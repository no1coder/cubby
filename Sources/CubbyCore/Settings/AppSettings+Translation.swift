import Foundation

/// 截图翻译设置的派生值与组合操作（存储属性见 AppSettings）
extension AppSettings {
    /// 当前的大模型服务预设（id 失效时回退默认预设）
    public var translationPreset: LLMProviderPreset {
        LLMProviderPreset.preset(id: translationProviderID) ?? .standard
    }

    /// 实际使用的接入地址：用户填写的，否则预设的默认地址
    public var effectiveTranslationBaseURL: String {
        translationBaseURL ?? translationPreset.defaultBaseURL
    }

    /// 实际使用的模型名：用户填写的，否则预设的建议模型（可能为空）
    public var effectiveTranslationModel: String {
        translationModel ?? translationPreset.suggestedModel ?? ""
    }

    /// 切换服务预设：地址与模型回到该预设的默认值（密钥按预设分别保存在钥匙串，不受影响）
    public func selectTranslationProvider(_ id: String) {
        guard let preset = LLMProviderPreset.preset(id: id), preset.id != translationProviderID else { return }
        translationProviderID = preset.id
        translationBaseURL = nil
        translationModel = nil
    }

    /// 用当前设置与钥匙串中该预设的密钥组装大模型配置（密钥须与当前地址绑定，见 LLMStoredKey）
    public func llmConfiguration(key: LLMStoredKeyLookup) -> Result<LLMConfiguration, LLMConfigurationIssue> {
        LLMConfiguration.make(
            preset: translationPreset, baseURL: effectiveTranslationBaseURL, model: effectiveTranslationModel,
            key: key)
    }
}
