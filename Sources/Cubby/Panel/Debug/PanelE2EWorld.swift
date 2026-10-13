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
        /// 加密 Vault（docs/HISTORY-ENCRYPTION-DESIGN.md）：nil 时直接用已解锁的加密存储；
        /// 否则 ClipStore 以内存模式创建，由真实的 VaultCoordinator 在脚本调用 startVault() 后准备
        var vault: VaultSetup?
    }

    /// Vault 脚本的起始条件
    struct VaultSetup {
        /// 数据目录里预先写入的明文历史（旧版本留下的 history.json）条数
        var plaintextItems = 0
        /// 读取密钥时先停在闸门上（模拟钥匙串询问），直到脚本开闸
        var waitsAtGate = false
        /// 读取密钥被拒绝（模拟用户在询问中点了「拒绝」）
        var startsLocked = false
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
    /// Vault 脚本才有：真实的协调器、可控的密钥来源与它管理的数据目录
    let vault: VaultCoordinator?
    let keyGate: PanelE2EKeyGate?
    let dataDirectory: URL

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
        dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        if let setup = options.vault {
            let world = try Self.makeVaultWorld(setup, dataDirectory: dataDirectory)
            store = world.store
            vault = world.vault
            keyGate = world.gate
        } else {
            // 随机临时密钥的加密存储：演示条目与图片都以密文写入，不碰钥匙串（E3b）
            let stores = DebugHistoryKey.vaultStores(in: directory)
            try stores.storage.save(PanelE2EFixtures.history(blobs: stores.blobs, now: Date()))
            store = ClipStore(storage: stores.storage, blobs: stores.blobs, limit: AppSettings.defaultHistoryLimit)
            vault = nil
            keyGate = nil
        }
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.no1coder.Cubby.panel-e2e.\(name)"))
        pasteboard.clearContents()
        translator = options.translationAvailable ? Self.makeTranslator(options) : nil
        updates = Self.makeUpdates(
            settings: settings, stub: updateStub, options: options, version: options.currentVersion,
            pasteboard: pasteboard)
        panel = Self.makePanel(
            store: store, settings: settings, pasteboard: pasteboard, options: options, translator: translator,
            updates: updates)
        panel.vault = vault
    }

    /// 内存模式的 ClipStore + 真实的 VaultCoordinator（密钥来自闸门，数据目录里可预置旧版本的明文历史）
    private static func makeVaultWorld(
        _ setup: VaultSetup, dataDirectory: URL
    ) throws -> (store: ClipStore, vault: VaultCoordinator, gate: PanelE2EKeyGate) {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        if setup.plaintextItems > 0 {
            let plain = PlaintextFiles(dataDirectory: dataDirectory)
            try JSONHistoryStorage(fileURL: plain.historyURL).save(
                PanelE2EFixtures.plaintextHistory(count: setup.plaintextItems, now: Date()))
        }
        let gate = PanelE2EKeyGate(startsOpen: !setup.waitsAtGate)
        gate.setLocked(setup.startsLocked)
        let store = ClipStore(inMemoryWithLimit: AppSettings.defaultHistoryLimit)
        let vault = VaultCoordinator(
            store: store, keySource: HistoryKeySource.Choice(provider: gate, isEphemeral: false),
            dataDirectory: dataDirectory)
        return (store, vault, gate)
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
        panel.vault = vault
        updates.start()
    }

    private static func makeTranslator(_ options: Options) -> PanelE2EStubTranslator {
        let translator = PanelE2EStubTranslator()
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
        // 闸门还关着时开闸，后台的密钥读取不再等待
        keyGate?.open()
        panel.hide(animated: false)
        panel.clipTranslation = nil
        pasteboard.releaseGlobally()
    }
}
#endif
