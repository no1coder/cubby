import AppKit
import CubbyCore
import os

/// 截图的触发来源
enum ScreenshotTrigger: Equatable {
    case hotKey
    case menu
    case panelButton
    #if DEBUG
    /// 调试构建 --scenario screenshot:<名称>（Release 中不存在）
    case debugScenario(String)
    #endif

    /// 日志用的固定名称（不含任何用户内容）
    var logName: String {
        switch self {
        case .hotKey: "hotKey"
        case .menu: "menu"
        case .panelButton: "panelButton"
        #if DEBUG
        case .debugScenario: "debugScenario"
        #endif
        }
    }
}

/// 截图的唯一入口：快捷键、菜单栏、面板按钮都调用 start(_:)。
/// 流程：权限检查 → 隐藏面板 → 采集所有屏幕（2 s 超时）→ 覆盖层 → 按结果输出。
/// 全程不激活 Cubby（覆盖层是不激活应用的面板），结束后前台应用不变
@MainActor
final class ScreenshotCoordinator: ScreenshotOverlayDelegate {
    typealias OverlayFactory =
        @MainActor (CaptureSession, ScreenshotSession, any ScreenshotOverlayDelegate) -> any ScreenshotOverlayPresenting

    /// 采集超时（设计文档 §2.12、§6 R2）
    static let captureTimeout: Duration = .seconds(2)
    /// 覆盖层交付前的占位：记录采集概况后立即取消
    static let placeholderOverlay: OverlayFactory = { NoOverlay(capture: $0, initial: $1, delegate: $2) }

    /// 由覆盖层类型生成工厂，例如 `ScreenshotCoordinator.overlayFactory(ScreenshotOverlayController.self)`
    static func overlayFactory<Overlay: ScreenshotOverlayPresenting>(_ type: Overlay.Type) -> OverlayFactory {
        { Overlay(capture: $0, initial: $1, delegate: $2) }
    }

    /// screens：开始时的屏幕布局，用于判断「屏幕参数变化」通知是否真的改变了布局
    enum State {
        case idle
        case capturing(Task<Void, Never>, screens: [CaptureScreen])
        case presenting(Presentation)
        /// 纯净窗口截图：覆盖层已关闭，正在单独采集窗口
        case capturingWindow(Task<Void, Never>, screens: [CaptureScreen])
        /// 覆盖层暂停（隐藏但保留会话）：存储对话框打开中（§9.4），或截图翻译的「去设置」「下载语言」进行中
        case suspended(Presentation, Suspension)
    }

    /// 覆盖层暂停的原因
    enum Suspension {
        case saving
        case resolvingTranslation
    }

    /// 覆盖层显示期间需要保留的上下文
    struct Presentation {
        let overlay: any ScreenshotOverlayPresenting
        let capture: CaptureSession
        let windowSource: any WindowImageSource
        let screens: [CaptureScreen]
    }

    let settings: AppSettings
    let pins: PinnedImageController
    let guide = ScreenRecordingGuideWindowController()
    let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")
    private let frameSource: any FrameSource
    private let windowSource: any WindowImageSource
    private let overlayFactory: OverlayFactory
    let output: ScreenshotOutputService
    /// 截图「存储」的位置选择（§9.4）
    let savePrompt: any SaveDestinationPrompting
    /// 截图翻译的设置与引擎（docs/TRANSLATION-DESIGN.md §4.3）；nil = 不提供翻译（工具栏不显示翻译按钮）
    var translation: (any TranslationProviding)?
    /// 截图翻译的文字识别与分块
    var translationRecognizer: (any TranslationTextRecognizing)?
    #if DEBUG
    /// 仅调试构建：覆盖层上屏后执行（调试场景用它自动触发存储等动作）
    var debugAfterPresent: (@MainActor (any ScreenshotOverlayPresenting) -> Void)?
    #endif
    /// 采集前的准备（隐藏面板等），保证 Cubby 自己的界面不出现在冻结帧里
    private let beforeCapture: @MainActor () -> Void
    /// 会话状态（+Translation 的暂停 / 恢复也读写它）
    var state = State.idle
    /// 每次开始采集递增：丢弃已取消会话迟到的回调
    private var generation = 0
    /// 覆盖层暂停期间屏幕布局变了：取消存储 / 解决完翻译问题时不再恢复覆盖层（冻结帧与新布局对不上）
    var layoutChangedWhileSuspended = false
    /// 存储对话框、翻译设置激活了 Cubby：会话结束时把前台还给截图前的应用
    var focusToRestore: FocusRestorer?

    init(
        settings: AppSettings,
        store: ClipStore,
        frameSource: any FrameSource = FrozenFrameCapturer(),
        windowSource: any WindowImageSource = WindowImageCapturer(),
        overlayFactory: @escaping OverlayFactory = ScreenshotCoordinator.placeholderOverlay,
        pins: PinnedImageController,
        pasteboard: NSPasteboard = .general,
        savePrompt: any SaveDestinationPrompting = ScreenshotSavePrompt.shared,
        beforeCapture: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.pins = pins
        self.frameSource = frameSource
        self.windowSource = windowSource
        self.overlayFactory = overlayFactory
        self.beforeCapture = beforeCapture
        self.savePrompt = savePrompt
        self.output = ScreenshotOutputService(
            settings: settings, store: store, recognizer: TextRecognizer(), pins: pins, pasteboard: pasteboard)
        guide.onGranted = { [weak self] in self?.showReadyHint() }
        observeScreenChanges()
    }

    /// 会话进行中（从开始采集到覆盖层结束）
    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    func start(_ trigger: ScreenshotTrigger) {
        guard !isActive else {
            // 会话中再按快捷键按 Q2 处理；菜单与面板按钮此时不可见，忽略
            if trigger == .hotKey { hotKeyPressedWhileActive() }
            return
        }
        #if DEBUG
        if case .debugScenario(let name) = trigger {
            startDebugScenario(name)
            return
        }
        #endif
        logger.info("Screenshot requested via \(trigger.logName, privacy: .public)")
        startLiveCapture()
    }

    /// 真实采集：权限检查后开始
    func startLiveCapture() {
        guard ensureAuthorized() else { return }
        let styles = settings.annotationStyles
        begin(frameSource: frameSource, windowSource: windowSource) { capture in
            let cursor = ScreenTopologyProvider.toGlobal(NSEvent.mouseLocation)
            return ScreenshotSession.initial(styles: styles, cursor: cursor, topology: capture.topology)
        }
    }

    /// 会话中再按快捷键（Q2）：无标注且不在编辑文字时取消，否则忽略（一次误触不能毁掉已画的标注）。
    /// 存储对话框打开中：把对话框提到前面。理由：用户已经确认要存储、截图还在等位置，
    /// 此时多半是对话框被别的窗口挡住了；开始新截图会把对话框本身截进去，取消又会丢掉已画的标注。
    /// 翻译的「去设置」「下载语言」进行中：同理不开始新截图也不取消（把设置 / 下载界面提到前面是 provider 的事）
    func hotKeyPressedWhileActive() {
        switch state {
        case .idle, .capturingWindow:
            return
        case .suspended(_, .saving):
            savePrompt.bringToFront()
        case .suspended(_, .resolvingTranslation):
            // 设置窗口与语言下载窗口都是 Cubby 自己的窗口：把 Cubby 提到前面即可看到它们
            logger.info("Shortcut ignored: translation settings are open")
            NSApp.activate()
        case .capturing(let task, _):
            task.cancel()
            state = .idle
        case .presenting(let presentation):
            let overlay = presentation.overlay
            // 导出进行中：用户已确认出口，结果马上就到
            guard !overlay.isFinishing else {
                logger.info("Shortcut ignored: the screenshot is being exported")
                return
            }
            guard overlay.phase != .editingText, !overlay.hasAnnotations else {
                logger.info("Shortcut ignored: the screenshot has annotations")
                return
            }
            overlay.cancel()
        }
    }

    /// 显示器插拔 / 分辨率变化：冻结帧与新布局对不上，取消会话。
    /// 该通知在程序坞、菜单栏自动显隐、显示器唤醒时也会发出，因此先比较屏幕布局，没变就不打扰（保住已画的标注）
    func screenParametersDidChange() {
        let current = ScreenTopologyProvider.screens()
        switch state {
        case .idle:
            return
        case .capturing(let task, let screens), .capturingWindow(let task, let screens):
            guard screens != current else { return }
            task.cancel()
            state = .idle
        case .presenting(let presentation):
            // 导出进行中不受影响：冻结帧已经在手，照常交付
            guard presentation.screens != current, !presentation.overlay.isFinishing else { return }
            presentation.overlay.cancel()
        case .suspended(let presentation, _):
            // 导出已完成、对话框打开中：照常存储；用户取消时不再恢复覆盖层（见 saveDestinationChosen）
            guard presentation.screens != current else { return }
            layoutChangedWhileSuspended = true
            logger.notice("Screen layout changed while the overlay is suspended")
            return
        }
        logger.notice("Screen layout changed, screenshot cancelled")
        warn(
            String(
                localized: "Screen layout changed", comment: "HUD when a screenshot is cancelled by a display change"))
    }

    // MARK: - 采集与覆盖层

    /// makeSession 返回 nil 时放弃（例如未知的调试场景名）
    func begin(
        frameSource: any FrameSource,
        windowSource: any WindowImageSource,
        makeSession: @escaping @MainActor (CaptureSession) -> ScreenshotSession?
    ) {
        beforeCapture()
        generation += 1
        let current = generation
        let clock = ContinuousClock()
        let started = clock.now
        let keptWindows = pins.windowIDs
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screens = ScreenTopologyProvider.screens()
        let task = Task { [weak self] in
            do {
                let capture = try await frameSource.capture(
                    excludingPID: ownPID, exceptWindowIDs: keptWindows, timeout: Self.captureTimeout)
                let captured = clock.now - started
                self?.present(
                    capture, generation: current, windowSource: windowSource, screens: screens,
                    makeSession: makeSession
                ) {
                    (captured, clock.now - started)
                }
            } catch {
                self?.captureFailed(error, generation: current)
            }
        }
        state = .capturing(task, screens: screens)
    }

    private func present(
        _ capture: CaptureSession,
        generation: Int,
        windowSource: any WindowImageSource,
        screens: [CaptureScreen],
        makeSession: @MainActor (CaptureSession) -> ScreenshotSession?,
        timing: () -> (captured: Duration, total: Duration)
    ) {
        guard generation == self.generation, case .capturing = state else { return }
        guard let session = makeSession(capture) else {
            logger.error("No initial screenshot session, cancelled")
            state = .idle
            return
        }
        // 截图翻译：macOS 26+ 且提供了服务才可用（会话据此决定 ⇧⌘T 是否生效，工具栏据此显示按钮）
        let services = translationServices
        let overlay = overlayFactory(capture, session.settingTranslationAvailable(services != nil), self)
        if let services {
            overlay.attachTranslation(services)
        }
        state = .presenting(
            Presentation(overlay: overlay, capture: capture, windowSource: windowSource, screens: screens))
        overlay.present()
        #if DEBUG
        debugAfterPresent?(overlay)
        debugAfterPresent = nil
        #endif
        let (captured, total) = timing()
        logger.notice(
            """
            Screenshot overlay shown in \(FrozenFrameCapturer.milliseconds(total), privacy: .public) ms \
            (capture \(FrozenFrameCapturer.milliseconds(captured), privacy: .public) ms)
            """
        )
    }

    private func captureFailed(_ error: any Error, generation: Int) {
        guard generation == self.generation, case .capturing = state else { return }
        state = .idle
        guard !(error is CancellationError) else { return }
        let failure = FrozenFrameCapturer.mapped(error)
        logger.error("Screen capture failed: \(failure.logName, privacy: .public)")
        if case .notAuthorized = failure {
            guide.show()
        } else {
            warn(
                String(
                    localized: "Couldn't capture the screen. Check the permission prompt.",
                    comment: "HUD when capturing the screen fails or times out"))
        }
    }

    // MARK: - ScreenshotOverlayDelegate

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didFinishWith result: ScreenshotResult) {
        guard let presentation = session(of: overlay) else { return }
        state = .idle
        handle(result, presentation: presentation)
        restoreFocus()
    }

    /// 「存储」：设置里关闭了「每次询问」就直接存入默认文件夹；否则弹出存储对话框（§9.4）
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestSave export: ScreenshotExport) {
        guard case .presenting(let presentation) = state, presentation.overlay === overlay else {
            overlay.dismiss()
            return
        }
        guard settings.asksWhereToSaveScreenshots else {
            state = .idle
            overlay.dismiss()
            output.save(export)
            restoreFocus()
            return
        }
        state = .suspended(presentation, .saving)
        // 导出期间（isFinishing）的屏幕变化被刻意忽略过，这里补查一次，免得取消后把旧冻结帧恢复到新布局上
        layoutChangedWhileSuspended = presentation.screens != ScreenTopologyProvider.screens()
        focusToRestore = focusToRestore ?? FocusRestorer.capture()
        let name = ScreenshotFileNaming.fileName(date: Date())
        let directory = ScreenshotSaveLocation.resolved(preferred: settings.screenshotSaveDirectory)
        let screen = ScreenTopologyProvider.nsScreen(for: export.screen)
        Task { [weak self, savePrompt] in
            let url = await savePrompt.chooseDestination(suggestedName: name, directory: directory, screen: screen)
            self?.saveDestinationChosen(url, export: export, overlay: overlay)
        }
    }

    /// 选定位置 → 写入并释放覆盖层；取消 → 覆盖层带着标注回来（布局变了则结束会话）
    private func saveDestinationChosen(
        _ url: URL?,
        export: ScreenshotExport,
        overlay: any ScreenshotOverlayPresenting
    ) {
        guard case .suspended(let presentation, .saving) = state, presentation.overlay === overlay else {
            overlay.dismiss()
            // 会话已在对话框打开期间结束：归还前台，免得过期的 focusToRestore 被下一次会话沿用
            if case .idle = state { restoreFocus() }
            return
        }
        if let url {
            state = .idle
            overlay.dismiss()
            output.save(export, to: url)
            restoreFocus()
        } else if layoutChangedWhileSuspended {
            state = .idle
            overlay.dismiss()
            restoreFocus()
            warn(
                String(
                    localized: "Screen layout changed",
                    comment: "HUD when a screenshot is cancelled by a display change"))
        } else {
            // 焦点留在 Cubby：覆盖层恢复后要继续接收键盘；会话结束时再归还
            state = .presenting(presentation)
            overlay.resume()
        }
    }

    /// 覆盖层所属的当前会话：上屏中，或暂停中（暂停态的覆盖层同样可能被取消）
    private func session(of overlay: any ScreenshotOverlayPresenting) -> Presentation? {
        switch state {
        case .presenting(let presentation), .suspended(let presentation, _):
            presentation.overlay === overlay ? presentation : nil
        default:
            nil
        }
    }

    /// 会话结束：存储对话框曾激活 Cubby 时，把前台还给截图前的应用
    func restoreFocus() {
        focusToRestore?.restore()
        focusToRestore = nil
    }

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didChangeStyles styles: ToolStyles) {
        settings.annotationStyles = styles
    }

    // MARK: - 输出

    private func handle(_ result: ScreenshotResult, presentation: Presentation) {
        switch result {
        case .copy(let export): output.copy(export)
        case .pin(let export): output.pin(export)
        case .extractText(let export, let clean):
            output.extractText(from: clean, anchor: ScreenshotOutputService.anchor(for: export.selection))
        case .copyColor(let text): output.copyColor(text, anchor: NSEvent.mouseLocation)
        case .translatedText(let text, let selection): copyExtractedTranslation(text, selection: selection)
        case .captureWindow(let windowID, let includeShadow):
            captureWindow(windowID, includeShadow: includeShadow, presentation: presentation)
        case .cancel: break
        case .failed(let failure):
            logger.error("Screenshot failed: \(String(describing: failure), privacy: .public)")
            warn(String(localized: "Couldn't create the screenshot", comment: "HUD when exporting a screenshot fails"))
        }
    }

    /// 覆盖层关闭后再单独采集该窗口（不受遮挡，圆角外透明）；采集期间会话仍算进行中
    private func captureWindow(_ windowID: UInt32, includeShadow: Bool, presentation: Presentation) {
        let window = presentation.capture.topology.windows.first { $0.id == windowID }
        let anchor =
            window.map { ScreenTopologyProvider.toAppKit(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            ?? NSEvent.mouseLocation
        let source = presentation.windowSource
        generation += 1
        let current = generation
        let task = Task { [weak self] in
            do {
                let image = try await source.captureWindow(
                    id: windowID, includeShadow: includeShadow, timeout: Self.captureTimeout)
                self?.windowCaptured(image, anchor: anchor, generation: current)
            } catch {
                self?.windowCaptureFailed(error, generation: current)
            }
        }
        state = .capturingWindow(task, screens: presentation.screens)
    }

    private func windowCaptured(_ image: WindowImage, anchor: CGPoint, generation: Int) {
        guard generation == self.generation, case .capturingWindow = state else { return }
        state = .idle
        output.copyWindow(image, anchor: anchor)
    }

    private func windowCaptureFailed(_ error: any Error, generation: Int) {
        guard generation == self.generation, case .capturingWindow = state else { return }
        state = .idle
        guard !(error is CancellationError) else { return }
        logger.error("Window capture failed: \(FrozenFrameCapturer.mapped(error).logName, privacy: .public)")
        warn(String(localized: "Couldn't capture the window", comment: "HUD when a window screenshot fails"))
    }

    // MARK: - 权限

    /// 已授权返回 true；否则申请（每次启动最多一次系统弹窗）并显示引导窗口，不开始截图
    private func ensureAuthorized() -> Bool {
        guard ScreenRecordingAuthorization.status != .granted else { return true }
        if ScreenRecordingAuthorization.request() { return true }
        logger.info("Screen recording not granted, showing the guide")
        guide.show()
        return false
    }

    /// 引导窗口发现已授权后：提示如何截图。不自动开始，因为 macOS 常要求重启应用才生效
    private func showReadyHint() {
        guard let shortcut = settings.screenshotHotKey, let anchor = HUDToast.defaultAnchor() else { return }
        HUDToast.show(
            String(
                localized: "Press \(shortcut.displayName) to take a screenshot",
                comment: "HUD after granting Screen Recording. %@ = screenshot shortcut"
            ),
            symbolName: "camera.viewfinder",
            tint: .accentColor,
            at: anchor
        )
    }

    // MARK: - 辅助

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersDidChange() }
        }
    }

    func warn(_ message: String) {
        guard let anchor = HUDToast.defaultAnchor() else { return }
        HUDToast.show(message, symbolName: "exclamationmark.triangle.fill", tint: .orange, at: anchor)
    }
}
