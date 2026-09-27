import AppKit
import CubbyCore
import os

/// 截图覆盖层（§3.4.1 / §3.4.5）：持有唯一的 `ScreenshotSession`，单向数据流
///
/// NSEvent → `ScreenshotEvent` → `ScreenshotReducer.reduce` → 新会话 → 所有视图；
/// effects 驱动文字编辑器、提示 HUD、样式持久化、截图翻译流水线与结束。结束时先立即隐藏所有覆盖层窗口，
/// 再在后台导出，完成后回调委托（见 +Finish，暂停 / 恢复也在那里）。截图翻译的翻译条操作见 +Translation。
@MainActor
final class ScreenshotOverlayController: ScreenshotOverlayPresenting {
    /// 一块屏幕的窗口与根视图
    struct Screen {
        let window: OverlayWindow
        let view: OverlayScreenView
    }

    let capture: CaptureSession
    private(set) weak var delegate: (any ScreenshotOverlayDelegate)?
    private(set) var session: ScreenshotSession
    private(set) var screens: [Screen] = []
    private let keyboard = OverlayKeyboard()
    let pixelation = MosaicPixelation()
    private let hoverInfo = HoverInfoProvider()
    private(set) var editor: TextAnnotationEditor?
    /// 截图翻译（macOS 26+ 且协调器提供了服务时才有）
    private(set) var translation: OverlayTranslationController?
    // 以下四个状态由结束 / 暂停流程（+Finish）读写
    /// 覆盖层已隐藏、不再接收事件
    var isFinished = false
    /// 委托已收到结果（保证只回调一次）
    var didDeliver = false
    /// 暂停中（存储对话框 §9.4、翻译的「去设置」）：覆盖层已隐藏，但窗口与会话都保留，等待 resume() / dismiss()
    var isSuspended = false
    /// 进行中的后台导出；外部取消时中止
    var exportTask: Task<Void, Never>?
    private let cursors = OverlayCursorCache()
    private var annotationIndex = AnnotationIndex.empty
    /// 各覆盖层窗口成为 key 的通知
    private var keyObservers: [any NSObjectProtocol] = []
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ScreenshotOverlay")
    #if DEBUG
    /// 仅调试构建：导出前人为等待（e2e 用它复现「导出进行中再次触发快捷键」）
    var debugExportDelay: Duration = .zero
    #endif

    var phase: ScreenshotPhase { session.phase }
    /// 有标注或译文（会话中再按快捷键时不取消）
    var hasAnnotations: Bool { session.hasDiscardableContent }
    /// 出口已确认、覆盖层已隐藏，正在后台导出（结果尚未回调）
    var isFinishing: Bool { isFinished && !didDeliver && exportTask != nil }

    init(capture: CaptureSession, initial: ScreenshotSession, delegate: any ScreenshotOverlayDelegate) {
        self.capture = capture
        self.session = initial
        self.delegate = delegate
        pixelation.onReady = { [weak self] in self?.render() }
    }

    // MARK: - ScreenshotOverlayPresenting

    func present() {
        guard screens.isEmpty, !isFinished else { return }
        screens = capture.topology.screens.compactMap(makeScreen)
        guard !screens.isEmpty else {
            logger.error("No frames to present")
            deliverImmediately(.failed(.noScreen))
            return
        }
        installKeyboard()
        render()
        // 先提交图层内容再上屏，避免第一帧闪黑
        CATransaction.flush()
        screens.forEach { $0.window.orderFrontRegardless() }
        let mouse = OverlayScreens.mouseLocation
        (screen(containing: mouse) ?? screens.first)?.window.makeKey()
        // 普通会话的初始值可能还没算悬停目标：按当前光标补一次；调试场景的预置会话保持原样
        if session.phase == .hovering && session.hover == nil {
            send(.mouseMoved(mouse))
        }
        if session.phase == .editingText, let state = session.textEditing {
            beginTextEditing(state)
        }
        updateCursor(overChrome: false)
    }

    /// 外部取消（快捷键再按、显示器变化）：立即回调 `.cancel`。
    /// 导出进行中（用户已确认复制 / 保存等，覆盖层已隐藏）时不取消：等导出完成后按真实结果回调，
    /// 否则用户以为已经复制，剪贴板里却什么都没有
    func cancel() {
        guard !didDeliver, !isFinishing else { return }
        if !isFinished || isSuspended {
            tearDown()
        }
        deliver(.cancel)
    }

    /// 存储对话框取消：覆盖层带着点「存储」之前的会话（选区、标注、撤销栈）重新上屏
    func resume() {
        guard isSuspended, exportTask == nil, !didDeliver else { return }
        isSuspended = false
        isFinished = false
        installKeyboard()
        render()
        CATransaction.flush()
        screens.forEach { $0.window.orderFrontRegardless() }
        (selectionScreen() ?? screen(containing: OverlayScreens.mouseLocation) ?? screens.first)?.window.makeKey()
        updateCursor(overChrome: false)
    }

    func attachTranslation(_ services: ScreenshotTranslationServices) {
        translation = OverlayTranslationController(
            services: services,
            send: { [weak self] event in self?.send(.translation(event)) },
            hiddenRegions: { [weak self] in self?.session.translationHiddenRegions ?? [] },
            selection: { [weak self] in self?.session.selection },
            rerender: { [weak self] in self?.render() }
        )
    }

    /// 存储流程结束：释放暂停中的覆盖层，不再回调委托
    func dismiss() {
        guard !didDeliver else { return }
        didDeliver = true
        exportTask?.cancel()
        exportTask = nil
        tearDown()
    }

    // MARK: - 单向数据流

    func send(_ event: ScreenshotEvent) {
        // 暂停（存储对话框）期间流水线的回报照常交给会话：取消对话框回来时翻译已经走完，而不是永远停在「进行中」
        guard !isFinished || (isSuspended && event.isTranslationReport) else { return }
        let result = ScreenshotReducer.reduce(session, event: event, topology: capture.topology)
        session = result.session
        for effect in result.effects {
            handle(effect)
            if isFinished { return }
        }
        render()
    }

    private func handle(_ effect: ScreenshotEffect) {
        switch effect {
        case .finish(let outcome):
            finish(outcome)
        case .beginTextEditing(let state, _):
            beginTextEditing(state)
        case .endTextEditing:
            endTextEditing()
        case .stylesChanged(let styles):
            delegate?.overlay(self, didChangeStyles: styles)
        case .showHint(let hint):
            showHint(hint.message)
        case .translation(let effect):
            translation?.perform(effect, capture: capture)
        }
    }

    func render() {
        guard !isFinished else { return }
        annotationIndex = annotationIndex.updated(for: session.document)
        preparePixelationIfNeeded()
        translation?.track(session)
        let magnifier = OverlayRenderModel.magnifier(for: session, capture: capture)
        let hover = hoverInfo.model(for: session, topology: capture.topology)
        let toolbar = OverlayRenderModel.toolbarModel(for: session)
        let styleBar = OverlayRenderModel.styleBarModel(for: session)
        let translationBar = translation?.barModel(for: session)
        let translationChrome = translation?.chrome(for: session) ?? OverlayTranslationChrome()
        for screen in screens {
            let id = screen.view.space.screen.id
            var canvas = OverlayRenderModel.canvasState(
                for: session,
                screen: screen.view.space.screen,
                pixelated: pixelation.image(for: id),
                index: annotationIndex
            )
            canvas.translation = OverlayRenderModel.translationState(
                for: session, screen: screen.view.space.screen, outline: translationChrome.bubble?.block)
            screen.view.render(
                OverlayScreenView.Input(
                    session: session,
                    canvas: canvas,
                    magnifier: magnifier?.screenID == id ? magnifier?.reading : nil,
                    hoverInfo: hover,
                    toolbar: toolbar,
                    styleBar: styleBar,
                    translationBar: translationBar,
                    translation: translationChrome
                )
            )
        }
        editor?.update(style: session.activeStyle)
    }

    /// 马赛克工具激活或文档里有马赛克时，为选区所在屏与马赛克所在屏准备像素化副本
    private func preparePixelationIfNeeded() {
        guard OverlayRenderModel.needsPixelation(session) else { return }
        let mosaicBounds = annotationIndex.entries.filter { $0.annotation.tool == .mosaic }.map(\.bounds)
        for frame in capture.frames {
            let isSelectionScreen = frame.screen.id == session.screenID
            let hasMosaic = mosaicBounds.contains { !$0.isNull && $0.intersects(frame.screen.frame) }
            if isSelectionScreen || hasMosaic {
                pixelation.prepare(frame)
            }
        }
    }

    // MARK: - 输入

    private func makeScreen(_ captureScreen: CaptureScreen) -> Screen? {
        guard let frame = capture.frame(for: captureScreen.id) else { return nil }
        let window = OverlayWindow(screen: captureScreen, appKitFrame: OverlayScreens.appKitRect(captureScreen.frame))
        let view = OverlayScreenView(
            frame: frame,
            onToolbarAction: { [weak self] action in self?.toolbarAction(action) },
            onStyleChange: { [weak self] style in self?.send(.styleChanged(style)) },
            onTranslation: { [weak self] input in self?.translationInput(input) }
        )
        view.canvas.onMouseEvent = { [weak self, weak window, weak view] event in
            guard let self, let window, let view else { return }
            self.mouseEvent(event, window: window, view: view)
        }
        view.canvas.onCursorUpdate = { [weak self] in self?.updateCursor(overChrome: false) }
        window.contentView = view
        return Screen(window: window, view: view)
    }

    private func mouseEvent(_ event: NSEvent, window: OverlayWindow, view: OverlayScreenView) {
        let point = view.canvas.globalPoint(for: event)
        // 点击总是让本屏成为 key（系统弹窗抢走焦点后点击即可恢复，§2.12）；
        // 移动只在 key 仍属于覆盖层的另一块屏幕时跟过去，不从系统弹窗手里抢焦点；编辑文字时保留焦点
        if !window.isKeyWindow {
            let keyIsOverlay = screens.contains { $0.window === NSApp.keyWindow }
            let followsMove = event.type == .mouseMoved && keyIsOverlay && session.phase != .editingText
            if event.type == .leftMouseDown || followsMove {
                window.makeKey()
            }
        }
        if let translated = OverlayInteraction.event(for: event, at: point) {
            send(translated)
        }
        updateCursor(over: view, at: point)
    }

    private func toolbarAction(_ action: ScreenshotToolbarAction) {
        switch action {
        case .selectTool(let tool): send(.command(.selectTool(tool)))
        case .undo: send(.command(.undo))
        case .redo: send(.command(.redo))
        case .outcome(let outcome): send(.toolbarAction(outcome))
        case .translate: send(.command(.translate))
        }
    }

    private func installKeyboard() {
        keyboard.owns = { [weak self] window in
            guard let self, let window else { return false }
            return self.screens.contains { $0.window === window }
        }
        keyboard.context = { [weak self] in
            OverlayKeyboard.Context(
                phase: self?.session.phase ?? .hovering,
                isComposingText: self?.editor?.hasMarkedText ?? false
            )
        }
        keyboard.onOutput = { [weak self] output in
            guard let self else { return }
            switch output {
            case .event(let event):
                self.send(event)
            case .copyColor:
                // C 键：取放大镜第二行当前显示的文本（reducer 拿不到像素）
                let text = OverlayRenderModel.magnifier(for: self.session, capture: self.capture)?.reading.colorText
                if let text, !text.isEmpty {
                    self.send(.toolbarAction(.copyColor(text)))
                }
            }
            self.updateCursor(overChrome: false)
        }
        keyboard.install()
        // 焦点被抢走期间的松开事件到不了 Cubby：覆盖层重新成为 key 时按系统当前的修饰键状态重置
        keyObservers = screens.map { screen in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: screen.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboard.resynchronize() }
            }
        }
    }

    private func updateCursor(overChrome: Bool) {
        guard !isFinished else { return }
        // 文字编辑框上是文本视图的 I 形光标：鼠标移动、修饰键变化时都不能改成箭头
        if isOverEditor(session.cursor) {
            NSCursor.iBeam.set()
            return
        }
        (overChrome ? NSCursor.arrow : cursors.cursor(for: session.cursorKind)).set()
    }

    /// 工具栏 / 翻译条上是箭头；卷帘分隔线上是左右调整；其余按会话
    private func updateCursor(over view: OverlayScreenView, at point: CGPoint) {
        if !isFinished, !isOverEditor(point), view.isOverWipeHandle(point) {
            NSCursor.resizeLeftRight.set()
            return
        }
        updateCursor(overChrome: view.isOverChrome(point))
    }

    // MARK: - 文字编辑

    private func isOverEditor(_ point: CGPoint) -> Bool {
        guard let editor, let view = editor.superview as? OverlayScreenView else { return false }
        return editor.frame.contains(view.space.viewPoint(point))
    }

    private func beginTextEditing(_ state: TextEditingState) {
        endTextEditing()
        guard let target = screen(containing: state.origin) ?? selectionScreen() else { return }
        let editor = TextAnnotationEditor(state: state, style: session.activeStyle, space: target.view.space)
        editor.onTextChange = { [weak self] text in self?.send(.textChanged(text)) }
        target.view.addEditor(editor)
        if !target.window.isKeyWindow {
            target.window.makeKey()
        }
        editor.focus()
        self.editor = editor
    }

    /// 文本已由 reducer 提交，这里只移除编辑器并把焦点还给窗口
    private func endTextEditing() {
        guard let editor else { return }
        let window = editor.window
        editor.removeFromSuperview()
        self.editor = nil
        window?.makeFirstResponder(nil)
    }

    // MARK: - 提示

    /// 提示显示在选区中心（没有选区时在光标处）
    private func showHint(_ message: String) {
        let anchor = session.selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? session.cursor
        (screen(containing: anchor) ?? screens.first)?.view.showHint(message, at: anchor)
    }

    /// 立即隐藏所有覆盖层（无淡出，§2.3 finishing）并释放；视图与位图在下一轮事件循环释放，
    /// 避免在工具栏按钮自己的事件处理中移除它
    func tearDown() {
        isFinished = true
        isSuspended = false
        translation?.cancel()
        hide()
        release()
    }

    /// 隐藏窗口、停止接收键盘；窗口与视图保留（「存储」暂停时还要恢复）
    func hide() {
        keyboard.remove()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        screens.forEach { $0.window.orderOut(nil) }
        NSCursor.arrow.set()
    }

    private func release() {
        let released = screens
        screens = []
        editor = nil
        Task { @MainActor in
            for screen in released {
                screen.window.contentView = nil
                screen.window.close()
            }
        }
    }

    // MARK: - 工具

    private func screen(containing point: CGPoint) -> Screen? {
        screens.first { $0.view.space.screen.contains(point) }
    }

    private func selectionScreen() -> Screen? {
        screens.first { $0.view.space.screen.id == session.screenID }
    }
}
