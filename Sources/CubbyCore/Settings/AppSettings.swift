import Foundation
import Observation

/// 用户偏好设置，修改后立即写入 UserDefaults
@MainActor
@Observable
public final class AppSettings {
    public static let historyLimitOptions = [50, 100, 200, 500, 1000, 2000]
    public static let defaultHistoryLimit = 500
    /// 默认忽略的密码类应用（它们通常也会标记机密类型，这里双重保险）
    public static let defaultIgnoredBundleIDs = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
    ]
    /// 偏好设置的格式版本：键名或取值含义变化时递增，并在 migrateSettings 中补充对应迁移
    public static let currentSettingsVersion = 1

    private enum Keys {
        static let hotKey = "hotKey"
        static let historyLimit = "historyLimit"
        static let pasteDirectly = "pasteDirectly"
        static let isPaused = "isPaused"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let panelPosition = "panelPosition"
        static let pasteFormat = "pasteFormat"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let ignoresSecrets = "ignoresSecrets"
        static let settingsVersion = "settingsVersion"
        static let checksForUpdatesAutomatically = "checksForUpdatesAutomatically"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let latestKnownVersion = "latestKnownVersion"
        static let latestKnownReleaseURL = "latestKnownReleaseURL"
        static let dismissedUpdateVersion = "dismissedUpdateVersion"
        static let hasAnsweredUpdatePrompt = "hasAnsweredUpdatePrompt"
        static let screenshotHotKey = "screenshotHotKey"
        /// 用户主动关闭截图快捷键的标记：与「从未设置（用默认值）」区分
        static let screenshotHotKeyDisabled = "screenshotHotKeyDisabled"
        static let screenshotSaveDirectory = "screenshotSaveDirectory"
        static let screenshotAsksWhereToSave = "screenshotAsksWhereToSave"
        static let annotationStyles = "annotationStyles"
        static let indexesImageText = "indexesImageText"
        static let translationEngine = "translationEngine"
        static let translationTargetLanguage = "translationTargetLanguage"
        static let translationProvider = "translationProvider"
        static let translationBaseURL = "translationBaseURL"
        static let translationModel = "translationModel"
        static let translatesClipsOnCopy = "translatesClipsOnCopy"
        static let showsTranslationOnCards = "showsTranslationOnCards"
        static let clipTranslationTargets = "clipTranslationTargetsByApp"
    }

    public var hotKey: HotKey {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: Keys.hotKey) }
    }

    /// 通过快捷键呼出时面板出现的位置
    public var panelPosition: PanelPosition {
        didSet { defaults.set(panelPosition.rawValue, forKey: Keys.panelPosition) }
    }

    /// 回车粘贴文本时的默认格式；⇧↩ 使用另一种
    public var pasteFormat: PasteFormat {
        didSet { defaults.set(pasteFormat.rawValue, forKey: Keys.pasteFormat) }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// 不记录疑似密钥 / 令牌（API Key、私钥、JWT 等）
    public var ignoresSecrets: Bool {
        didSet { defaults.set(ignoresSecrets, forKey: Keys.ignoresSecrets) }
    }

    /// 在本机识别历史图片中的文字以便搜索（默认开启；关闭时由索引器清除已保存的识别文字）
    public var indexesImageText: Bool {
        didSet { defaults.set(indexesImageText, forKey: Keys.indexesImageText) }
    }

    /// 每天自动检查更新（默认关闭；新用户第一次显示欢迎页时打开，见 applyFirstRunUpdateDefault）。
    /// 用户对开关的任何改动都算回答过询问：在设置里关掉的人不会再被面板横幅问（docs/UPDATE-REMINDER-DESIGN.md U4）
    public var checksForUpdatesAutomatically: Bool {
        didSet {
            defaults.set(checksForUpdatesAutomatically, forKey: Keys.checksForUpdatesAutomatically)
            if !hasAnsweredUpdatePrompt { hasAnsweredUpdatePrompt = true }
        }
    }

    /// 最近一次成功检查更新的时间
    public var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Keys.lastUpdateCheck) }
    }

    /// 最近查到的新版本（U7）：重启后不联网也能显示蓝点与横幅；读写请用 AppSettings+Updates 中的方法
    public internal(set) var knownRelease: KnownRelease? {
        didSet {
            Self.store(knownRelease?.version.description, forKey: Keys.latestKnownVersion, in: defaults)
            Self.store(knownRelease?.releaseURL.absoluteString, forKey: Keys.latestKnownReleaseURL, in: defaults)
        }
    }

    /// 用户点了「稍后」的版本（U6）：只隐藏这个版本的横幅，重启后仍有效
    public internal(set) var dismissedUpdateVersion: SemanticVersion? {
        didSet { Self.store(dismissedUpdateVersion?.description, forKey: Keys.dismissedUpdateVersion, in: defaults) }
    }

    /// 是否回答过「有新版本时提醒你吗？」（欢迎页的勾选、询问横幅的两个按钮或设置里的开关，U3 / U4）
    public internal(set) var hasAnsweredUpdatePrompt: Bool {
        didSet { defaults.set(hasAnsweredUpdatePrompt, forKey: Keys.hasAnsweredUpdatePrompt) }
    }

    /// 截图全局快捷键；nil 表示用户已关闭（只能从菜单栏与面板按钮截图）。从未设置过时为 ⇧⌘2
    public var screenshotHotKey: HotKey? {
        didSet {
            if let screenshotHotKey {
                defaults.set(try? JSONEncoder().encode(screenshotHotKey), forKey: Keys.screenshotHotKey)
                defaults.removeObject(forKey: Keys.screenshotHotKeyDisabled)
            } else {
                defaults.removeObject(forKey: Keys.screenshotHotKey)
                defaults.set(true, forKey: Keys.screenshotHotKeyDisabled)
            }
        }
    }

    /// 截图保存目录；nil 表示跟随系统截图位置。只接受文件 URL，其他 URL 视为 nil
    public var screenshotSaveDirectory: URL? {
        didSet {
            // 在自身的 didSet 中赋值不会再次触发观察器
            if let url = screenshotSaveDirectory, !url.isFileURL {
                screenshotSaveDirectory = nil
            }
            if let path = screenshotSaveDirectory?.path {
                defaults.set(path, forKey: Keys.screenshotSaveDirectory)
            } else {
                defaults.removeObject(forKey: Keys.screenshotSaveDirectory)
            }
        }
    }

    /// 截图「存储」时先弹出存储对话框选择位置与文件名（默认开启）；关闭后直接存入 `screenshotSaveDirectory`。
    /// 对话框确认后会把所选文件夹写回 `screenshotSaveDirectory`，下次从这里开始
    public var asksWhereToSaveScreenshots: Bool {
        didSet { defaults.set(asksWhereToSaveScreenshots, forKey: Keys.screenshotAsksWhereToSave) }
    }

    /// 每个标注工具最近使用的样式（跨会话记忆）；读取容错，损坏时回退默认
    public var annotationStyles: ToolStyles {
        didSet { defaults.set(annotationStyles.encoded(), forKey: Keys.annotationStyles) }
    }

    /// 截图翻译的引擎（默认系统翻译；保存了可用的大模型配置后自动切到大模型，见 TranslationEngineKind）
    public var translationEngine: TranslationEngineKind {
        didSet { defaults.set(translationEngine.rawValue, forKey: Keys.translationEngine) }
    }

    /// 截图翻译的目标语言（BCP-47）；nil 表示自动（设计文档 §3.4）
    public var translationTargetLanguage: String? {
        didSet { Self.store(translationTargetLanguage, forKey: Keys.translationTargetLanguage, in: defaults) }
    }

    /// 大模型服务预设的 id（LLMProviderPreset）；切换预设请用 selectTranslationProvider(_:)
    public var translationProviderID: String {
        didSet { defaults.set(translationProviderID, forKey: Keys.translationProvider) }
    }

    /// 大模型接入地址；nil 表示使用预设的默认地址
    public var translationBaseURL: String? {
        didSet { Self.store(translationBaseURL, forKey: Keys.translationBaseURL, in: defaults) }
    }

    /// 大模型模型名；nil 表示使用预设的建议模型
    public var translationModel: String? {
        didSet { Self.store(translationModel, forKey: Keys.translationModel, in: defaults) }
    }

    /// 复制时自动翻译（默认关；只用本机系统翻译，且语言包已下载，docs/CLIP-TRANSLATION-DESIGN.md §6）
    public var translatesClipsOnCopy: Bool {
        didSet { defaults.set(translatesClipsOnCopy, forKey: Keys.translatesClipsOnCopy) }
    }

    /// 在面板卡片上显示译文首行（默认关；只因译文命中搜索时无论开关都显示）
    public var showsTranslationOnCards: Bool {
        didSet { defaults.set(showsTranslationOnCards, forKey: Keys.showsTranslationOnCards) }
    }

    /// 按粘贴目标应用记住的剪贴板翻译目标语言（§0.1 A8）；读写请用 AppSettings+ClipTranslation 中的方法
    public internal(set) var clipTranslationTargets: ClipPasteTargetLanguages {
        didSet { defaults.set(clipTranslationTargets.languages, forKey: Keys.clipTranslationTargets) }
    }

    /// 开启了自动检查、完成了欢迎页且已到期（每天一次；lastFailure 为本次运行中最近一次失败的时间，见 UpdateCheckSchedule）。
    /// 欢迎页显示期间开关已默认打开（U3），但用户还可能取消勾选：完成欢迎页之前一律不到期，不联网
    public func isAutomaticUpdateCheckDue(now: Date = Date(), lastFailure: Date? = nil) -> Bool {
        guard checksForUpdatesAutomatically, hasCompletedOnboarding else { return false }
        return UpdateCheckSchedule.isDue(lastCheck: lastUpdateCheck, lastFailure: lastFailure, now: now)
    }

    public static let updateCheckInterval = UpdateCheckSchedule.interval

    /// 非收藏条目的保留上限
    public var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    /// 选中条目后直接粘贴到当前应用（否则仅复制到剪贴板）
    public var pasteDirectly: Bool {
        didSet { defaults.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }

    public var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    public var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 先迁移再读取，保证下面读到的都是当前版本的键值
        Self.migrateSettings(in: defaults)
        hotKey =
            defaults.data(forKey: Keys.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .default
        panelPosition = defaults.string(forKey: Keys.panelPosition).flatMap(PanelPosition.init(rawValue:)) ?? .mouse
        pasteFormat = defaults.string(forKey: Keys.pasteFormat).flatMap(PasteFormat.init(rawValue:)) ?? .original
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        ignoresSecrets = defaults.object(forKey: Keys.ignoresSecrets) as? Bool ?? true
        indexesImageText = defaults.object(forKey: Keys.indexesImageText) as? Bool ?? true
        checksForUpdatesAutomatically = defaults.bool(forKey: Keys.checksForUpdatesAutomatically)
        lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        knownRelease = Self.storedKnownRelease(
            version: Keys.latestKnownVersion, releaseURL: Keys.latestKnownReleaseURL, in: defaults)
        dismissedUpdateVersion = defaults.string(forKey: Keys.dismissedUpdateVersion).flatMap(SemanticVersion.init)
        hasAnsweredUpdatePrompt = defaults.bool(forKey: Keys.hasAnsweredUpdatePrompt)
        let storedLimit = defaults.integer(forKey: Keys.historyLimit)
        historyLimit = storedLimit > 0 ? storedLimit : Self.defaultHistoryLimit
        pasteDirectly = defaults.object(forKey: Keys.pasteDirectly) as? Bool ?? true
        isPaused = defaults.bool(forKey: Keys.isPaused)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? Self.defaultIgnoredBundleIDs
        screenshotHotKey = Self.storedScreenshotHotKey(in: defaults)
        screenshotSaveDirectory = Self.storedScreenshotSaveDirectory(in: defaults)
        asksWhereToSaveScreenshots = defaults.object(forKey: Keys.screenshotAsksWhereToSave) as? Bool ?? true
        annotationStyles = ToolStyles.decode(defaults.data(forKey: Keys.annotationStyles))
        translationEngine =
            defaults.string(forKey: Keys.translationEngine).flatMap(TranslationEngineKind.init(rawValue:)) ?? .system
        translationTargetLanguage = Self.nonEmptyString(Keys.translationTargetLanguage, in: defaults)
        let storedProvider = defaults.string(forKey: Keys.translationProvider)
        let knownProvider = storedProvider.flatMap(LLMProviderPreset.preset(id:))
        translationProviderID = knownProvider?.id ?? LLMProviderPreset.standard.id
        // 存储的预设已失效（被更新版本写入或损坏）时，地址与模型属于那个预设，一并回到默认
        let providerIsValid = storedProvider == nil || knownProvider != nil
        translationBaseURL = providerIsValid ? Self.nonEmptyString(Keys.translationBaseURL, in: defaults) : nil
        translationModel = providerIsValid ? Self.nonEmptyString(Keys.translationModel, in: defaults) : nil
        translatesClipsOnCopy = defaults.bool(forKey: Keys.translatesClipsOnCopy)
        showsTranslationOnCards = defaults.bool(forKey: Keys.showsTranslationOnCards)
        clipTranslationTargets = ClipPasteTargetLanguages(
            defaults.dictionary(forKey: Keys.clipTranslationTargets)?.compactMapValues { $0 as? String } ?? [:])
    }

    /// 读取非空字符串；缺失、空串或类型不对时为 nil
    private static func nonEmptyString(_ key: String, in defaults: UserDefaults) -> String? {
        defaults.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// nil 或空串时移除键，否则写入
    private static func store(_ value: String?, forKey key: String, in defaults: UserDefaults) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 禁用标志优先；否则解码已存储的快捷键，缺失或损坏时回退默认值
    private static func storedScreenshotHotKey(in defaults: UserDefaults) -> HotKey? {
        guard !defaults.bool(forKey: Keys.screenshotHotKeyDisabled) else { return nil }
        return defaults.data(forKey: Keys.screenshotHotKey)
            .flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .screenshotDefault
    }

    /// 只接受绝对路径；空串、相对路径（含未展开的 ~）或类型不对时视为未设置
    private static func storedScreenshotSaveDirectory(in defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: Keys.screenshotSaveDirectory), path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 设置迁移入口：按已存储的版本逐级升级旧键值，最后写入当前版本号。
    /// 缺失（或类型不对）视为 v0：v0.1 未记录版本号，其键值与 v1 相同，无需转换。
    /// 版本号高于当前时保持原样（被更新版本的 Cubby 写过），避免降级运行时抹掉新版本的标记。
    private static func migrateSettings(in defaults: UserDefaults) {
        let stored = defaults.object(forKey: Keys.settingsVersion) as? Int ?? 0
        guard stored < currentSettingsVersion else { return }
        // v0 → v1：无需转换。日后新增版本时在此按 stored 追加各步转换
        defaults.set(currentSettingsVersion, forKey: Keys.settingsVersion)
    }

    /// 是否记录来自该应用的复制内容
    public func shouldCapture(from source: SourceApp?) -> Bool {
        guard !isPaused else { return false }
        guard let bundleID = source?.bundleID else { return true }
        return !ignoredBundleIDs.contains(bundleID)
    }

    /// 按内容判断是否记录：开启密钥过滤时跳过疑似密钥 / 令牌的文本
    public func shouldRecord(_ content: ClipContent) -> Bool {
        guard ignoresSecrets else { return true }
        switch content {
        case .text(let text), .richText(let text, _):
            return !SecretDetector.containsSecret(text)
        case .image:
            return shouldRecordImage
        case .files:
            return true
        }
    }

    /// 剪贴板监听取到的内容：尚未转码的图片与 .image 走同一条图片规则
    public func shouldRecord(_ capture: PasteboardCapture) -> Bool {
        switch capture {
        case .content(let content): shouldRecord(content)
        case .rawImage: shouldRecordImage
        }
    }

    /// 图片的记录规则（已转码与未转码共用）：图片不含可检测的文字，始终记录
    private var shouldRecordImage: Bool {
        true
    }

    public func addIgnoredApp(bundleID: String) {
        guard !ignoredBundleIDs.contains(bundleID) else { return }
        ignoredBundleIDs = ignoredBundleIDs + [bundleID]
    }

    public func removeIgnoredApp(bundleID: String) {
        ignoredBundleIDs = ignoredBundleIDs.filter { $0 != bundleID }
    }
}
