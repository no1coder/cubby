import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 截图翻译设置")
@MainActor
struct AppSettingsTranslationTests {
    @Test("默认值：系统翻译、自动目标语言、DeepSeek 预设及其默认地址与建议模型")
    func defaults() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.translationEngine == .system)
            #expect(settings.translationTargetLanguage == nil)
            #expect(settings.translationProviderID == "deepseek")
            #expect(settings.translationBaseURL == nil)
            #expect(settings.translationModel == nil)
            #expect(settings.effectiveTranslationBaseURL == "https://api.deepseek.com")
            #expect(settings.effectiveTranslationModel == "deepseek-flash")
        }
    }

    @Test("各项写入 UserDefaults 后可被新实例读回")
    func persists() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.translationEngine = .llm
            settings.translationTargetLanguage = "ja"
            settings.translationProviderID = "kimi"
            settings.translationBaseURL = "https://api.moonshot.ai/v1"
            settings.translationModel = "kimi-model"

            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.translationEngine == .llm)
            #expect(reloaded.translationTargetLanguage == "ja")
            #expect(reloaded.translationProviderID == "kimi")
            #expect(reloaded.effectiveTranslationBaseURL == "https://api.moonshot.ai/v1")
            #expect(reloaded.effectiveTranslationModel == "kimi-model")
            #expect(defaults.string(forKey: "translationEngine") == "llm")
        }
    }

    @Test("设为 nil 或空串时移除键（回到自动 / 预设默认值）")
    func clearingRemovesKeys() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.translationTargetLanguage = "fr"
            settings.translationBaseURL = "https://example.com/v1"
            settings.translationModel = "m"
            settings.translationTargetLanguage = nil
            settings.translationBaseURL = ""
            settings.translationModel = nil
            for key in ["translationTargetLanguage", "translationBaseURL", "translationModel"] {
                #expect(defaults.object(forKey: key) == nil)
            }
            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.translationTargetLanguage == nil)
            #expect(reloaded.translationBaseURL == nil)
        }
    }

    @Test("存储值无效时回退默认：未知引擎、未知预设、空串")
    func invalidStoredValues() {
        withIsolatedDefaults { defaults in
            defaults.set("quantum", forKey: "translationEngine")
            defaults.set("unknown-provider", forKey: "translationProvider")
            defaults.set("", forKey: "translationModel")
            defaults.set("", forKey: "translationTargetLanguage")
            let settings = AppSettings(defaults: defaults)
            #expect(settings.translationEngine == .system)
            #expect(settings.translationProviderID == "deepseek")
            #expect(settings.translationModel == nil)
            #expect(settings.translationTargetLanguage == nil)
        }
    }

    @Test("存储的预设失效时，地址与模型一并回到默认；预设键缺失（从未切换）时保留地址与模型")
    func unknownProviderResetsEndpoint() {
        withIsolatedDefaults { defaults in
            defaults.set("future-provider", forKey: "translationProvider")
            defaults.set("https://future.example.com/v1", forKey: "translationBaseURL")
            defaults.set("future-model", forKey: "translationModel")
            let settings = AppSettings(defaults: defaults)
            #expect(settings.translationProviderID == "deepseek")
            #expect(settings.translationBaseURL == nil)
            #expect(settings.effectiveTranslationModel == "deepseek-flash")

            defaults.removeObject(forKey: "translationProvider")
            defaults.set("https://proxy.example.com/v1", forKey: "translationBaseURL")
            #expect(AppSettings(defaults: defaults).translationBaseURL == "https://proxy.example.com/v1")
        }
    }

    @Test("切换预设：地址与模型回到新预设的默认值；选同一个或未知预设不变")
    func selectProvider() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.translationBaseURL = "https://proxy.example.com/v1"
            settings.translationModel = "custom-model"

            settings.selectTranslationProvider("deepseek")
            #expect(settings.translationModel == "custom-model")

            settings.selectTranslationProvider("nope")
            #expect(settings.translationProviderID == "deepseek")

            settings.selectTranslationProvider("qwen")
            #expect(settings.translationProviderID == "qwen")
            #expect(settings.translationBaseURL == nil)
            #expect(settings.translationModel == nil)
            #expect(settings.effectiveTranslationBaseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1")
            #expect(settings.effectiveTranslationModel == "qwen-plus")

            settings.selectTranslationProvider("kimi")
            #expect(settings.effectiveTranslationModel.isEmpty)
        }
    }

    @Test("用当前设置与钥匙串中的密钥组装配置")
    func configuration() throws {
        try withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let deepseek = try #require(URL(string: "https://api.deepseek.com"))
            #expect(settings.llmConfiguration(key: .none) == .failure(.missingAPIKey))
            let configuration = try settings.llmConfiguration(
                key: .found(LLMStoredKey(key: "sk-test", boundTo: deepseek))
            ).get()
            #expect(configuration.model == "deepseek-flash")
            #expect(configuration.preset.id == "deepseek")
            #expect(configuration.endpoint.apiKey == "sk-test")

            settings.translationBaseURL = "https://proxy.example.com/v1"
            #expect(
                settings.llmConfiguration(key: .found(LLMStoredKey(key: "sk-test", boundTo: deepseek)))
                    == .failure(.keySavedForOtherHost("api.deepseek.com")))

            settings.selectTranslationProvider("ollama")
            #expect(settings.llmConfiguration(key: .none) == .failure(.missingModel))
            settings.translationModel = "qwen3:8b"
            #expect(try settings.llmConfiguration(key: .none).get().endpoint.apiKey == nil)
        }
    }

    @Test("新增翻译键不改变设置格式版本")
    func settingsVersionUnchanged() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).translationEngine = .llm
            #expect(AppSettings.currentSettingsVersion == 1)
            #expect(defaults.integer(forKey: "settingsVersion") == 1)
        }
    }
}
