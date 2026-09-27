import AppKit
import os
import SwiftUI
import CubbyCore

/// 管理面板的显示、定位、动画、键盘事件与粘贴流程
@MainActor
final class PanelController {
    /// 面板的呼出方式，决定出现位置
    enum Trigger {
        case hotKey
        /// 点击菜单栏图标，参数为图标在屏幕上的位置
        case statusItem(CGRect)
    }

    private static let panelSize = NSSize(width: 380, height: 620)
    /// 点击菜单栏图标关闭面板时，忽略紧随其后的同一次点击，避免关闭后立即重新打开
    private static let reopenGuard: TimeInterval = 0.3
    /// 面板隐藏后缩略图缓存再保留这么久才清空：与「30 秒内重开保留分类」一致，
    /// 连续复制粘贴时重开不必重新解码；更久不用时释放这部分内存（常驻菜单栏）
    private static let thumbnailRetention: Duration = .seconds(30)

    var openSettings: (() -> Void)?
    /// 帮助浮层的「完整使用说明…」：面板先无动画隐藏，再打开使用说明窗口
    var openUserGuide: (() -> Void)?
    /// 面板顶栏相机按钮：面板先无动画隐藏（不能出现在冻结帧里），再开始截图
    var takeScreenshot: (() -> Void)?
    /// 最近一次点击菜单栏图标的位置，用于「菜单栏图标下方」模式
    var statusItemFrame: (() -> CGRect?)?
    /// 把历史图片贴到屏幕上（由 AppDelegate 注入 PinnedImageController.pin）
    var pinImage: ((HistoryImagePin) -> Void)?
    /// 剪贴板翻译（C3 在 AppDelegate 里接线）；nil 或 macOS 26 以下时所有翻译入口隐藏（设计文档 K8）
    var clipTranslation: (any ClipTranslating)? {
        didSet { configureTranslation() }
    }
    /// 翻译交互的时长（E2E 换成更短的值；须在设置 clipTranslation 之前设置）
    var translationTimings = TranslationTimings()
    #if DEBUG
    /// 面板 E2E：其他进程抢走焦点时不收起
    var debugKeepsOpen = false
    /// 面板 E2E：固定粘贴目标（只用于显示与「按应用记住目标语言」，不参与真实粘贴）
    var debugPasteTarget: PasteTarget?
    #endif
    // 以下几项供同模块的扩展使用（翻译接线：PanelController+Translation；调试：PanelController+Debug）
    let panel = ClipPanel(size: PanelController.panelSize)
    let preview: PreviewPanelController
    let viewModel: PanelViewModel
    let store: ClipStore
    private let settings: AppSettings
    let paster: PanelPaster
    private let keyboard = PanelKeyboard()
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Panel")

    private(set) var isShown = false
    private var lastHiddenAt: Date?
    /// 面板落位后的最终位置：入场动画进行中打开预览时，预览按它对齐而不是按动画中的帧
    private var restingFrame: CGRect?
    /// 用于丢弃过期的隐藏动画回调
    private var generation = 0

    /// - Parameter pasteboard: 粘贴写入的剪贴板（E2E 注入命名剪贴板）
    init(store: ClipStore, settings: AppSettings, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.settings = settings
        self.paster = PanelPaster(store: store, settings: settings, pasteboard: pasteboard)
        self.viewModel = PanelViewModel(store: store, settings: settings)
        self.preview = PreviewPanelController(viewModel: viewModel)

        let hostingView = FirstMouseHostingView(rootView: PanelView(viewModel: viewModel))
        // 面板尺寸由我们控制，不让 SwiftUI 反向调整窗口大小
        hostingView.sizingOptions = []
        panel.contentView = PanelChrome.makeContainer(for: hostingView)

        panel.onResignKey = { [weak self] in
            #if DEBUG
            // 截图走查：并行运行的其他进程抢走焦点时面板不收起，保证截得到
            if CommandLine.arguments.contains("--keep-panel") || self?.debugKeepsOpen == true { return }
            #endif
            self?.hide()
        }
        viewModel.onPaste = { [weak self] item, mode in self?.perform(item, mode: mode) }
        viewModel.onClose = { [weak self] in self?.hide() }
        viewModel.onOpenSettings = { [weak self] in
            self?.hide(animated: false)
            self?.openSettings?()
        }
        viewModel.onOpenUserGuide = { [weak self] in
            self?.hide(animated: false)
            self?.openUserGuide?()
        }
        viewModel.onTakeScreenshot = { [weak self] in
            self?.hide(animated: false)
            self?.takeScreenshot?()
        }
        viewModel.onDetailPaneChange = { [weak self] pane in self?.updateDetail(pane) }
        viewModel.onPinImage = { [weak self] item in self?.pinToScreen(item) }
        keyboard.handler = { [weak self] event in self?.handleKeyDown(event) ?? false }
        keyboard.onOptionChange = { [weak self] isDown in self?.viewModel.optionKeyChanged(isDown: isDown) }
        keyboard.onPointerDown = { [weak self] in self?.viewModel.pointerPressed() }
    }

    func toggle(_ trigger: Trigger = .hotKey) {
        if isShown {
            hide()
        } else if let lastHiddenAt, Date().timeIntervalSince(lastHiddenAt) < Self.reopenGuard,
            case .statusItem = trigger
        {
            // 点击图标导致面板失焦关闭，这次点击本意就是关闭
            return
        } else {
            show(trigger)
        }
    }

    func show(_ trigger: Trigger = .hotKey) {
        guard !isShown else { return }
        #if DEBUG
        let target = debugPasteTarget ?? PasteTarget.current()
        #else
        let target = PasteTarget.current()
        #endif
        guard let frame = targetFrame(for: trigger) else { return }

        generation += 1
        isShown = true
        restingFrame = frame
        ImageCache.shared.cancelScheduledPurge()
        viewModel.prepareForDisplay(
            target: target,
            warnings: PanelWarning.current(
                pasteDirectly: settings.pasteDirectly,
                isPaused: settings.isPaused,
                loadIssue: store.loadIssue
            ),
            canPasteDirectly: settings.pasteDirectly && PasteService.isTrusted
        )
        present(at: frame)
        keyboard.install(for: panel)
    }

    /// 入场：从上方 entranceOffset 处淡入并落位；减弱动态效果时原地短淡入
    private func present(at frame: CGRect) {
        let reduceMotion = Motion.prefersReducedMotion
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: Motion.entranceOffset), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? Motion.fade : Motion.panelEntrance
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    func hide(animated: Bool = true) {
        // orderOut 会触发 resignKey 回调，这里保证只执行一次
        guard isShown else { return }
        isShown = false
        lastHiddenAt = Date()
        restingFrame = nil
        generation += 1
        keyboard.remove()
        viewModel.panelDidHide()
        ImageCache.shared.purgeThumbnails(after: Self.thumbnailRetention)

        guard animated else {
            panel.orderOut(nil)
            return
        }
        let current = generation
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Motion.fade
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.panel.orderOut(nil)
                }
            })
    }

    // MARK: - 定位

    private func targetFrame(for trigger: Trigger) -> CGRect? {
        let size = Self.panelSize
        switch (trigger, settings.panelPosition) {
        case (.statusItem(let anchor), _):
            return screen(containing: anchor.origin).map {
                PanelPlacement.frame(size: size, below: anchor, visibleFrame: $0.visibleFrame)
            }
        case (.hotKey, .statusItem):
            if let anchor = statusItemFrame?(), let screen = screen(containing: anchor.origin) {
                return PanelPlacement.frame(size: size, below: anchor, visibleFrame: screen.visibleFrame)
            }
            return mouseFrame(size)
        case (.hotKey, .center):
            let mouse = NSEvent.mouseLocation
            return screen(containing: mouse).map { PanelPlacement.centered(size: size, in: $0.visibleFrame) }
        case (.hotKey, .mouse):
            return mouseFrame(size)
        }
    }

    private func mouseFrame(_ size: CGSize) -> CGRect? {
        let mouse = NSEvent.mouseLocation
        return screen(containing: mouse).map {
            PanelPlacement.frame(size: size, mouse: mouse, visibleFrame: $0.visibleFrame)
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// 详情区：隐藏、显示，或在预览与翻译卡之间切换（同一窗口，只调整高度）
    private func updateDetail(_ pane: DetailPane?) {
        guard pane != nil, isShown, let screen = panel.screen ?? NSScreen.main else {
            preview.hide()
            return
        }
        if preview.isVisible {
            preview.relayout()
        } else {
            preview.show(beside: restingFrame ?? panel.frame, visibleFrame: screen.visibleFrame)
        }
    }

    // MARK: - 贴到屏幕

    /// 面板先无动画收起（贴图出现在屏幕中央，不应被面板挡住），再在面板所在屏幕的中央贴图；
    /// 图片文件已被清理等原因贴不出来时，在原面板位置提示
    private func pinToScreen(_ item: ClipItem) {
        let anchor = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let pinImage, let url = store.imageURL(for: item),
            let screen = panel.screen ?? screen(containing: NSEvent.mouseLocation)
        else {
            Self.showPinFailure(at: anchor)
            return
        }
        hide(animated: false)
        Task { @MainActor [logger] in
            guard let pin = await HistoryImagePinning.load(url: url, on: screen) else {
                logger.error("Failed to decode the image to pin")
                Self.showPinFailure(at: anchor)
                return
            }
            pinImage(pin)
        }
    }

    private static func showPinFailure(at anchor: CGPoint) {
        NSSound.beep()
        HUDToast.show(
            String(localized: "Image file is missing", comment: "Error when copying an image item"),
            symbolName: "exclamationmark.triangle.fill",
            tint: .orange,
            at: anchor
        )
    }

    // MARK: - 粘贴

    private func perform(_ item: ClipItem, mode: PasteMode) {
        if let failure = paster.write(item, mode: mode) {
            NSSound.beep()
            viewModel.showToast(.error(failure))
            return
        }
        paster.deliver(
            promoting: item.id, copyOnly: mode == .copyOnly, target: viewModel.target, anchor: anchor,
            copied: PanelPaster.copiedMessage, pasted: nil
        ) { hide(animated: false) }
    }

    /// 面板中心（面板关闭后 HUD 显示在这里）
    var anchor: CGPoint {
        CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    }

    // MARK: - 键盘

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 输入法组字过程中（如拼音候选），方向键 / 回车 / 空格交给输入法处理
        guard event.window === panel, !isComposingText else { return false }
        let command = PanelCommand.from(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            characters: event.charactersIgnoringModifiers,
            allowsSpace: viewModel.searchText.isEmpty,
            translationCardOpen: viewModel.isTranslationCardOpen
        )
        // 任何其他按键都取消「按住 ⌥ 预览」（⌥↩ 粘贴正在显示的内容）
        viewModel.keyPressed(isOptionReturn: command == .translateAndPaste, isEscape: command == .escape)
        guard let command else { return false }
        // 搜索框里选中了文字时 ⌘C 仍是「拷贝」
        if command == .copyTranslation, hasSearchSelection { return false }
        return viewModel.handle(command)
    }

    private var isComposingText: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private var hasSearchSelection: Bool {
        ((panel.firstResponder as? NSTextView)?.selectedRange().length ?? 0) > 0
    }
}
