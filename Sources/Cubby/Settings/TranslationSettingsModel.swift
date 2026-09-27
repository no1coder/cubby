import CubbyCore
import Foundation

/// 「设置 › 翻译」的状态与操作。
/// 地址与模型在提交（回车、离开输入框、关闭窗口）时才写入设置；密钥只进钥匙串（与当前地址绑定），界面只显示掩码。
/// 用户的保存动作按 TranslationEngineKind.afterSavingLLMSettings 自动切到大模型（D2）；
/// 关闭窗口、切换引擎前的隐式提交从不切换引擎
@MainActor
@Observable
final class TranslationSettingsModel {
    /// 刷新模型列表、测试连接的状态
    enum ProbeState: Equatable {
        case idle
        case running
        case succeeded(String)
        case failed(String)
    }

    let settings: AppSettings
    @ObservationIgnored private let keys: any TranslationKeyStoring
    @ObservationIgnored private let session: URLSession

    var baseURLText = ""
    var modelText = ""
    var keyDraft = ""
    /// 当前预设在钥匙串中的读取结果（缓存；读取失败时只有点「重试」才会再次访问钥匙串）
    private(set) var keyLookup = LLMStoredKeyLookup.none
    private(set) var keyError: String?
    private(set) var models: [String] = []
    private(set) var modelsState = ProbeState.idle
    private(set) var testState = ProbeState.idle
    @ObservationIgnored private var modelsTask: Task<Void, Never>?
    @ObservationIgnored private var testTask: Task<Void, Never>?

    init(settings: AppSettings, keys: any TranslationKeyStoring, session: URLSession = LLMHTTP.makeSession()) {
        self.settings = settings
        self.keys = keys
        self.session = session
        // 钥匙串在页面出现时才读取（reload），启动时不访问
        baseURLText = settings.effectiveTranslationBaseURL
        modelText = settings.effectiveTranslationModel
    }

    var preset: LLMProviderPreset {
        settings.translationPreset
    }

    /// Ollama 在本机时不需要密钥，隐藏密钥一行
    var showsKeyField: Bool {
        !(preset.isLocalService && baseURLIsLoopback)
    }

    /// 地址输入框当前内容的问题（nil = 有效）
    var baseURLIssue: LLMBaseURLError? {
        guard case .failure(let error) = LLMBaseURL.validate(baseURLText) else { return nil }
        return error
    }

    /// 已保存的地址（无效时为 nil）
    var savedBaseURL: URL? {
        try? LLMBaseURL.validate(settings.effectiveTranslationBaseURL).get()
    }

    /// 已保存的密钥相对于已保存地址的状态
    var keyState: LLMKeyState {
        LLMKeyState(keyLookup, baseURL: savedBaseURL)
    }

    /// 已保存的配置是否完整可用
    var isConfigured: Bool {
        (try? settings.llmConfiguration(key: keyLookup).get()) != nil
    }

    /// 隐私说明里的主机名（地址无效时为 nil）
    var host: String? {
        savedBaseURL.map(LLMBaseURL.displayHost)
    }

    var baseURLIsLoopback: Bool {
        (try? LLMBaseURL.validate(baseURLText).get()).map(LLMBaseURL.isLoopback) ?? false
    }

    /// 已保存密钥的掩码：只露出末尾 4 位（短密钥全部遮住）；密钥不可用时为 nil
    var savedKeyMask: String? {
        guard case .available(let key) = keyState else { return nil }
        let dots = String(repeating: "•", count: 8)
        return key.count >= 12 ? dots + key.suffix(4) : dots
    }

    /// 从设置与缓存的钥匙串结果重新载入（打开页面、切换预设时）；尚未保存的密钥草稿保留
    func reload() {
        // 只在不同时赋值：给正在编辑的输入框重复赋同一个值可能清空其显示
        if baseURLText != settings.effectiveTranslationBaseURL { baseURLText = settings.effectiveTranslationBaseURL }
        if modelText != settings.effectiveTranslationModel { modelText = settings.effectiveTranslationModel }
        keyError = nil
        keyLookup = keys.lookup(preset.id)
    }

    // MARK: - 保存

    /// 先把未提交的输入隐式提交（不会自动切换），再采用用户明确选择的引擎
    func selectEngine(_ kind: TranslationEngineKind) {
        commitPendingEdits()
        settings.translationEngine = kind
    }

    func selectPreset(_ id: String) {
        guard id != settings.translationProviderID else { return }
        cancelProbes()
        saving(.userEdit) {
            settings.selectTranslationProvider(id)
            keyLookup = keys.lookup(id)
        }
        keyDraft = ""
        models = []
        modelsState = .idle
        testState = .idle
        reload()
    }

    /// 地址有效时保存（与预设默认值相同则清空，跟随预设）；无效时保留输入、不保存
    func commitBaseURL() {
        commitBaseURL(trigger: .userEdit)
    }

    func selectEndpoint(_ url: String) {
        baseURLText = url
        commitBaseURL()
    }

    func commitModel() {
        commitModel(trigger: .userEdit)
    }

    func selectModel(_ model: String) {
        modelText = model
        commitModel()
    }

    /// 保存密钥并绑定到当前地址；地址无效时不保存
    func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        commitBaseURL()
        commitModel()
        guard let url = savedBaseURL else {
            keyError = TranslationSettingsCopy.message(for: baseURLIssue ?? .malformed)
            return
        }
        do {
            try saving(.userEdit) {
                try keys.save(key, for: preset.id, boundTo: url)
                keyLookup = keys.lookup(preset.id)
            }
            keyDraft = ""
            keyError = nil
        } catch {
            keyError = TranslationSettingsCopy.keychainError
        }
    }

    func removeKey() {
        do {
            try keys.remove(preset.id)
            keyLookup = keys.lookup(preset.id)
            keyError = nil
            testState = .idle
        } catch {
            keyError = TranslationSettingsCopy.keychainError
        }
    }

    /// 用户点「重试」：重新访问钥匙串（此前的失败不再沿用）
    func retryKeychain() {
        keyLookup = keys.retry(preset.id)
        keyError = nil
    }

    /// 关闭设置窗口、切换引擎前提交输入框中尚未提交的地址与模型：隐式提交，从不切换引擎
    func commitPendingEdits() {
        commitBaseURL(trigger: .implicit)
        commitModel(trigger: .implicit)
    }

    // MARK: - 探测

    /// 只带与该地址绑定的密钥，绝不把密钥发往别的主机
    func refreshModels() {
        commitBaseURL()
        guard let url = savedBaseURL, baseURLIssue == nil else {
            modelsState = .failed(TranslationSettingsCopy.message(for: baseURLIssue ?? .malformed))
            return
        }
        let endpoint = LLMEndpoint(baseURL: url, apiKey: LLMKeyState(keyLookup, baseURL: url).usableKey)
        modelsState = .running
        modelsTask?.cancel()
        modelsTask = Task { [session] in
            do {
                let models = try await LLMServiceProbe.models(for: endpoint, session: session)
                guard !Task.isCancelled else { return }
                self.models = models
                self.modelsState = .succeeded(TranslationSettingsCopy.modelCount(models.count))
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.modelsState = .failed(
                    TranslationSettingsCopy.message(for: error, host: LLMBaseURL.displayHost(url)))
            }
        }
    }

    func testConnection() {
        commitBaseURL()
        commitModel()
        let configuration: LLMConfiguration
        switch settings.llmConfiguration(key: keyLookup) {
        case .success(let valid): configuration = valid
        case .failure(let issue):
            testState = .failed(TranslationSettingsCopy.message(for: issue, currentHost: host ?? baseURLText))
            return
        }
        testState = .running
        let engine = LLMTranslationEngine(configuration: configuration, session: session)
        let target = connectionTestTarget
        testTask?.cancel()
        testTask = Task {
            do {
                let result = try await LLMServiceProbe.testConnection(engine, target: target)
                guard !Task.isCancelled else { return }
                self.testState = .succeeded(TranslationSettingsCopy.connected(result, model: configuration.model))
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.testState = .failed(
                    TranslationSettingsCopy.message(
                        for: error, host: LLMBaseURL.displayHost(configuration.endpoint.baseURL)))
            }
        }
    }

    // MARK: - 内部

    private func commitBaseURL(trigger: LLMSettingsSaveTrigger) {
        guard case .success(let url) = LLMBaseURL.validate(baseURLText) else { return }
        let normalized = url.absoluteString
        if baseURLText != normalized { baseURLText = normalized }
        guard normalized != settings.effectiveTranslationBaseURL else { return }
        saving(trigger) { settings.translationBaseURL = normalized == preset.defaultBaseURL ? nil : normalized }
    }

    private func commitModel(trigger: LLMSettingsSaveTrigger) {
        let cleaned = LLMModelName.cleaned(modelText)
        if modelText != cleaned { modelText = cleaned }
        guard cleaned != settings.effectiveTranslationModel else { return }
        saving(trigger) {
            settings.translationModel = cleaned.isEmpty || cleaned == preset.suggestedModel ? nil : cleaned
        }
        if cleaned.isEmpty { modelText = settings.effectiveTranslationModel }
    }

    /// 执行一次保存，并按保存前后配置是否完整与保存来源决定是否自动切到大模型
    private func saving(_ trigger: LLMSettingsSaveTrigger, _ change: () throws -> Void) rethrows {
        let wasComplete = isConfigured
        try change()
        let next = settings.translationEngine.afterSavingLLMSettings(
            wasComplete: wasComplete, isComplete: isConfigured, trigger: trigger)
        if next != settings.translationEngine { settings.translationEngine = next }
    }

    /// 测试连接的目标语言：选定的，否则第一个非英语的首选语言，否则简体中文
    private var connectionTestTarget: String {
        settings.translationTargetLanguage
            ?? Locale.preferredLanguages.compactMap(TranslationLanguageCatalog.normalize).first { $0 != "en" }
            ?? "zh-Hans"
    }

    private func cancelProbes() {
        modelsTask?.cancel()
        testTask?.cancel()
        modelsTask = nil
        testTask = nil
    }
}
