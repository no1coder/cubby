import Foundation
import Testing
@testable import CubbyCore

@Suite("模型列表与测试连接（URLProtocol 桩，不联网）", .timeLimit(.minutes(1)))
struct LLMServiceProbeTests {
    private func json(_ object: Any) -> StubResponse {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return StubResponse(headers: ["Content-Type": "application/json"], steps: [.send(data)])
    }

    @Test("GET models：带密钥，按名称排序去重")
    func listsModels() async throws {
        let server = StubServer(
            json(["object": "list", "data": [["id": "model-b"], ["id": "model-a"], ["id": "model-b"], ["id": ""]]]))
        let endpoint = LLMEndpoint(baseURL: server.baseURL, apiKey: "sk-test")
        let models = try await LLMServiceProbe.models(for: endpoint, session: server.makeSession())
        #expect(models == ["model-a", "model-b"])
        let request = try #require(server.requests.first?.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url == server.baseURL.appending(path: "models"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("模型列表：含空白、控制或格式字符及过长的 id 被丢弃")
    func dropsInvalidModelIDs() async throws {
        let long = String(repeating: "x", count: LLMModelName.maxLength + 1)
        let ids = ["ok-model", "bad\nline", "two words", "zw\u{200B}sp", long, "vendor/model:tag"]
        let server = StubServer(json(["data": ids.map { ["id": $0] }]))
        let models = try await LLMServiceProbe.models(
            for: LLMEndpoint(baseURL: server.baseURL, apiKey: nil), session: server.makeSession())
        #expect(models == ["ok-model", "vendor/model:tag"])
    }

    @Test("模型列表响应超过 4 MiB 时停止读取并报告无法识别")
    func modelListSizeCap() async {
        let chunk = Data(repeating: UInt8(ascii: " "), count: 1 << 20)
        let steps = Array(repeating: StubResponse.Step.send(chunk), count: 5)
        let server = StubServer(StubResponse(headers: ["Content-Type": "application/json"], steps: steps))
        await #expect(throws: TranslationFailure.invalidResponse) {
            try await LLMServiceProbe.models(
                for: LLMEndpoint(baseURL: server.baseURL, apiKey: nil), session: server.makeSession())
        }
    }

    @Test("模型列表失败：状态码映射、格式不对、超时")
    func modelListFailures() async {
        let unauthorized = StubServer(StubResponse(status: 401))
        await #expect(throws: TranslationFailure.unauthorized) {
            try await LLMServiceProbe.models(
                for: LLMEndpoint(baseURL: unauthorized.baseURL, apiKey: "k"), session: unauthorized.makeSession())
        }
        let garbage = StubServer(json(["models": ["x"]]))
        await #expect(throws: TranslationFailure.invalidResponse) {
            try await LLMServiceProbe.models(
                for: LLMEndpoint(baseURL: garbage.baseURL, apiKey: nil), session: garbage.makeSession())
        }
        // 响应头一直不来：结果只能来自 200 ms 的超时（原先 5 s 后响应头会到，线程池繁忙时与超时谁先到没有保证）
        let slow = StubServer(.noResponse)
        await #expect(throws: TranslationFailure.network) {
            try await LLMServiceProbe.models(
                for: LLMEndpoint(baseURL: slow.baseURL, apiKey: nil), session: slow.makeSession(),
                timeout: .milliseconds(200))
        }
    }

    @Test("测试连接：发送一块 Hello，返回译文与耗时")
    func connectionTest() async throws {
        let server = StubServer(.sse(SSE.stream(#"{"id":0,"text":"你好"}"#)))
        let engine = LLMTranslationEngine(
            configuration: LLMConfiguration(
                preset: .standard, endpoint: LLMEndpoint(baseURL: server.baseURL, apiKey: "k"), model: "m"),
            session: server.makeSession())
        let result = try await LLMServiceProbe.testConnection(engine, target: "zh-Hans")
        #expect(result.translation == "你好")
        #expect(result.duration >= .zero)
        let body = try #require(server.requests.first?.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: String]])
        #expect(messages.last?["content"] == #"{"id":0,"text":"Hello"}"#)
        #expect(messages.first?["content"]?.contains("zh-Hans") == true)
    }

    @Test("测试连接失败时抛出映射后的错误")
    func connectionTestFailure() async {
        let server = StubServer(StubResponse(status: 403))
        let engine = LLMTranslationEngine(
            configuration: LLMConfiguration(
                preset: .standard, endpoint: LLMEndpoint(baseURL: server.baseURL, apiKey: "k"), model: "m"),
            session: server.makeSession())
        await #expect(throws: TranslationFailure.unauthorized) {
            try await LLMServiceProbe.testConnection(engine, target: "ja")
        }
    }

    @Test("桩自检：不加重定向守卫时，URLSession 会跟随跨主机重定向（证明守卫确实生效）")
    func stubFollowsRedirectsWithoutGuard() async throws {
        let elsewhere = StubServer(json(["data": []]))
        let server = StubServer(StubResponse(redirect: elsewhere.baseURL.appending(path: "models")))
        let (_, response) = try await server.makeSession().data(from: server.baseURL.appending(path: "models"))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(elsewhere.requests.count == 1)

        await #expect(throws: TranslationFailure.server(status: 307)) {
            try await LLMServiceProbe.models(
                for: LLMEndpoint(baseURL: server.baseURL, apiKey: "k"), session: server.makeSession())
        }
        #expect(elsewhere.requests.count == 1)
    }

    @Test("默认会话：临时、不缓存、不存 Cookie")
    func defaultSession() {
        let configuration = LLMHTTP.makeSession().configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
}
