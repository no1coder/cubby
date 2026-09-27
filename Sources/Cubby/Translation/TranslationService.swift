import CubbyCore
import Foundation
import Translation

/// 截图翻译的设置与引擎（实现 TranslationProviding，docs/TRANSLATION-DESIGN.md §4.3 T2）。
/// 引擎选择（D2）：选了大模型且已配置 → 大模型；选了大模型但未配置 → notConfigured
/// （钥匙串无法访问 → unauthorized，见 LLMConfigurationIssue.translationFailure）；否则系统翻译
@available(macOS 26, *)
@MainActor
final class TranslationService: TranslationProviding {
    private let settings: AppSettings
    private let keys: any TranslationKeyStoring
    private let session: URLSession
    /// 打开「设置 › 翻译」，在设置窗口关闭后返回
    private let openSettings: @MainActor () async -> Void
    private let missingLanguages = MissingLanguagePair()
    private let downloads = LanguageDownloadWindowController()

    init(
        settings: AppSettings,
        keys: any TranslationKeyStoring,
        session: URLSession = LLMHTTP.makeSession(),
        openSettings: @escaping @MainActor () async -> Void
    ) {
        self.settings = settings
        self.keys = keys
        self.session = session
        self.openSettings = openSettings
    }

    var targetLanguage: String? {
        get { settings.translationTargetLanguage }
        set { settings.translationTargetLanguage = newValue.flatMap(TranslationLanguageCatalog.normalize) }
    }

    var selectableLanguages: [String] {
        TranslationLanguageCatalog.selectable(preferred: Locale.preferredLanguages)
    }

    func makeEngine() -> Result<any TranslationEngine, TranslationFailure> {
        makeEngine(prompt: .screenshot).map(\.engine)
    }

    /// 选择规则见类型说明；prompt 为大模型提示词的场景（截图 / 剪贴板文本）
    private func makeEngine(prompt: LLMTranslationPrompt.Profile) -> Result<ClipEngine, TranslationFailure> {
        switch settings.translationEngine {
        case .system:
            return .success(ClipEngine(engine: makeSystemEngine(), input: .plainText, host: nil))
        case .llm:
            switch settings.llmConfiguration(key: storedKey()) {
            case .success(let configuration):
                let engine = LLMTranslationEngine(configuration: configuration, session: session, prompt: prompt)
                let host = engine.sendsTextOffDevice ? LLMBaseURL.displayHost(configuration.endpoint.baseURL) : nil
                return .success(ClipEngine(engine: engine, input: .markup, host: host))
            case .failure(let issue):
                return .failure(issue.translationFailure)
            }
        }
    }

    private func makeSystemEngine() -> any TranslationEngine {
        SystemTranslationEngine(missingLanguages: missingLanguages)
    }

    func canResolve(_ failure: TranslationFailure) -> Bool {
        switch failure {
        case .notConfigured, .unauthorized, .languageNotInstalled: true
        default: false
        }
    }

    func resolve(_ failure: TranslationFailure) async -> Bool {
        switch failure {
        case .notConfigured, .unauthorized:
            let before = snapshot()
            await openSettings()
            let after = snapshot()
            // 未配置：现在能用就重试（包括切回了系统翻译）；密钥无效：还得确实改过设置，避免原样重试
            return after.isUsable && (failure == .notConfigured || after != before)
        case .languageNotInstalled:
            return await downloads.download(missingLanguages.take())
        default:
            return false
        }
    }

    /// 当前服务预设保存的密钥（缓存的结果，不会反复访问钥匙串）
    private func storedKey() -> LLMStoredKeyLookup {
        keys.lookup(settings.translationProviderID)
    }

    /// 与翻译相关的设置快照（只在内存中短暂存在，用于判断用户是否改过设置）
    private struct Snapshot: Equatable {
        let engine: TranslationEngineKind
        let provider: String
        let baseURL: String
        let model: String
        let key: LLMStoredKeyLookup
        let isUsable: Bool
    }

    private func snapshot() -> Snapshot {
        let key = storedKey()
        let isUsable =
            switch settings.translationEngine {
            case .system: true
            case .llm: (try? settings.llmConfiguration(key: key).get()) != nil
            }
        return Snapshot(
            engine: settings.translationEngine, provider: settings.translationProviderID,
            baseURL: settings.effectiveTranslationBaseURL, model: settings.effectiveTranslationModel, key: key,
            isUsable: isUsable)
    }
}

// MARK: - 剪贴板条目翻译（docs/CLIP-TRANSLATION-DESIGN.md §7）

@available(macOS 26, *)
extension TranslationService: ClipTranslationProviding {
    func makeClipEngine(prompt: LLMTranslationPrompt.Profile) -> Result<ClipEngine, TranslationFailure> {
        makeEngine(prompt: prompt)
    }

    /// 独立的缺失语言记录：自动翻译遇到缺少语言包时不会顶掉用户翻译时记下的语言对
    func makeOnDeviceEngine() -> any TranslationEngine {
        SystemTranslationEngine(missingLanguages: MissingLanguagePair())
    }

    func isInstalled(_ languages: TranslationLanguages) async -> Bool {
        guard let source = languages.source else { return false }
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source), to: Locale.Language(identifier: languages.target))
        return status == .installed
    }
}
