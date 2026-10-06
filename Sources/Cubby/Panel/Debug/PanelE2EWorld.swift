#if DEBUG
import AppKit
import CubbyCore

/// 一条面板脚本的隔离环境（仿截图 E2EWorld）：独立的偏好设置域、临时历史目录（演示条目）、命名剪贴板、
/// 桩翻译服务与自己的面板控制器。不读系统剪贴板、不联网、不碰真实数据目录；关闭「直接粘贴」，只断言剪贴板内容
@MainActor
final class PanelE2EWorld {
    struct Options {
        /// false：不接线翻译服务（功能不可用）
        var translationAvailable = true
        var engine = PanelE2EStubTranslator.Engine.system
        var planFailure: TranslationFailure?
        var streamFailure: TranslationFailure?
        var startDelay: Duration = .milliseconds(80)
        var segmentDelay: Duration = .milliseconds(80)
        var inlineCap: Duration = .seconds(30)
        var isPaused = false
        /// 更新提醒（docs/UPDATE-REMINDER-DESIGN.md）：正在运行的版本与是否按 Homebrew 安装处理
        var currentVersion = "0.2.1"
        var isHomebrewInstall = false
    }

    /// 固定的粘贴目标（只显示，不参与真实粘贴）
    static let pasteTarget = PasteTarget(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", processID: 0)

    let directory: URL
    let pasteboard: NSPasteboard
    /// 本环境的偏好设置域：relaunch 用它重新读出设置（模拟重启）
    let defaults: UserDefaults
    let options: Options
    let store: ClipStore
    let translator: PanelE2EStubTranslator?
    /// 更新检查的桩：返回脚本给定的结果，记录检查次数与打开的网址（不联网、不开浏览器）
    let updateStub = PanelE2EUpdateStub()
    private(set) var settings: AppSettings
    private(set) var panel: PanelController
    private(set) var updates: UpdateCoordinator

    init(name: String, root: URL, options: Options) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 以绝对路径作为 suite 名：偏好设置写到本环境目录下，不进 ~/Library/Preferences
        guard let defaults = UserDefaults(suiteName: directory.appendingPathComponent("defaults").path) else {
            throw E2EWorldError.noDefaults
        }
        self.directory = directory
        self.defaults = defaults
        self.options = options
        let settings = AppSettings(defaults: defaults)
        settings.pasteDirectly = false
        settings.isPaused = options.isPaused
        self.settings = settings
        let blobs = BlobStore(directory: directory.appendingPathComponent("Images", isDirectory: true))
        let storage = JSONHistoryStorage(fileURL: directory.appendingPathComponent("history.json"))
        try storage.save(PanelE2EFixtures.history(blobs: blobs, now: Date()))
        store = ClipStore(storage: storage, blobs: blobs, limit: AppSettings.defaultHistoryLimit)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.no1coder.Cubby.panel-e2e.\(name)"))
        pasteboard.clearContents()
        translator = options.translationAvailable ? Self.makeTranslator(options, directory: directory) : nil
        updates = Self.makeUpdates(
            settings: settings, stub: updateStub, options: options, version: options.currentVersion,
            pasteboard: pasteboard)
        panel = Self.makePanel(
            store: store, settings: settings, pasteboard: pasteboard, options: options, translator: translator,
            updates: updates)
    }

    private static func makePanel(
        store: ClipStore, settings: AppSettings, pasteboard: NSPasteboard, options: Options,
        translator: PanelE2EStubTranslator?, updates: UpdateCoordinator
    ) -> PanelController {
        let panel = PanelController(store: store, settings: settings, pasteboard: pasteboard)
        panel.debugKeepsOpen = true
        panel.debugPasteTarget = Self.pasteTarget
        panel.translationTimings = TranslationTimings(inlineCap: options.inlineCap)
        panel.clipTranslation = translator
        panel.updates = updates
        return panel
    }

    /// 接桩的更新协调器：不定时、不监听唤醒；脚本自己调用 start()（先写好设置再启动）
    private static func makeUpdates(
        settings: AppSettings, stub: PanelE2EUpdateStub, options: Options, version: String,
        pasteboard: NSPasteboard
    ) -> UpdateCoordinator {
        let environment = UpdateCoordinator.Environment(
            check: { await stub.check() },
            currentVersion: version,
            isHomebrewInstall: options.isHomebrewInstall,
            openURL: { stub.open($0) },
            pasteboard: pasteboard,
            schedulesChecks: false
        )
        return UpdateCoordinator(settings: settings, environment: environment)
    }

    /// 模拟重启：从同一个偏好设置域重新读出设置，换新的更新协调器与面板并启动（currentVersion 模拟升级后的版本）
    func relaunch(currentVersion: String? = nil) {
        let version = currentVersion ?? updates.currentVersion
        panel.hide(animated: false)
        panel.clipTranslation = nil
        settings = AppSettings(defaults: defaults)
        updates = Self.makeUpdates(
            settings: settings, stub: updateStub, options: options, version: version, pasteboard: pasteboard)
        panel = Self.makePanel(
            store: store, settings: settings, pasteboard: pasteboard, options: options, translator: translator,
            updates: updates)
        updates.start()
    }

    private static func makeTranslator(_ options: Options, directory: URL) -> PanelE2EStubTranslator {
        let translator = PanelE2EStubTranslator(outputDirectory: directory)
        translator.engine = options.engine
        translator.planFailure = options.planFailure
        translator.streamFailure = options.streamFailure
        translator.startDelay = options.startDelay
        translator.segmentDelay = options.segmentDelay
        translator.isRecordingPaused = options.isPaused
        return translator
    }

    var viewModel: PanelViewModel {
        panel.debugViewModel
    }

    func item(_ key: String) -> ClipItem? {
        store.item(id: PanelE2EFixtures.id(key))
    }

    /// 剪贴板上的纯文本（只接受带 Cubby 标记的写入）
    var pasteboardText: String? {
        pasteboard.string(forType: .string)
    }

    var pasteboardTypes: Set<NSPasteboard.PasteboardType> {
        Set(pasteboard.types ?? [])
    }

    func tearDown() {
        panel.hide(animated: false)
        panel.clipTranslation = nil
        pasteboard.releaseGlobally()
    }
}
#endif
