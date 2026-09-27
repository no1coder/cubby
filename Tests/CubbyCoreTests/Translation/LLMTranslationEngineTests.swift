import Foundation
import Testing
@testable import CubbyCore

@Suite("大模型翻译引擎（URLProtocol 桩，不联网）")
struct LLMTranslationEngineTests {
    private let fastTimeouts = LLMTimeouts(firstByte: .seconds(5), total: .seconds(10))
    private let languages = TranslationLanguages(source: "en", target: "zh-Hans")

    private func engine(
        _ server: StubServer, key: String? = "sk-test-not-a-real-key", timeouts: LLMTimeouts? = nil
    ) -> LLMTranslationEngine {
        let configuration = LLMConfiguration(
            preset: LLMProviderPreset.standard, endpoint: LLMEndpoint(baseURL: server.baseURL, apiKey: key),
            model: "test-model")
        return LLMTranslationEngine(
            configuration: configuration, session: server.makeSession(), timeouts: timeouts ?? fastTimeouts)
    }

    private func translate(
        _ server: StubServer, _ texts: [String], key: String? = "sk-test-not-a-real-key", timeouts: LLMTimeouts? = nil
    ) async -> ([BlockTranslation], (any Error)?) {
        await collect(engine(server, key: key, timeouts: timeouts).translate(makeBlocks(texts), languages: languages))
    }

    @Test("逐块流式返回译文；请求为 POST chat/completions，带 Bearer 密钥与 JSON Lines")
    func streamsTranslations() async throws {
        let output = #"{"id":0,"text":"设置"}"# + "\n" + #"{"id":1,"text":"保存更改"}"# + "\n"
        let server = StubServer(.sse(SSE.stream(output, pieces: 5)))
        let (translations, error) = await translate(server, ["Settings", "Save changes"])

        #expect(error == nil)
        #expect(translations == [BlockTranslation(blockID: 0, text: "设置"), BlockTranslation(blockID: 1, text: "保存更改")])
        let recorded = try #require(server.requests.first)
        #expect(recorded.request.httpMethod == "POST")
        #expect(recorded.request.url == server.baseURL.appending(path: "chat/completions"))
        #expect(recorded.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-not-a-real-key")
        #expect(recorded.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(recorded.request.value(forHTTPHeaderField: "Accept") == "text/event-stream")

        let body = try #require(try JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        #expect(body["model"] as? String == "test-model")
        #expect(body["stream"] as? Bool == true)
        #expect(body["temperature"] == nil)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(messages[1]["content"] == #"{"id":0,"text":"Settings"}"# + "\n" + #"{"id":1,"text":"Save changes"}"#)
    }

    @Test("没有密钥时不带 Authorization")
    func omitsAuthorizationWithoutKey() async throws {
        let server = StubServer(.sse(SSE.stream(#"{"id":0,"text":"你好"}"#)))
        let (translations, error) = await translate(server, ["Hello"], key: nil)
        #expect(error == nil)
        #expect(translations.count == 1)
        #expect(server.requests.first?.request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("SSE 按字节任意切分、CRLF、注释行与角色块都能正确处理")
    func toleratesFragmentedSSE() async {
        let events = [
            ": OPENROUTER PROCESSING\r\n\r\n",
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"# + "\r\n\r\n",
            SSE.content(#"{"id":0,"te"#).replacingOccurrences(of: "\n", with: "\r\n"),
            SSE.content(#"xt":"一"}"# + "\n" + #"{"id":1,"#),
            SSE.content(#""text":"二"}"#),
            SSE.done,
        ].joined()
        let bytes = Array(events.utf8)
        let steps = stride(from: 0, to: bytes.count, by: 7).map {
            StubResponse.Step.send(Data(bytes[$0..<min($0 + 7, bytes.count)]))
        }
        let server = StubServer(StubResponse(steps: steps))
        let (translations, error) = await translate(server, ["One", "Two"])
        #expect(error == nil)
        #expect(translations.map(\.text) == ["一", "二"])
    }

    @Test("流以没有换行的 data 行结束（没有 [DONE]）也能处理")
    func lastEventWithoutNewline() async {
        let last = String(SSE.content(#"{"id":0,"text":"一"}"#).dropLast(2))
        let server = StubServer(.sse([last]))
        let (translations, error) = await translate(server, ["One"])
        #expect(error == nil)
        #expect(translations.map(\.text) == ["一"])
    }

    @Test("代码块围栏、前后杂讯、重复与未知 id 被容忍")
    func toleratesNoise() async {
        let output = """
            Sure! Here is the translation:
            ```json
            {"id":0,"text":"文件"}
            {"id":0,"text":"重复"}
            {"id":7,"text":"未知"}
            {"id":1,"text":"编辑"}
            ```
            Hope this helps.
            """
        let server = StubServer(.sse(SSE.stream(output, pieces: 4)))
        let (translations, error) = await translate(server, ["File", "Edit"])
        #expect(error == nil)
        #expect(translations == [BlockTranslation(blockID: 0, text: "文件"), BlockTranslation(blockID: 1, text: "编辑")])
    }

    @Test("服务忽略 stream 返回普通 JSON 时也能解析")
    func acceptsNonStreamingResponse() async {
        let content = #"{"id":0,"text":"你好"}"#
        let json = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let server = StubServer(StubResponse(headers: ["Content-Type": "application/json"], steps: [.send(json)]))
        let (translations, error) = await translate(server, ["Hello"])
        #expect(error == nil)
        #expect(translations == [BlockTranslation(blockID: 0, text: "你好")])
    }

    @Test("超大的非流式响应视为无法识别")
    func oversizedJSONResponse() async {
        let chunk = Data(repeating: UInt8(ascii: " "), count: 1 << 20)
        let steps = Array(repeating: StubResponse.Step.send(chunk), count: 5)
        let server = StubServer(StubResponse(headers: ["Content-Type": "application/json"], steps: steps))
        let (_, error) = await translate(server, ["Hello"])
        #expect(error as? TranslationFailure == .invalidResponse)
    }

    @Test(
        "HTTP 状态码映射",
        arguments: [
            (401, TranslationFailure.unauthorized), (403, .unauthorized), (402, .rateLimited), (429, .rateLimited),
            (500, .server(status: 500)), (503, .server(status: 503)), (404, .server(status: 404)),
        ])
    func mapsStatus(_ status: Int, _ expected: TranslationFailure) async {
        let server = StubServer(StubResponse(status: status, headers: ["Content-Type": "application/json"]))
        let (translations, error) = await translate(server, ["Hello"])
        #expect(translations.isEmpty)
        #expect(error as? TranslationFailure == expected)
    }

    @Test("离线等网络错误映射为 network", arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost])
    func mapsNetworkErrors(_ code: URLError.Code) async {
        let server = StubServer(StubResponse(failure: URLError(code)))
        let (_, error) = await translate(server, ["Hello"])
        #expect(error as? TranslationFailure == .network)
    }

    @Test("首字节超时映射为 network，并取消请求")
    func firstByteTimeout() async {
        let server = StubServer(StubResponse(headerDelay: .seconds(5), steps: []))
        let timeouts = LLMTimeouts(firstByte: .milliseconds(200), total: .seconds(5))
        let started = ContinuousClock.now
        let (_, error) = await translate(server, ["Hello"], timeouts: timeouts)
        #expect(error as? TranslationFailure == .network)
        #expect(ContinuousClock.now - started < .seconds(3))
    }

    @Test("整体超时映射为 network，已到达的译文保留")
    func totalTimeout() async {
        let server = StubServer(
            StubResponse(steps: [.send(Data(SSE.content(#"{"id":0,"text":"一"}"# + "\n").utf8))], hangs: true))
        let timeouts = LLMTimeouts(firstByte: .seconds(2), total: .milliseconds(400))
        let (translations, error) = await translate(server, ["One", "Two"], timeouts: timeouts)
        #expect(translations == [BlockTranslation(blockID: 0, text: "一")])
        #expect(error as? TranslationFailure == .network)
    }

    @Test("取消消费方即取消请求")
    func cancellationStopsRequest() async throws {
        let server = StubServer(StubResponse(steps: [.send(Data(": keep-alive\n\n".utf8))], hangs: true))
        let stream = engine(server).translate(makeBlocks(["Hello"]), languages: languages)
        let consumer = Task { await collect(stream) }
        try await Task.sleep(for: .milliseconds(200))
        consumer.cancel()
        _ = await consumer.value
        for _ in 0..<50 where server.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(server.stopCount >= 1)
    }

    @Test("拒绝跨主机重定向：不向其他主机发请求，以 307 结束")
    func refusesCrossHostRedirect() async {
        let elsewhere = StubServer(.sse(SSE.stream(#"{"id":0,"text":"不应到达"}"#)))
        let server = StubServer(StubResponse(redirect: elsewhere.baseURL.appending(path: "chat/completions")))
        let (translations, error) = await translate(server, ["Hello"])
        #expect(translations.isEmpty)
        #expect(error as? TranslationFailure == .server(status: 307))
        #expect(elsewhere.requests.isEmpty)
    }

    @Test("同一主机内的重定向照常跟随")
    func followsSameHostRedirect() async throws {
        let server = StubServer { request, _ in
            request.url?.path == "/v1/chat/completions"
                ? StubResponse(redirect: URL(string: "https://\(request.url!.host()!)/v2/chat/completions")!)
                : .sse(SSE.stream(#"{"id":0,"text":"你好"}"#))
        }
        let (translations, error) = await translate(server, ["Hello"])
        #expect(error == nil)
        #expect(translations.map(\.text) == ["你好"])
        #expect(server.requests.last?.request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test("一块都解析不出来时为 invalidResponse")
    func invalidResponseWhenNothingParsed() async {
        let server = StubServer(.sse(SSE.stream("I cannot translate this.")))
        let (translations, error) = await translate(server, ["Hello"])
        #expect(translations.isEmpty)
        #expect(error as? TranslationFailure == .invalidResponse)
    }

    @Test("流中的错误事件结束翻译，已到达的译文保留")
    func inStreamError() async {
        let events = [
            SSE.content(#"{"id":0,"text":"一"}"# + "\n"),
            #"data: {"error":{"code":429,"message":"slow down"}}"# + "\n\n",
        ]
        let server = StubServer(.sse(events))
        let (translations, error) = await translate(server, ["One", "Two"])
        #expect(translations.map(\.blockID) == [0])
        #expect(error as? TranslationFailure == .rateLimited)
    }

    @Test("超过 6000 字符分批顺序请求，下一批的 system 带上一批最后 3 块作为上下文")
    func batchesWithContext() async throws {
        let texts = (0..<5).map { index in "Block \(index) " + String(repeating: "x", count: 1990) }
        let server = StubServer { _, body in
            let ids = Self.requestedIDs(body)
            return .sse(SSE.stream(ids.map { #"{"id":\#($0),"text":"译\#($0)"}"# }.joined(separator: "\n")))
        }
        let (translations, error) = await translate(server, texts)
        #expect(error == nil)
        #expect(translations.map(\.blockID) == [0, 1, 2, 3, 4])
        #expect(server.requests.count == 2)

        let second = try #require(server.requests.last)
        let messages = try Self.messages(second.body)
        #expect(Self.requestedIDs(second.body) == [3, 4])
        #expect(messages[0].contains("Block 0") && messages[0].contains("Block 1") && messages[0].contains("Block 2"))
        let first = try Self.messages(try #require(server.requests.first).body)
        #expect(!first[0].contains("For context only"))
    }

    @Test("后一批失败时前一批的译文保留")
    func laterBatchFailureKeepsEarlierResults() async {
        let texts = ["A " + String(repeating: "a", count: 5000), "B " + String(repeating: "b", count: 5000)]
        let server = StubServer { _, body in
            Self.requestedIDs(body) == [0] ? .sse(SSE.stream(#"{"id":0,"text":"甲"}"#)) : StubResponse(status: 500)
        }
        let (translations, error) = await translate(server, texts)
        #expect(translations == [BlockTranslation(blockID: 0, text: "甲")])
        #expect(error as? TranslationFailure == .server(status: 500))
    }

    @Test("引擎名含模型；本机地址不算离开这台 Mac")
    func displayNameAndLocality() throws {
        let server = StubServer(.sse([]))
        let remote = engine(server)
        #expect(remote.displayName == "DeepSeek · test-model")
        #expect(remote.sendsTextOffDevice)

        let local = LLMTranslationEngine(
            configuration: try LLMConfiguration.make(
                preset: try #require(LLMProviderPreset.preset(id: "ollama")), baseURL: "http://localhost:11434/v1",
                model: "qwen3", key: .none
            ).get(),
            session: server.makeSession())
        #expect(!local.sendsTextOffDevice)
        #expect(local.displayName == "Ollama · qwen3")
    }

    // MARK: - 解析请求体

    private static func messages(_ body: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = object?["messages"] as? [[String: String]] ?? []
        return messages.compactMap { $0["content"] }
    }

    private static func requestedIDs(_ body: Data) -> [Int] {
        guard let user = try? messages(body).last else { return [] }
        return user.split(separator: "\n").compactMap { line in
            let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return object?["id"] as? Int
        }
    }
}
