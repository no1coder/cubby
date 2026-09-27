import Foundation
import Testing
@testable import CubbyCore

@Suite("大模型接入地址、预设与配置")
struct LLMConfigurationTests {
    // MARK: - 地址校验

    @Test(
        "有效地址：规范化末尾斜杠与空白，省略协议时补 https",
        arguments: [
            ("https://api.deepseek.com", "https://api.deepseek.com"),
            ("  https://api.openai.com/v1/  ", "https://api.openai.com/v1"),
            ("api.moonshot.cn/v1", "https://api.moonshot.cn/v1"),
            ("HTTPS://Example.com:8443/v1", "HTTPS://Example.com:8443/v1"),
            ("http://localhost:11434/v1", "http://localhost:11434/v1"),
            ("http://127.0.0.1:1234/v1", "http://127.0.0.1:1234/v1"),
            ("http://[::1]:11434/v1", "http://[::1]:11434/v1"),
        ])
    func validURLs(_ input: String, _ expected: String) throws {
        #expect(try LLMBaseURL.validate(input).get().absoluteString == expected)
    }

    @Test(
        "无效地址",
        arguments: [
            ("", LLMBaseURLError.empty), ("  / ", .empty), ("http://api.example.com/v1", .insecure),
            ("http://192.168.1.2:11434/v1", .insecure), ("http://localhost.evil.com/v1", .insecure),
            ("ftp://example.com", .malformed), ("https://", .malformed),
            ("https://user:pass@example.com", .unsupportedComponents),
            ("https://example.com/v1?key=1", .unsupportedComponents),
            ("https://example.com/v1#x", .unsupportedComponents),
            ("https://exa mple.com", .malformed),
        ])
    func invalidURLs(_ input: String, _ expected: LLMBaseURLError) {
        #expect(LLMBaseURL.validate(input) == .failure(expected))
    }

    @Test("本机判断与显示用主机名")
    func loopbackAndDisplayHost() throws {
        let local = try #require(URL(string: "http://[::1]:11434/v1"))
        #expect(LLMBaseURL.isLoopback(local))
        #expect(LLMBaseURL.displayHost(local) == "[::1]:11434")
        let remote = try #require(URL(string: "https://API.DeepSeek.com"))
        #expect(!LLMBaseURL.isLoopback(remote))
        #expect(LLMBaseURL.displayHost(remote) == "api.deepseek.com")
        #expect(LLMBaseURL.displayHost(try #require(URL(string: "file:///tmp"))) == "file:///tmp")
        #expect(!LLMBaseURL.isLoopback(try #require(URL(string: "file:///tmp"))))
    }

    @Test("重定向只允许同一协议、主机与端口")
    func redirectPolicy() throws {
        let base = try #require(URL(string: "https://api.example.com/v1/chat/completions"))
        func allows(_ destination: String) throws -> Bool {
            LLMBaseURL.allowsRedirect(from: base, to: try #require(URL(string: destination)))
        }
        #expect(try allows("https://API.example.com/v2/chat/completions"))
        #expect(try allows("https://api.example.com:443/v1/x"))
        #expect(try !allows("https://evil.example.net/v1/chat/completions"))
        #expect(try !allows("http://api.example.com/v1/chat/completions"))
        #expect(try !allows("https://api.example.com:8443/v1"))
        let local = try #require(URL(string: "http://localhost:11434/v1/models"))
        #expect(LLMBaseURL.allowsRedirect(from: local, to: try #require(URL(string: "http://localhost:11434/v1/m"))))
        #expect(!LLMBaseURL.allowsRedirect(from: local, to: try #require(URL(string: "http://localhost/v1/m"))))
    }

    @Test("接口路径拼接在接入地址之后")
    func endpointPath() throws {
        let base = try LLMBaseURL.validate("https://open.bigmodel.cn/api/paas/v4").get()
        #expect(
            LLMBaseURL.endpoint(base, path: "chat/completions").absoluteString
                == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
    }

    // MARK: - 预设

    @Test("预设：顺序、唯一 id、默认地址都是有效的 https（Ollama 为本机 http）")
    func presets() throws {
        let presets = LLMProviderPreset.all
        #expect(presets.map(\.id) == ["deepseek", "qwen", "kimi", "glm", "openai", "openrouter", "ollama", "custom"])
        #expect(LLMProviderPreset.standard.id == "deepseek")
        for preset in presets where !preset.isCustom {
            for endpoint in preset.endpoints {
                let url = try LLMBaseURL.validate(endpoint.url).get()
                #expect(url.absoluteString == endpoint.url)
                #expect(url.scheme == (preset.id == "ollama" ? "http" : "https"))
                #expect(!endpoint.regionName.isEmpty)
            }
            #expect(preset.defaultBaseURL == preset.endpoints.first?.url)
        }
        let custom = try #require(LLMProviderPreset.preset(id: "custom"))
        #expect(custom.isCustom && custom.defaultBaseURL.isEmpty && custom.suggestedModel == nil)
        #expect(presets.filter(\.isLocalService).map(\.id) == ["ollama"])
        #expect(LLMProviderPreset.preset(id: "nope") == nil)
    }

    @Test("预设的官方地址（含地域）")
    func presetEndpoints() {
        func urls(_ id: String) -> [String] { LLMProviderPreset.preset(id: id)?.endpoints.map(\.url) ?? [] }
        #expect(urls("deepseek") == ["https://api.deepseek.com"])
        #expect(
            urls("qwen") == [
                "https://dashscope.aliyuncs.com/compatible-mode/v1",
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                "https://dashscope-us.aliyuncs.com/compatible-mode/v1",
            ])
        #expect(urls("kimi") == ["https://api.moonshot.cn/v1", "https://api.moonshot.ai/v1"])
        #expect(urls("glm") == ["https://open.bigmodel.cn/api/paas/v4", "https://api.z.ai/api/paas/v4"])
        #expect(urls("openai") == ["https://api.openai.com/v1"])
        #expect(urls("openrouter") == ["https://openrouter.ai/api/v1"])
        #expect(urls("ollama") == ["http://localhost:11434/v1"])
    }

    @Test("名称：品牌名不翻译；Ollama 的简称不带「本机」")
    func presetNames() throws {
        #expect(try #require(LLMProviderPreset.preset(id: "openai")).displayName == "OpenAI")
        let ollama = try #require(LLMProviderPreset.preset(id: "ollama"))
        #expect(ollama.shortName == "Ollama")
        #expect(ollama.displayName != "Ollama")
        for preset in LLMProviderPreset.all {
            #expect(!preset.displayName.isEmpty && !preset.shortName.isEmpty)
        }
        let regions: [LLMEndpointOption.Region] = [.chinaMainland, .international, .unitedStates, .thisMac]
        #expect(Set(regions.map { LLMEndpointOption(region: $0, url: "").regionName }).count == 4)
    }

    // MARK: - 配置

    private static let deepseekURL = URL(string: "https://api.deepseek.com")!

    private static func key(_ value: String, for url: URL = deepseekURL) -> LLMStoredKeyLookup {
        .found(LLMStoredKey(key: value, boundTo: url))
    }

    @Test("完整配置：去掉模型首尾空白，使用与地址匹配的密钥")
    func completeConfiguration() throws {
        let configuration = try LLMConfiguration.make(
            preset: .standard, baseURL: "https://api.deepseek.com/", model: " deepseek-flash ",
            key: Self.key("sk-abc")
        ).get()
        #expect(configuration.model == "deepseek-flash")
        #expect(configuration.endpoint.apiKey == "sk-abc")
        #expect(configuration.endpoint.baseURL.absoluteString == "https://api.deepseek.com")
        #expect(configuration.displayName == "DeepSeek · deepseek-flash")
        #expect(configuration.endpoint.sendsTextOffDevice)
    }

    @Test("不完整的原因：地址无效、缺模型、非本机缺密钥、密钥属于其他主机、钥匙串无法访问")
    func incompleteConfiguration() {
        #expect(
            LLMConfiguration.make(preset: .standard, baseURL: "", model: "m", key: Self.key("k"))
                == .failure(.invalidBaseURL(.empty)))
        #expect(
            LLMConfiguration.make(
                preset: .standard, baseURL: "https://api.deepseek.com", model: "  ", key: Self.key("k"))
                == .failure(.missingModel))
        #expect(
            LLMConfiguration.make(preset: .standard, baseURL: "https://a.com", model: "m", key: .none)
                == .failure(.missingAPIKey))
        #expect(
            LLMConfiguration.make(preset: .standard, baseURL: "https://a.com", model: "m", key: Self.key("k"))
                == .failure(.keySavedForOtherHost("api.deepseek.com")))
        #expect(
            LLMConfiguration.make(preset: .standard, baseURL: "https://a.com", model: "m", key: .inaccessible)
                == .failure(.keychainUnavailable))
    }

    @Test("同一预设内切换地域也要重新填写密钥（各地域的密钥互不通用）")
    func regionSwitchNeedsNewKey() throws {
        let qwen = try #require(LLMProviderPreset.preset(id: "qwen"))
        let china = try #require(URL(string: qwen.endpoints[0].url))
        let result = LLMConfiguration.make(
            preset: qwen, baseURL: qwen.endpoints[1].url, model: "qwen-plus", key: Self.key("sk", for: china))
        #expect(result == .failure(.keySavedForOtherHost("dashscope.aliyuncs.com")))
    }

    @Test("本机地址不需要密钥；不匹配或无法读取的密钥不发送；自定义服务显示主机名")
    func localAndCustom() throws {
        let custom = try #require(LLMProviderPreset.preset(id: "custom"))
        let local = "http://127.0.0.1:1234/v1"
        for lookup in [LLMStoredKeyLookup.none, .inaccessible, Self.key("sk-remote")] {
            let configuration = try LLMConfiguration.make(
                preset: custom, baseURL: local, model: "local-model", key: lookup
            ).get()
            #expect(configuration.endpoint.apiKey == nil)
        }
        let withKey = try LLMConfiguration.make(
            preset: custom, baseURL: local, model: "local-model", key: Self.key("sk-local", for: URL(string: local)!)
        ).get()
        #expect(withKey.endpoint.apiKey == "sk-local")
        #expect(!withKey.endpoint.sendsTextOffDevice)
        #expect(withKey.displayName == "127.0.0.1:1234 · local-model")
    }

    @Test("配置问题对应的翻译失败：钥匙串无法访问 → unauthorized，其余 → notConfigured")
    func issueFailures() {
        #expect(LLMConfigurationIssue.keychainUnavailable.translationFailure == .unauthorized)
        let others: [LLMConfigurationIssue] = [
            .invalidBaseURL(.empty), .missingModel, .missingAPIKey, .keySavedForOtherHost("a.com"),
        ]
        #expect(others.allSatisfy { $0.translationFailure == .notConfigured })
    }

    @Test("打印接入点时不出现密钥")
    func endpointRedactsKey() throws {
        let url = try #require(URL(string: "https://api.example.com/v1"))
        let endpoint = LLMEndpoint(baseURL: url, apiKey: "sk-secret-value")
        #expect(!String(describing: endpoint).contains("sk-secret-value"))
        #expect(!String(reflecting: endpoint).contains("sk-secret-value"))
        #expect(String(describing: LLMEndpoint(baseURL: url, apiKey: "")).contains("none"))
    }

    // MARK: - 自动切换

    @Test("用户保存且配置从不完整变为完整时切到大模型，其余情况保持")
    func autoSwitch() {
        func next(_ kind: TranslationEngineKind, _ was: Bool, _ now: Bool) -> TranslationEngineKind {
            kind.afterSavingLLMSettings(wasComplete: was, isComplete: now, trigger: .userEdit)
        }
        #expect(next(.system, false, true) == .llm)
        #expect(next(.system, true, true) == .system)
        #expect(next(.system, false, false) == .system)
        #expect(next(.llm, true, false) == .llm)
    }

    @Test("隐式提交（关窗、切换引擎前）从不切换引擎，保留用户明确的选择")
    func implicitCommitNeverSwitches() {
        for kind in TranslationEngineKind.allCases {
            for was in [false, true] {
                for now in [false, true] {
                    #expect(kind.afterSavingLLMSettings(wasComplete: was, isComplete: now, trigger: .implicit) == kind)
                }
            }
        }
    }

    // MARK: - 模型名

    @Test("服务返回的模型名：含空白、控制或格式字符、为空或过长的丢弃")
    func validatedModelNames() {
        #expect(LLMModelName.validated("deepseek-flash") == "deepseek-flash")
        #expect(LLMModelName.validated("openai/gpt-6-luna:beta") == "openai/gpt-6-luna:beta")
        for bad in ["", "two words", "line\nbreak", "tab\t", "zero\u{200B}width", "bell\u{07}", "rtl\u{202E}x"] {
            #expect(LLMModelName.validated(bad) == nil)
        }
        #expect(LLMModelName.validated(String(repeating: "m", count: LLMModelName.maxLength)) != nil)
        #expect(LLMModelName.validated(String(repeating: "m", count: LLMModelName.maxLength + 1)) == nil)
    }

    @Test("用户输入的模型名：去掉首尾空白与控制、格式字符，截到上限")
    func cleanedModelNames() {
        #expect(LLMModelName.cleaned("  qwen3:8b\n") == "qwen3:8b")
        #expect(LLMModelName.cleaned("gpt\u{200B}-\u{07}6") == "gpt-6")
        #expect(LLMModelName.cleaned(String(repeating: "m", count: 500)).count == LLMModelName.maxLength)
        #expect(LLMModelName.cleaned(" \u{200B} ").isEmpty)
    }

    @Test("组装配置时模型名同样被清理")
    func configurationCleansModel() throws {
        let configuration = try LLMConfiguration.make(
            preset: .standard, baseURL: "https://api.deepseek.com", model: "deep\u{200B}seek-flash\u{07}",
            key: Self.key("k")
        ).get()
        #expect(configuration.model == "deepseek-flash")
    }
}
