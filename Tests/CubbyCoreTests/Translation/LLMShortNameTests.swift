import Foundation
import Testing
@testable import CubbyCore

/// 翻译条引擎徽标上的简称：预设只显示品牌，自定义服务显示域名的主体部分（完整名称留在悬停说明里）
@Suite("引擎简称")
struct LLMShortNameTests {
    // MARK: - 自定义服务的主机简称

    @Test(
        "主机简称：去掉子域名、顶级域名与二级公共后缀，取主体部分",
        arguments: [
            ("https://api.siliconflow.cn/v1", "siliconflow"),
            ("https://openrouter.ai/api/v1", "openrouter"),
            ("https://api.example.com.cn/v1", "example"),
            ("https://example.co.uk", "example"),
            ("https://gateway.ai.cloudflare.com/v1/acct/gw/openai", "cloudflare"),
            ("https://llm-gateway.prod.internal.example-corp.com/v1", "example-corp"),
            ("https://myres.openai.azure.com/openai", "azure"),
            ("https://myserver/v1", "myserver"),
            ("https://foo.co", "foo"),
            ("https://API.SiliconFlow.CN/v1", "siliconflow"),
            ("https://api.deepseek.com./v1", "deepseek"),
            ("https://api.deepseek.com:8443/v1", "deepseek"),
        ])
    func shortHost(_ url: String, _ expected: String) throws {
        #expect(LLMBaseURL.shortHost(try #require(URL(string: url))) == expected)
    }

    @Test(
        "主机简称：主体是 punycode 或不超过 2 个字符（多半是没认出的公共后缀）时退回完整主机",
        arguments: [
            ("https://api.xn--fsqu00a.cn/v1", "api.xn--fsqu00a.cn"),
            ("https://api.foo.ne.jp/v1", "api.foo.ne.jp"),
            ("https://x.ai/v1", "x.ai"),
        ])
    func shortHostFallsBack(_ url: String, _ expected: String) throws {
        #expect(LLMBaseURL.shortHost(try #require(URL(string: url))) == expected)
    }

    @Test(
        "主机简称：本机与 IP 地址显示完整主机（不带端口，IPv6 保留方括号）",
        arguments: [
            ("http://localhost:11434/v1", "localhost"),
            ("http://127.0.0.1:1234/v1", "127.0.0.1"),
            ("http://[::1]:8080/v1", "[::1]"),
            ("https://192.168.1.20:8443/v1", "192.168.1.20"),
            ("https://[2001:db8::1]:8443/v1", "[2001:db8::1]"),
        ])
    func shortHostKeepsAddresses(_ url: String, _ expected: String) throws {
        #expect(LLMBaseURL.shortHost(try #require(URL(string: url))) == expected)
    }

    @Test("主机简称：没有主机的地址退回完整地址")
    func shortHostWithoutHost() throws {
        #expect(LLMBaseURL.shortHost(try #require(URL(string: "file:///tmp"))) == "file:///tmp")
    }

    // MARK: - 配置与引擎的简称

    private static func configuration(
        preset id: String, baseURL: String, model: String = "Qwen/Qwen2.5-72B-Instruct"
    ) throws -> LLMConfiguration {
        let preset = try #require(LLMProviderPreset.preset(id: id))
        let url = try #require(URL(string: baseURL))
        return LLMConfiguration(preset: preset, endpoint: LLMEndpoint(baseURL: url, apiKey: "sk"), model: model)
    }

    @Test("预设服务只显示品牌名，不带模型")
    func presetShortName() throws {
        let deepSeek = try Self.configuration(preset: "deepseek", baseURL: "https://api.deepseek.com")
        #expect(deepSeek.shortName == "DeepSeek")
        let ollama = try Self.configuration(preset: "ollama", baseURL: "http://localhost:11434/v1", model: "qwen3:8b")
        #expect(ollama.shortName == "Ollama")
        let qwenPreset = try #require(LLMProviderPreset.preset(id: "qwen"))
        let qwen = try Self.configuration(preset: "qwen", baseURL: qwenPreset.defaultBaseURL, model: "qwen-plus")
        #expect(qwen.shortName == qwenPreset.shortName)
        #expect(!qwen.shortName.contains("qwen-plus"))
    }

    @Test("自定义服务显示域名主体；完整的主机与模型仍在 displayName 里")
    func customShortName() throws {
        let remote = try Self.configuration(preset: "custom", baseURL: "https://api.siliconflow.cn/v1")
        #expect(remote.shortName == "siliconflow")
        #expect(remote.displayName == "api.siliconflow.cn · Qwen/Qwen2.5-72B-Instruct")
        let local = try Self.configuration(preset: "custom", baseURL: "http://127.0.0.1:1234/v1")
        #expect(local.shortName == "127.0.0.1")
    }

    @Test("大模型引擎的简称来自配置")
    func llmEngineShortName() throws {
        let configuration = try Self.configuration(preset: "custom", baseURL: "https://openrouter.ai/api/v1")
        let engine = LLMTranslationEngine(configuration: configuration, session: URLSession(configuration: .ephemeral))
        #expect(engine.shortName == "openrouter")
        #expect(engine.displayName == configuration.displayName)
        // 生产路径经由 any TranslationEngine：shortName 必须是协议要求才会派发到这里的实现
        let erased: any TranslationEngine = engine
        #expect(erased.shortName == "openrouter")
    }

    @Test("没有实现简称的引擎沿用显示名")
    func defaultEngineShortName() {
        #expect(NamedEngine(displayName: "System Translation").shortName == "System Translation")
    }

    // MARK: - 徽标

    @Test("徽标：简称默认与名称相同，也可单独给出")
    func badgeShortName() {
        #expect(TranslationEngineBadge(name: "Stub", sendsTextOffDevice: false).shortName == "Stub")
        let badge = TranslationEngineBadge(
            name: "api.siliconflow.cn · Qwen/Qwen2.5-72B-Instruct", shortName: "siliconflow", sendsTextOffDevice: true)
        #expect(badge.name == "api.siliconflow.cn · Qwen/Qwen2.5-72B-Instruct")
        #expect(badge.shortName == "siliconflow")
    }
}

/// 只给出显示名的引擎（验证协议扩展里的默认简称）
private struct NamedEngine: TranslationEngine {
    let displayName: String
    let sendsTextOffDevice = false

    func translate(_ blocks: [TextBlock], languages: TranslationLanguages) -> AsyncThrowingStream<
        BlockTranslation, any Error
    > {
        AsyncThrowingStream { $0.finish() }
    }
}
