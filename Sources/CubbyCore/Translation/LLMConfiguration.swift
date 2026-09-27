import Foundation

/// 截图翻译使用的引擎（设置 › 翻译）
public enum TranslationEngineKind: String, CaseIterable, Sendable {
    /// 系统翻译（Apple 本机，默认）
    case system
    /// 兼容 OpenAI 接口的大模型
    case llm

    /// 自动切换规则（D2）：用户保存设置后，大模型配置从「不完整」变为「完整」时切到大模型；
    /// 其余情况保持当前选择（用户切回系统翻译后，再改模型名不会被切走）。
    /// 隐式提交（关闭设置窗口、切换引擎前提交未提交的输入）从不切换，以免推翻用户明确的选择
    public func afterSavingLLMSettings(
        wasComplete: Bool, isComplete: Bool, trigger: LLMSettingsSaveTrigger
    ) -> TranslationEngineKind {
        trigger == .userEdit && isComplete && !wasComplete ? .llm : self
    }
}

/// 大模型设置的保存来源
public enum LLMSettingsSaveTrigger: Equatable, Sendable {
    /// 用户的保存动作：回车、离开输入框、从菜单选择、保存密钥、切换服务商
    case userEdit
    /// 顺带提交尚未提交的输入：关闭设置窗口、切换引擎之前
    case implicit
}

/// 大模型配置不完整的原因
public enum LLMConfigurationIssue: Error, Equatable, Sendable {
    case invalidBaseURL(LLMBaseURLError)
    case missingModel
    case missingAPIKey
    /// 保存的密钥属于另一个主机（关联值），不会发往当前地址
    case keySavedForOtherHost(String)
    /// 无法读取钥匙串（用户拒绝访问或钥匙串已锁定）
    case keychainUnavailable

    /// 翻译时对应的失败（契约 TranslationFailure 已冻结，取最接近的情况）：
    /// 钥匙串无法访问 → unauthorized（密钥存在但无权使用，「去设置」后可在设置中重试）；其余 → notConfigured
    public var translationFailure: TranslationFailure {
        self == .keychainUnavailable ? .unauthorized : .notConfigured
    }
}

/// 接入点：地址与密钥（密钥为 nil 时请求不带 Authorization）
public struct LLMEndpoint: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let baseURL: URL
    public let apiKey: String?

    public init(baseURL: URL, apiKey: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 文字是否会离开这台 Mac（主机不是本机）
    public var sendsTextOffDevice: Bool {
        !LLMBaseURL.isLoopback(baseURL)
    }

    // 打印、日志与断言失败信息中不出现密钥
    public var description: String {
        "LLMEndpoint(\(LLMBaseURL.displayHost(baseURL)), apiKey: \(apiKey == nil ? "none" : "redacted"))"
    }

    public var debugDescription: String {
        description
    }
}

/// 一份完整、可用于翻译的大模型配置
public struct LLMConfiguration: Equatable, Sendable {
    public let preset: LLMProviderPreset
    public let endpoint: LLMEndpoint
    public let model: String

    /// 校验并组装：地址有效、模型已填；非本机地址需要与该地址绑定的密钥。
    /// 本机地址（Ollama 等）可以不带密钥：保存的密钥与当前地址不匹配或无法读取时不带
    public static func make(
        preset: LLMProviderPreset, baseURL: String, model: String, key: LLMStoredKeyLookup
    ) -> Result<LLMConfiguration, LLMConfigurationIssue> {
        let url: URL
        switch LLMBaseURL.validate(baseURL) {
        case .success(let valid): url = valid
        case .failure(let error): return .failure(.invalidBaseURL(error))
        }
        let cleanedModel = LLMModelName.cleaned(model)
        guard !cleanedModel.isEmpty else { return .failure(.missingModel) }
        let state = LLMKeyState(key, baseURL: url)
        if requiresAPIKey(url) {
            switch state {
            case .available: break
            case .missing: return .failure(.missingAPIKey)
            case .savedForOtherHost(let host): return .failure(.keySavedForOtherHost(host))
            case .inaccessible: return .failure(.keychainUnavailable)
            }
        }
        let endpoint = LLMEndpoint(baseURL: url, apiKey: state.usableKey)
        return .success(LLMConfiguration(preset: preset, endpoint: endpoint, model: cleanedModel))
    }

    /// 非本机地址必须有密钥；本机服务（Ollama 等）可以不填
    public static func requiresAPIKey(_ baseURL: URL) -> Bool {
        !LLMBaseURL.isLoopback(baseURL)
    }

    /// 翻译条上的引擎名：「DeepSeek · 模型名」；自定义服务显示主机名
    public var displayName: String {
        let provider = preset.isCustom ? LLMBaseURL.displayHost(endpoint.baseURL) : preset.shortName
        return "\(provider) · \(model)"
    }
}

/// 模型名的清理：服务返回的列表与用户输入的名称都会出现在菜单、翻译条与设置中
public enum LLMModelName {
    /// 模型名上限（Unicode 标量数）
    public static let maxLength = 200

    /// 服务返回的模型名：含空白、控制或格式字符、为空或过长的整个丢弃（截断会得到错误的名称）
    public static func validated(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.unicodeScalars.count <= maxLength,
            raw.unicodeScalars.allSatisfy({ !isDisallowed($0) && !$0.properties.isWhitespace })
        else { return nil }
        return raw
    }

    /// 用户输入的模型名：去掉控制与格式字符和首尾空白，截到上限
    public static func cleaned(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: raw.unicodeScalars.filter { !isDisallowed($0) })
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(maxLength)))
    }

    private static func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: true
        default: false
        }
    }
}
