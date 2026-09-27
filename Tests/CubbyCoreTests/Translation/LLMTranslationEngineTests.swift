import Foundation
import Testing
@testable import CubbyCore

@Suite("大模型翻译引擎（URLProtocol 桩，不联网）", .timeLimit(.minutes(1)))
struct LLMTranslationEngineTests {
    private let fastTimeouts = LLMTimeouts(firstByte: .seconds(5), total: .seconds(10))
    private let languages = TranslationLanguages(source: "en", target: "zh-Hans")

    /// timer 为 nil 时走默认的 GCD 计时；超时用例注入手动计时器，由测试决定超时何时触发
    private func engine(
        _ server: StubServer, key: String? = "sk-test-not-a-real-key", timer: DeadlineTimer? = nil
    ) -> LLMTranslationEngine {
        let configuration = LLMConfiguration(
            preset: LLMProviderPreset.standard, endpoint: LLMEndpoint(baseURL: server.baseURL, apiKey: key),
            model: "test-model")
        guard let timer else {
            return LLMTranslationEngine(
                configuration: configuration, session: server.makeSession(), timeouts: fastTimeouts)
        }
        return LLMTranslationEngine(
            configuration: configuration, session: server.makeSession(), timeouts: fastTimeouts, timer: timer)
    }

    private func translate(
        _ server: StubServer, _ texts: [String], key: String? = "sk-test-not-a-real-key", timer: DeadlineTimer? = nil
    ) async -> ([BlockTranslation], (any Error)?) {
        await collect(engine(server, key: key, timer: timer).translate(makeBlocks(texts), languages: languages))
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

    // 超时用例用手动计时器按顺序断言：原先用 200 ms / 400 ms 的真实超时加耗时上限，
    // CI 上协作线程池繁忙时，请求与译文晚好几秒才排上，耗时断言（实测 9.8 s）与「已到达」都会误报
    @Test("首字节超时映射为 network，并取消请求")
    func firstByteTimeout() async {
        let server = StubServer(.noResponse)
        let clock = ManualDeadlineTimer()
        let translation = Task { await translate(server, ["Hello"], timer: clock.timer) }
        // 请求已到达桩、首字节计时器已安排后，只触发首字节超时（整体超时始终不触发），结果只能来自首字节超时
        await waitUntil("请求已发出、首字节计时器已安排") {
            server.requests.count == 1 && clock.scheduledCount(fastTimeouts.firstByte) == 1
        }
        clock.fire(fastTimeouts.firstByte)
        let (translations, error) = await translation.value
        #expect(translations.isEmpty)
        #expect(error as? TranslationFailure == .network)
        await waitUntil("请求被取消") { server.stopCount >= 1 }
    }

    @Test("整体超时映射为 network，已到达的译文保留")
    func totalTimeout() async throws {
        // 第一块到达后流停住，直到请求被取消
        let server = StubServer(
            StubResponse(steps: [.send(Data(SSE.content(#"{"id":0,"text":"一"}"# + "\n").utf8))], hangs: true))
        let clock = ManualDeadlineTimer()
        var iterator = engine(server, timer: clock.timer)
            .translate(makeBlocks(["One", "Two"]), languages: languages)
            .makeAsyncIterator()
        // 先确定地收到第一块，再触发整体超时（计时器与请求并发安排，触发前确认它已登记）
        #expect(try await iterator.next() == BlockTranslation(blockID: 0, text: "一"))
        await waitUntil("整体计时器已安排") { clock.scheduledCount(fastTimeouts.total) == 1 }
        clock.fire(fastTimeouts.total)
        do {
            let next = try await iterator.next()
            Issue.record("整体超时后流应以错误结束，却收到 \(String(describing: next))")
        } catch {
            #expect(error as? TranslationFailure == .network)
        }
        await waitUntil("请求被取消") { server.stopCount >= 1 }
    }

    @Test("取消消费方即取消请求")
    func cancellationStopsRequest() async throws {
        let server = StubServer(StubResponse(steps: [.send(Data(": keep-alive\n\n".utf8))], hangs: true))
        let stream = engine(server).translate(makeBlocks(["Hello"]), languages: languages)
        let consumer = Task { await collect(stream) }
        // 等请求真正到达桩再取消（原先固定睡 200 ms，线程池繁忙时请求可能还没发出）
        await waitUntil("请求已发出") { server.requests.count == 1 }
        consumer.cancel()
        _ = await consumer.value
        await waitUntil("请求被取消") { server.stopCount >= 1 }
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
