#if DEBUG
import AppKit
import CubbyCore

/// 一条端到端脚本的隔离环境：独立的偏好设置域、历史目录、保存目录、命名剪贴板、贴图与协调器。
/// 采集一律用 FixtureFrameSource（合成桌面），不读取真实屏幕，也不碰系统剪贴板与真实数据目录
@MainActor
final class E2EWorld {
    /// 纯净窗口截图的来源
    enum WindowSourceKind {
        /// FixtureFrameSource：按假窗口绘制，成功
        case fixture
        /// 模拟真实采集找不到假窗口 id（与 WindowImageCapturer 的 windowNotFound 相同）
        case failing
    }

    /// 截图翻译的桩（nil = 不提供翻译：工具栏没有翻译按钮，与既有脚本一致）
    struct TranslationSetup {
        enum Recognizer {
            /// 夹具文字上的确定性块
            case stub
            /// 真实的 VisionTranslationRecognizer（对夹具画面做识别）
            case vision
        }

        var script = E2ETranslationProvider.Script()
        var recognizer = Recognizer.stub
    }

    struct Options {
        var isPaused = false
        var translation: TranslationSetup?
        var windowSource = WindowSourceKind.fixture
        /// 导出前的人为延迟（复现「导出进行中再次触发」）
        var exportDelay: Duration = .zero
        /// 设置「每次存储前询问位置」
        var asksWhereToSave = true
    }

    let directory: URL
    let saveDirectory: URL
    /// 存储对话框（桩）里「选择」的另一个文件夹：验证写入所选位置、记住上次的文件夹
    let pickedDirectory: URL
    /// 存储位置选择的桩（截图与贴图共用）
    let savePrompt = E2ESavePrompt()
    let pasteboard: NSPasteboard
    let settings: AppSettings
    let store: ClipStore
    let pins: PinnedImageController
    let screen: CaptureScreen
    /// 截图翻译的桩 provider 与识别器（Options.translation 为 nil 时没有）
    let translationProvider: E2ETranslationProvider?
    let stubRecognizer: E2EStubRecognizer?
    private(set) var coordinator: ScreenshotCoordinator?
    /// 本环境创建过的全部覆盖层（保留强引用：会话结束后仍可读取最终状态）
    private(set) var overlays: [ScreenshotOverlayController] = []
    /// 覆盖层交给协调器的结果（按顺序，文字描述）
    var results: [String] {
        recorder.results
    }

    /// 最近一次采集（拓扑与帧）
    private(set) var lastCapture: CaptureSession?
    private let recorder = E2EResultRecorder()

    private let options: Options
    private let fixture: FixtureFrameSource

    init(name: String, root: URL, options: Options) throws {
        guard let primary = ScreenTopologyProvider.screens().first else { throw E2EWorldError.noScreen }
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saveDirectory = directory.appendingPathComponent("Saved", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let pickedDirectory = directory.appendingPathComponent("Picked", isDirectory: true)
        try FileManager.default.createDirectory(at: pickedDirectory, withIntermediateDirectories: true)
        // 以绝对路径作为 suite 名：偏好设置写到本环境目录下的 defaults.plist，不进 ~/Library/Preferences
        guard let defaults = UserDefaults(suiteName: directory.appendingPathComponent("defaults").path) else {
            throw E2EWorldError.noDefaults
        }

        self.directory = directory
        self.saveDirectory = saveDirectory
        self.pickedDirectory = pickedDirectory
        self.options = options
        self.screen = primary
        self.fixture = FixtureFrameSource(screens: ScreenTopologyProvider.screens())
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.no1coder.Cubby.e2e.\(name)"))
        pasteboard.clearContents()
        settings = AppSettings(defaults: defaults)
        settings.screenshotSaveDirectory = saveDirectory
        settings.isPaused = options.isPaused
        settings.asksWhereToSaveScreenshots = options.asksWhereToSave
        store = ClipStore(
            storage: JSONHistoryStorage(fileURL: directory.appendingPathComponent("history.json")),
            blobs: BlobStore(directory: directory.appendingPathComponent("Images", isDirectory: true)),
            limit: AppSettings.defaultHistoryLimit
        )
        pins = PinnedImageController(settings: settings, pasteboard: pasteboard, savePrompt: savePrompt)
        translationProvider = options.translation.map { E2ETranslationProvider(script: $0.script) }
        stubRecognizer = options.translation?.recognizer == .stub ? E2EStubRecognizer() : nil
        let coordinator = makeCoordinator()
        if let translationProvider {
            coordinator.translation = translationProvider
            coordinator.translationRecognizer = stubRecognizer ?? VisionTranslationRecognizer()
        }
        self.coordinator = coordinator
    }

    /// 与 AppDelegate 相同的协调器，换上 fixture、命名剪贴板，并记录每个覆盖层
    private func makeCoordinator() -> ScreenshotCoordinator {
        let exportDelay = options.exportDelay
        return ScreenshotCoordinator(
            settings: settings,
            store: store,
            frameSource: fixture,
            windowSource: fixture,
            overlayFactory: { [weak self, recorder] capture, initial, delegate in
                // 结果先经记录器再交给协调器（覆盖层只弱引用委托，记录器由本环境持有）
                recorder.target = delegate
                let overlay = ScreenshotOverlayController(capture: capture, initial: initial, delegate: recorder)
                overlay.debugExportDelay = exportDelay
                self?.overlays.append(overlay)
                self?.lastCapture = capture
                return overlay
            },
            pins: pins,
            pasteboard: pasteboard,
            savePrompt: savePrompt,
            beforeCapture: {}
        )
    }

    // MARK: - 会话

    /// 开始一次会话：合成桌面、光标在 cursor（全局点），与真实截图相同的初始会话
    func start(cursor: CGPoint) {
        let styles = settings.annotationStyles
        coordinator?.begin(frameSource: fixture, windowSource: windowSource) { capture in
            ScreenshotSession.initial(styles: styles, cursor: cursor, topology: capture.topology)
        }
    }

    var isActive: Bool {
        coordinator?.isActive ?? false
    }

    /// 当前（或最近一次）覆盖层
    var overlay: ScreenshotOverlayController? {
        overlays.last
    }

    /// 覆盖层已上屏且仍在接收事件
    var isOverlayPresented: Bool {
        guard let overlay, !overlay.debugIsFinished else { return false }
        return overlay.debugWindows.contains { $0.isVisible }
    }

    private var windowSource: any WindowImageSource {
        switch options.windowSource {
        case .fixture: fixture
        case .failing: E2EFailingWindowSource()
        }
    }

    // MARK: - 输出

    var pasteboardPNG: Data? {
        pasteboard.data(forType: .png)
    }

    var pasteboardText: String? {
        pasteboard.string(forType: .string)
    }

    var history: [ClipItem] {
        store.history.items
    }

    /// 保存目录中的文件（按名称排序）
    var savedFiles: [URL] {
        files(in: saveDirectory)
    }

    /// 存储对话框（桩）所选文件夹中的文件
    var pickedFiles: [URL] {
        files(in: pickedDirectory)
    }

    private func files(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().map { folder.appendingPathComponent($0) }
    }

    /// 屏幕上可见的贴图窗口
    var pinWindows: [PinnedImageWindow] {
        NSApp.windows.compactMap { $0 as? PinnedImageWindow }.filter(\.isVisible)
    }

    // MARK: - 清理

    /// 结束仍在进行的会话、关闭贴图、释放命名剪贴板
    func tearDown() {
        savePrompt.resolve(nil)
        overlay?.cancel()
        pins.closeAll()
        pasteboard.releaseGlobally()
        coordinator = nil
    }
}

enum E2EWorldError: Error, CustomStringConvertible {
    case noScreen
    case noDefaults

    var description: String {
        switch self {
        case .noScreen: "no screen available"
        case .noDefaults: "could not create the isolated defaults suite"
        }
    }
}

/// 记录覆盖层的结果并原样转发给协调器
@MainActor
final class E2EResultRecorder: ScreenshotOverlayDelegate {
    weak var target: (any ScreenshotOverlayDelegate)?
    private(set) var results: [String] = []

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didFinishWith result: ScreenshotResult) {
        results.append(Self.describe(result))
        target?.overlay(overlay, didFinishWith: result)
    }

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didChangeStyles styles: ToolStyles) {
        target?.overlay(overlay, didChangeStyles: styles)
    }

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestSave export: ScreenshotExport) {
        results.append("requestSave")
        target?.overlay(overlay, didRequestSave: export)
    }

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestResolving failure: TranslationFailure) {
        results.append("requestResolve(\(failure))")
        target?.overlay(overlay, didRequestResolving: failure)
    }

    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestCopyingText text: String, selection: CGRect) {
        results.append("copyText")
        target?.overlay(overlay, didRequestCopyingText: text, selection: selection)
    }

    static func describe(_ result: ScreenshotResult) -> String {
        switch result {
        case .copy: "copy"
        case .pin: "pin"
        case .extractText: "extractText"
        case .copyColor(let text): "copyColor(\(text))"
        case .captureWindow(let id, let shadow): "captureWindow(\(id), shadow: \(shadow))"
        case .translatedText: "translatedText"
        case .cancel: "cancel"
        case .failed(let failure): "failed(\(failure))"
        }
    }
}

/// 模拟真实的纯净窗口采集找不到窗口（假窗口 id 在系统中不存在）
struct E2EFailingWindowSource: WindowImageSource {
    func captureWindow(id: UInt32, includeShadow: Bool, timeout: Duration) async throws -> WindowImage {
        throw FrameCaptureError.windowNotFound
    }
}
#endif
