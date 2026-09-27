import Foundation

/// 兼容 OpenAI Chat Completions 接口的大模型服务预设（docs/TRANSLATION-DESIGN.md D3）。
/// 地址均取自各服务商的官方文档（2026-09 核实）；默认模型只在官方文档确认为当前可用时才给出，
/// 其余留空，由用户从模型列表中选择或手动输入
public struct LLMProviderPreset: Equatable, Sendable, Identifiable {
    /// 预设 id：写入设置，并作为钥匙串条目的 account，发布后不可改名
    public let id: String
    /// 可选的接入地址，第一个为默认；「自定义」为空
    public let endpoints: [LLMEndpointOption]
    /// 建议的默认模型；nil 表示需要用户选择
    public let suggestedModel: String?
    /// 品牌名（不翻译）；nil 表示使用本地化名称
    private let brandName: String?

    init(id: String, brandName: String?, endpoints: [LLMEndpointOption], suggestedModel: String?) {
        self.id = id
        self.brandName = brandName
        self.endpoints = endpoints
        self.suggestedModel = suggestedModel
    }

    /// 默认接入地址（「自定义」为空串）
    public var defaultBaseURL: String {
        endpoints.first?.url ?? ""
    }

    /// 设置界面服务商选单里的名称
    public var displayName: String {
        if let brandName { return brandName }
        switch id {
        case Self.qwenID:
            return String(localized: "Qwen (Alibaba Cloud)", comment: "Translation provider preset name")
        case Self.glmID:
            return String(localized: "Zhipu GLM", comment: "Translation provider preset name")
        case Self.ollamaID:
            return String(localized: "Ollama (on this Mac)", comment: "Translation provider preset name")
        default:
            return String(localized: "Custom", comment: "Translation provider preset name")
        }
    }

    /// 翻译条引擎徽标里的简称（「Ollama（本机）」只显示 Ollama）
    public var shortName: String {
        id == Self.ollamaID ? "Ollama" : displayName
    }

    /// 是否为本机服务（Ollama）：默认地址在本机，不需要密钥
    public var isLocalService: Bool {
        !endpoints.isEmpty && endpoints.allSatisfy { $0.region == .thisMac }
    }

    /// 是否为「自定义」（地址由用户填写）
    public var isCustom: Bool {
        id == Self.customID
    }
}

/// 一个接入地址及其所属地域
public struct LLMEndpointOption: Equatable, Sendable {
    public enum Region: Equatable, Sendable {
        case chinaMainland
        case international
        case unitedStates
        case thisMac
    }

    public let region: Region
    public let url: String

    /// 地址选单里的地域名
    public var regionName: String {
        switch region {
        case .chinaMainland:
            String(localized: "China mainland", comment: "Translation provider endpoint region")
        case .international:
            String(localized: "International", comment: "Translation provider endpoint region")
        case .unitedStates:
            String(localized: "United States", comment: "Translation provider endpoint region")
        case .thisMac:
            String(localized: "This Mac", comment: "Translation provider endpoint region")
        }
    }
}

extension LLMProviderPreset {
    static let deepSeekID = "deepseek"
    static let qwenID = "qwen"
    static let kimiID = "kimi"
    static let glmID = "glm"
    static let openAIID = "openai"
    static let openRouterID = "openrouter"
    static let ollamaID = "ollama"
    static let customID = "custom"

    /// 设置界面的服务商选单（按此顺序显示）
    public static let all: [LLMProviderPreset] = [
        // api-docs.deepseek.com：base_url 为 https://api.deepseek.com；deepseek-flash 为当前模型名
        LLMProviderPreset(
            id: deepSeekID, brandName: "DeepSeek",
            endpoints: [.init(region: .international, url: "https://api.deepseek.com")],
            suggestedModel: "deepseek-flash"),
        // help.aliyun.com/en/model-studio/base-url：DashScope 共享域名（北京 / 新加坡 / 弗吉尼亚）仍可用
        LLMProviderPreset(
            id: qwenID, brandName: nil,
            endpoints: [
                .init(region: .chinaMainland, url: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
                .init(region: .international, url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
                .init(region: .unitedStates, url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1"),
            ],
            suggestedModel: "qwen-plus"),
        // platform.kimi.com / platform.kimi.ai：api.moonshot.cn/v1（中国）与 api.moonshot.ai/v1（国际）；
        // 文档未给出推荐模型，从 /v1/models 选择
        LLMProviderPreset(
            id: kimiID, brandName: "Kimi",
            endpoints: [
                .init(region: .chinaMainland, url: "https://api.moonshot.cn/v1"),
                .init(region: .international, url: "https://api.moonshot.ai/v1"),
            ],
            suggestedModel: nil),
        // docs.bigmodel.cn（open.bigmodel.cn）与 docs.z.ai（国际版 Z.ai）：/api/paas/v4
        LLMProviderPreset(
            id: glmID, brandName: nil,
            endpoints: [
                .init(region: .chinaMainland, url: "https://open.bigmodel.cn/api/paas/v4"),
                .init(region: .international, url: "https://api.z.ai/api/paas/v4"),
            ],
            suggestedModel: "glm-5.3"),
        // developers.openai.com/api/docs/models：gpt-6-luna 为面向大批量任务的高效模型
        LLMProviderPreset(
            id: openAIID, brandName: "OpenAI",
            endpoints: [.init(region: .international, url: "https://api.openai.com/v1")],
            suggestedModel: "gpt-6-luna"),
        // openrouter.ai/docs：模型众多，从 /models 选择
        LLMProviderPreset(
            id: openRouterID, brandName: "OpenRouter",
            endpoints: [.init(region: .international, url: "https://openrouter.ai/api/v1")],
            suggestedModel: nil),
        // docs.ollama.com/api/openai-compatibility：本机 /v1，模型取决于用户已拉取的模型
        LLMProviderPreset(
            id: ollamaID, brandName: nil,
            endpoints: [.init(region: .thisMac, url: "http://localhost:11434/v1")],
            suggestedModel: nil),
        LLMProviderPreset(id: customID, brandName: nil, endpoints: [], suggestedModel: nil),
    ]

    /// 默认预设（与原型一致）
    public static var standard: LLMProviderPreset {
        all[0]
    }

    /// 按 id 查找；未知 id（例如被更新版本写入）返回 nil
    public static func preset(id: String) -> LLMProviderPreset? {
        all.first { $0.id == id }
    }
}
