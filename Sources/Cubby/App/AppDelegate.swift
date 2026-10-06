import AppKit
import Observation
import os
import CubbyCore

/// 组装各模块：存储、剪贴板监听、全局热键、面板、菜单栏、设置与引导
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let hotKeys = HotKeyManager()
    private lazy var updates = UpdateCoordinator(settings: settings)
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "App")

    private var store: ClipStore?
    private var monitor: ClipboardMonitor?
    private var panel: PanelController?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    /// 使用说明窗口：第一次打开时才创建并载入文档
    private lazy var userGuide = UserGuideWindowController()
    private var screenshots: ScreenshotCoordinator?
    /// 历史图片的本机文字识别（按图中文字搜索）
    private var imageTextIndexer: ImageTextIndexer?
    /// 各动作最近一次注册成功的快捷键，新快捷键被占用时回退到它
    private var lastWorkingHotKeys: [HotKeyAction: HotKey] = [:]
    /// 截图翻译的 API Key 存储（设置页与翻译服务共用）
    private lazy var translationKeys: any TranslationKeyStoring = Self.makeTranslationKeyStore()
    /// 「设置 › 翻译」的状态；macOS 26 以前为 nil
    private var translationSettings: TranslationSettingsModel?
    /// 复制时自动翻译（剪贴板条目翻译，仅 macOS 26）
    private var clipAutoTranslator: ClipAutoTranslator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        #if DEBUG
        if Self.launchDebugTool() { return }
        DebugInputLock.installIfRequested()
        #endif
        AppPaths.prepare()
        #if DEBUG
        // 截图走查：强制浅色外观
        if CommandLine.arguments.contains("--light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        // 剪贴板翻译演示：在创建存储之前写入演示历史（只写 CUBBY_DATA_DIR，没设置时不写、也不运行演示）
        if let demo = Self.debugScenario.flatMap(PanelTranslationDemo.init(scenario:)),
            !TranslationDemoHistory.seed(demo)
        {
            logger.error("Could not write the translation demo history (it needs CUBBY_DATA_DIR)")
            NSApp.terminate(nil)
            return
        }
        #endif
        let panel = makeComponents()

        #if DEBUG
        // 设置页、翻译、使用说明与翻译演示用不到剪贴板：不启动监听，避免读取用户的剪贴板
        let skipsClipboard = [
            "settings:", "translation:", "guide", PanelTranslationDemo.prefix, "screenshot:translate-demo",
        ]
        .contains {
            Self.debugScenario?.hasPrefix($0) == true
        }
        if !skipsClipboard { monitor?.start() }
        #else
        monitor?.start()
        #endif
        lastWorkingHotKeys[.togglePanel] = settings.hotKey
        lastWorkingHotKeys[.screenshot] = settings.screenshotHotKey
        #if DEBUG
        // 截图走查时不注册全局热键，避免与已安装的正式版冲突
        if Self.debugScenario == nil { registerHotKeys() }
        #else
        registerHotKeys()
        #endif
        observeSettings()
        imageTextIndexer?.start()
        store?.backfillThumbnails()
        // 更新提醒：升级后清除记住的版本、到期就查，之后每小时与唤醒时再判断（docs/UPDATE-REMINDER-DESIGN.md U1）
        updates.start()
        logger.info(
            """
            Launched. Clipboard access: \(PasteboardAccess.status.rawValue, privacy: .public), \
            accessibility: \(PasteService.isTrusted)
            """
        )

        if !settings.hasCompletedOnboarding, !CommandLine.arguments.contains("--scenario") {
            showOnboarding()
        } else {
            handleLaunchArguments(panel: panel)
        }
    }

    /// 创建并连接各模块，返回面板控制器
    private func makeComponents() -> PanelController {
        let store = ClipStore(
            storage: JSONHistoryStorage(fileURL: AppPaths.historyFile),
            blobs: BlobStore(directory: AppPaths.imagesDirectory),
            limit: settings.historyLimit
        )
        let panel = PanelController(store: store, settings: settings)
        let screenshots = makeScreenshotCoordinator(store: store, panel: panel)
        let translationSettings = makeTranslationSettings()
        let settingsWindow = SettingsWindowController(
            settings: settings,
            store: store,
            updates: updates,
            translation: translationSettings,
            onShortcutRecordingChange: { [weak self] in self?.setShortcutRecording($0) },
            openUserGuide: { [weak self] in self?.showUserGuide() }
        )
        configureTranslation(screenshots: screenshots, panel: panel, store: store, settingsWindow: settingsWindow)
        let statusBar = makeStatusBar(panel: panel, settingsWindow: settingsWindow, screenshots: screenshots)
        connectPanel(panel, settingsWindow: settingsWindow, statusBar: statusBar)

        self.store = store
        self.panel = panel
        self.settingsWindow = settingsWindow
        self.translationSettings = translationSettings
        self.statusBar = statusBar
        self.screenshots = screenshots
        self.imageTextIndexer = ImageTextIndexer(
            store: store,
            settings: settings,
            recognizer: VisionImageTextRecognizer()
        )
        self.monitor = ClipboardMonitor { [weak self] capture, source in
            self?.capture(capture, from: source)
        }
        return panel
    }

    /// 面板通往其他窗口的入口：设置、隐私设置、使用说明、检查更新；以及菜单栏图标的位置
    private func connectPanel(
        _ panel: PanelController, settingsWindow: SettingsWindowController, statusBar: StatusBarController
    ) {
        panel.openSettings = { settingsWindow.show() }
        panel.openUserGuide = { [weak self] in self?.showUserGuide() }
        PanelWarning.checkForUpdates = { [weak self] in self?.updates.checkInteractively() }
        PanelWarning.openPrivacySettings = { [weak panel] in
            panel?.hide(animated: false)
            settingsWindow.show(pane: .privacy)
        }
        panel.statusItemFrame = { [weak statusBar] in statusBar?.buttonFrame }
        panel.updates = updates
    }

    /// 截图协调器：面板顶栏按钮与快捷键共用；采集前先无动画隐藏面板（面板不能出现在冻结帧里）。
    private func makeScreenshotCoordinator(store: ClipStore, panel: PanelController) -> ScreenshotCoordinator {
        let coordinator = ScreenshotCoordinator(
            settings: settings,
            store: store,
            overlayFactory: ScreenshotCoordinator.overlayFactory(ScreenshotOverlayController.self),
            pins: PinnedImageController(settings: settings),
            beforeCapture: { [weak panel] in panel?.hide(animated: false) }
        )
        panel.takeScreenshot = { [weak coordinator] in coordinator?.start(.panelButton) }
        // 历史图片「贴到屏幕」与截图贴图共用同一组贴图窗口
        panel.pinImage = { [weak coordinator] pin in
            coordinator?.pins.pin(image: pin.image, pixelSize: pin.pixelSize, scale: pin.scale, at: pin.center)
        }
        return coordinator
    }

    // MARK: - 截图翻译（仅 macOS 26，docs/TRANSLATION-DESIGN.md D5）

    private func makeTranslationSettings() -> TranslationSettingsModel? {
        guard #available(macOS 26, *) else { return nil }
        return TranslationSettingsModel(settings: settings, keys: translationKeys)
    }

    /// 给截图协调器与面板（剪贴板条目翻译）接上同一个翻译服务：「去设置」打开设置 › 翻译，等设置窗口关闭后返回
    private func configureTranslation(
        screenshots: ScreenshotCoordinator, panel: PanelController, store: ClipStore,
        settingsWindow: SettingsWindowController
    ) {
        guard #available(macOS 26, *) else { return }
        let service = TranslationService(settings: settings, keys: translationKeys) { [weak settingsWindow] in
            await settingsWindow?.showUntilClosed(pane: .translation)
        }
        let recognizer = VisionTranslationRecognizer()
        screenshots.translation = service
        screenshots.translationRecognizer = recognizer
        panel.clipTranslation = ClipTranslationService(
            store: store, settings: settings, provider: service, recognizer: recognizer)
        clipAutoTranslator = ClipAutoTranslator(store: store, settings: settings, provider: service)
    }

    /// 正式运行时用登录钥匙串；调试走查（--scenario）只用内存，不接触钥匙串
    private static func makeTranslationKeyStore() -> any TranslationKeyStoring {
        #if DEBUG
        if debugScenario != nil {
            return InMemoryTranslationKeyStore(keys: DebugTranslationFixtures.fakeKeys)
        }
        #endif
        return KeychainTranslationKeyStore()
    }

    private func makeStatusBar(
        panel: PanelController,
        settingsWindow: SettingsWindowController,
        screenshots: ScreenshotCoordinator
    ) -> StatusBarController {
        StatusBarController(
            settings: settings,
            updates: updates,
            actions: .init(
                togglePanel: { anchor in panel.toggle(anchor.map { .statusItem($0) } ?? .hotKey) },
                takeScreenshot: { [weak screenshots] in screenshots?.start(.menu) },
                openSettings: { settingsWindow.show() },
                showOnboarding: { [weak self] in self?.showOnboarding() },
                showUserGuide: { [weak self] in self?.showUserGuide() },
                clearHistory: { [weak self] in self?.confirmClearHistory() },
                checkForUpdates: { [weak self] in self?.updates.checkInteractively() }
            )
        )
    }

    /// 调试 / 自动化：open Cubby.app --args --show-panel
    private func handleLaunchArguments(panel: PanelController) {
        #if DEBUG
        if let scenario = Self.debugScenario {
            applyDebugScenario(scenario, panel: panel)
            return
        }
        #endif
        // 在设置里切换界面语言后重新打开：回到设置，让用户直接看到新语言
        if CommandLine.arguments.contains(AppRelauncher.showSettingsArgument) {
            settingsWindow?.show(pane: .general)
            return
        }
        guard CommandLine.arguments.contains("--show-panel") else { return }
        panel.show()
    }

    #if DEBUG
    /// 调试工具（只运行工具，不启动剪贴板监听、热键与面板，不接触真实剪贴板与数据目录）：
    /// --e2e 截图端到端测试；--translate-qa <corpus.json> <outdir> 截图翻译视觉验收（只处理合成图片，写完报告即退出）；
    /// --clip-translation-selftest 剪贴板翻译服务自检（临时目录、桩引擎）
    private static func launchDebugTool() -> Bool {
        if let e2e = ScreenshotE2E.requested {
            ScreenshotE2E.launch(e2e)
            return true
        }
        // 面板端到端测试（--panel-e2e）：同样只运行脚本，每条脚本用自己的面板、演示条目、命名剪贴板与桩翻译服务
        if let panelE2E = PanelE2E.requested {
            PanelE2E.launch(panelE2E)
            return true
        }
        if let qa = TranslationQA.requested {
            TranslationQA.launch(qa)
            return true
        }
        if ClipTranslationSelfTest.isRequested {
            ClipTranslationSelfTest.launch()
            return true
        }
        return false
    }

    /// 调试构建：--scenario <名称> 复现界面状态（面板类见 PanelController.applyDebugScenario）
    private static var debugScenario: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--scenario"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func applyDebugScenario(_ scenario: String, panel: PanelController) {
        if scenario.hasPrefix("settings:"),
            let pane = SettingsPane.allCases.first(where: { "settings:\($0)" == scenario })
        {
            settingsWindow?.show(pane: pane)
            if pane == .translation { translationSettings.map(DebugTranslationFixtures.runProbesIfRequested) }
        } else if scenario == "translation:download" {
            if #available(macOS 26, *), let translation = screenshots?.translation {
                DebugTranslationFixtures.runDownloadScenario(translation)
            }
        } else if scenario == "onboarding" {
            showOnboarding()
        } else if scenario == "guide" || scenario.hasPrefix("guide:") {
            // guide:<搜索词> 预先填入搜索框
            userGuide.show(query: scenario.hasPrefix("guide:") ? String(scenario.dropFirst("guide:".count)) : nil)
        } else if scenario == "hud" {
            showHotKeyTip()
        } else if scenario.hasPrefix("screenshot:") {
            // screenshot:<名称>，见 ScreenshotCoordinator.startDebugScenario
            screenshots?.start(.debugScenario(scenario))
        } else if let demo = PanelTranslationDemo(scenario: scenario) {
            startTranslationDemo(demo, panel: panel)
        } else {
            panel.applyDebugScenario(scenario)
        }
    }

    /// 剪贴板翻译演示：面板换上接演示引擎的真实翻译服务（Vision 识别、排版与绘制照常），再打开翻译卡
    private func startTranslationDemo(_ demo: PanelTranslationDemo, panel: PanelController) {
        guard #available(macOS 26, *), let store else {
            logger.error("The translation demo needs macOS 26")
            return
        }
        panel.clipTranslation = ClipTranslationService(
            store: store, settings: settings, provider: DemoTranslationProvider(),
            recognizer: VisionTranslationRecognizer())
        panel.startTranslationDemo(demo)
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        imageTextIndexer?.stop()
        store?.discardUndo()
        store?.flush()
    }

    // MARK: - 剪贴板

    /// 摘要计算、TIFF 转码与图片落盘在后台完成（大图不卡主线程），按复制顺序入历史
    private func capture(_ capture: PasteboardCapture, from source: SourceApp?) {
        guard settings.shouldCapture(from: source), settings.shouldRecord(capture) else { return }
        switch capture {
        case .content(let content):
            // 入历史后交给复制时自动翻译（只处理文本，图片不自动翻译）
            if let recording = store?.recordInBackground(content, source: source) {
                clipAutoTranslator?.track(recording)
            }
        case .rawImage(let image): store?.recordInBackground(image, source: source)
        }
    }

    // MARK: - 快捷键

    private func registerHotKeys() {
        registerPanelHotKey()
        registerScreenshotHotKey()
    }

    private func registerPanelHotKey() {
        register(settings.hotKey, for: .togglePanel) { [weak self] in
            self?.panel?.toggle()
        }
    }

    /// 用户清空截图快捷键时注销（只剩菜单栏与面板按钮两个入口）
    private func registerScreenshotHotKey() {
        guard let hotKey = settings.screenshotHotKey else {
            hotKeys.unregister(.screenshot)
            return
        }
        register(hotKey, for: .screenshot) { [weak self] in
            self?.screenshots?.start(.hotKey)
        }
    }

    /// 暂停期间（正在录制另一个快捷键）只登记，真正的结果在恢复时由 hotKeysResumed 处理
    private func register(_ hotKey: HotKey, for action: HotKeyAction, handler: @escaping () -> Void) {
        switch hotKeys.register(hotKey, for: action, handler: handler) {
        case .registered: lastWorkingHotKeys[action] = hotKey
        case .deferred: break
        case .failed: hotKeyRegistrationFailed(hotKey, for: action)
        }
    }

    private func hotKeyRegistrationFailed(_ hotKey: HotKey, for action: HotKeyAction) {
        logger.error(
            """
            Failed to register hot key \(hotKey.displayName, privacy: .public) \
            for action \(action.rawValue), maybe used by another app
            """
        )
        notifyHotKeyConflict(hotKey, for: action)
    }

    /// 新快捷键被占用时告知用户，并回退到该动作上一个可用的快捷键（回退会再次触发注册）
    private func notifyHotKeyConflict(_ hotKey: HotKey, for action: HotKeyAction) {
        let fallback = lastWorkingHotKeys[action].flatMap { $0 == hotKey ? nil : $0 }
        let message =
            fallback.map {
                String(
                    localized: "\(hotKey.displayName) is already in use. Switched back to \($0.displayName).",
                    comment: "HUD when a new global shortcut is taken. %1$@ = new shortcut, %2$@ = previous shortcut"
                )
            }
            ?? String(
                localized: "\(hotKey.displayName) is used by another app. Choose a different shortcut in Settings.",
                comment: "HUD when the global shortcut is taken"
            )
        if let anchor = HUDToast.defaultAnchor() {
            HUDToast.show(message, symbolName: "exclamationmark.triangle.fill", tint: .orange, at: anchor)
        }
        guard let fallback else { return }
        switch action {
        case .togglePanel: settings.hotKey = fallback
        case .screenshot: settings.screenshotHotKey = fallback
        }
    }

    /// 录制新快捷键期间暂停全局热键；恢复时报告暂停期间登记的快捷键是否注册成功
    private func setShortcutRecording(_ isRecording: Bool) {
        if isRecording {
            hotKeys.suspend()
        } else {
            hotKeysResumed(failed: hotKeys.resume())
        }
    }

    /// 注册成功的记为「上一个可用」；失败的提示并回滚（与直接注册失败同一路径）
    private func hotKeysResumed(failed: [HotKeyAction]) {
        for action in HotKeyAction.allCases {
            if let working = hotKeys.registeredHotKey(for: action) {
                lastWorkingHotKeys[action] = working
            }
        }
        for action in failed {
            guard let hotKey = currentHotKey(for: action) else { continue }
            hotKeyRegistrationFailed(hotKey, for: action)
        }
    }

    private func currentHotKey(for action: HotKeyAction) -> HotKey? {
        switch action {
        case .togglePanel: settings.hotKey
        case .screenshot: settings.screenshotHotKey
        }
    }

    // MARK: - 设置监听（各项独立订阅，互不触发）

    private func observeSettings() {
        observe({ [settings] in settings.hotKey }) { [weak self] in self?.registerPanelHotKey() }
        observe({ [settings] in settings.screenshotHotKey }) { [weak self] in self?.registerScreenshotHotKey() }
        observe({ [settings] in settings.historyLimit }) { [weak self] in
            guard let self else { return }
            self.store?.setLimit(self.settings.historyLimit)
        }
        observe({ [settings] in settings.isPaused }) { [weak self] in self?.statusBar?.refreshAppearance() }
        // 查到新版本、点了「稍后」或升级后：菜单栏蓝点与菜单项随之更新
        observe({ [updates] in updates.reminder }) { [weak self] in self?.statusBar?.refreshAppearance() }
    }

    private func observe<Value>(
        _ value: @escaping @MainActor @Sendable () -> Value,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        withObservationTracking {
            _ = value()
        } onChange: {
            Task { @MainActor [weak self] in
                // 先重新订阅再执行：回调里再次修改同一设置（如热键冲突时回退）也能被观察到
                self?.observe(value, onChange: onChange)
                onChange()
            }
        }
    }

    // MARK: - 窗口

    private func showOnboarding() {
        let controller =
            onboardingWindow
            ?? OnboardingWindowController(
                settings: settings,
                onShortcutRecordingChange: { [weak self] in self?.setShortcutRecording($0) },
                onFinish: { [weak self] in
                    self?.onboardingWindow = nil
                    self?.showHotKeyTip()
                }
            )
        onboardingWindow = controller
        controller.show()
    }

    /// 使用说明（菜单栏、设置 › 关于、面板帮助浮层共用）
    private func showUserGuide() {
        userGuide.show()
    }

    /// 引导结束后提示呼出方式（不直接弹出面板，避免打断用户）
    private func showHotKeyTip() {
        guard let anchor = HUDToast.defaultAnchor() else { return }
        HUDToast.show(
            String(
                localized: "Press \(settings.hotKey.displayName) to open your clipboard anytime",
                comment: "HUD after the first-launch guide. %@ = global shortcut"
            ),
            symbolName: "keyboard",
            tint: .accentColor,
            duration: HUDToast.tipDuration,
            at: anchor
        )
    }

    private func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = ClearHistoryCopy.title
        alert.informativeText = ClearHistoryCopy.message
        alert.addButton(withTitle: ClearHistoryCopy.confirm)
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store?.clearHistory()
        }
    }
}

/// 清空历史的确认文案（菜单栏与设置页共用）
enum ClearHistoryCopy {
    static var title: String {
        String(localized: "Clear clipboard history?", comment: "Clear history confirmation title")
    }

    static var message: String {
        String(
            localized: "Favorites will be kept. This can't be undone.",
            comment: "Clear history confirmation message"
        )
    }

    static var confirm: String {
        String(localized: "Clear", comment: "Clear history confirmation button")
    }
}
