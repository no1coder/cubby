import Foundation
import os
@testable import CubbyCore

/// 桩服务器的一次响应（按步骤交付，模拟分片到达）
struct StubResponse: Sendable {
    enum Step: Sendable {
        case send(Data)
        case wait(Duration)
    }

    var status = 200
    /// 响应头之前的等待（模拟首字节迟迟不来）
    var headerDelay: Duration = .zero
    var headers = ["Content-Type": "text/event-stream"]
    var steps: [Step] = []
    /// 交付完步骤后以该错误结束（nil 则正常结束）
    var failure: URLError?
    /// 交付完步骤后不结束（等待取消或超时）
    var hangs = false
    /// 不响应，而是重定向到该地址（307）
    var redirect: URL?

    static func sse(_ events: [String], status: Int = 200) -> StubResponse {
        StubResponse(status: status, steps: events.map { .send(Data($0.utf8)) })
    }
}

/// 一个测试专用的桩服务器：以唯一主机名注册，不联网。记录收到的请求与被停止的次数
final class StubServer: Sendable {
    struct Recorded: Sendable {
        let request: URLRequest
        let body: Data
    }

    let host: String
    private let handler: @Sendable (URLRequest, Data) -> StubResponse
    private let state = OSAllocatedUnfairLock(initialState: (requests: [Recorded](), stops: 0))

    init(
        host: String = "stub-\(UUID().uuidString.lowercased()).test",
        handler: @escaping @Sendable (URLRequest, Data) -> StubResponse
    ) {
        self.host = host
        self.handler = handler
        StubURLProtocol.register(self)
    }

    convenience init(_ response: StubResponse) {
        self.init { _, _ in response }
    }

    var baseURL: URL {
        URL(string: "https://\(host)/v1")!
    }

    var requests: [Recorded] {
        state.withLock { $0.requests }
    }

    var stopCount: Int {
        state.withLock { $0.stops }
    }

    /// 使用桩协议的临时会话
    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    fileprivate func respond(to request: URLRequest, body: Data) -> StubResponse {
        state.withLock { $0.requests.append(Recorded(request: request, body: body)) }
        return handler(request, body)
    }

    fileprivate func recordStop() {
        state.withLock { $0.stops += 1 }
    }
}

/// 按主机名把请求交给对应的 StubServer
final class StubURLProtocol: URLProtocol {
    private static let servers = OSAllocatedUnfairLock(initialState: [String: StubServer]())
    private let isStopped = OSAllocatedUnfairLock(initialState: false)
    private var delivery: Task<Void, Never>?

    static func register(_ server: StubServer) {
        servers.withLock { $0[server.host] = server }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
            let server = Self.servers.withLock({ $0[host] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = server.respond(to: request, body: Self.body(of: request))
        if let redirect = response.redirect {
            deliverRedirect(to: redirect, from: url)
            return
        }
        let http = HTTPURLResponse(
            url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        // URLProtocol 不是 Sendable：用盒子带进交付任务（桩只在测试中使用，交付期间不会被并发修改）
        let box = UncheckedBox(value: self)
        delivery = Task { await box.value.deliver(response, head: http) }
    }

    private func deliver(_ response: StubResponse, head: HTTPURLResponse) async {
        if response.headerDelay > .zero { try? await Task.sleep(for: response.headerDelay) }
        guard !isStopped.withLock({ $0 }) else { return }
        client?.urlProtocol(self, didReceive: head, cacheStoragePolicy: .notAllowed)
        for step in response.steps {
            switch step {
            case .send(let data): client?.urlProtocol(self, didLoad: data)
            case .wait(let duration): try? await Task.sleep(for: duration)
            }
            if isStopped.withLock({ $0 }) { return }
        }
        guard !response.hangs else { return }
        if let failure = response.failure {
            client?.urlProtocol(self, didFailWithError: failure)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        isStopped.withLock { $0 = true }
        delivery?.cancel()
        if let host = request.url?.host(), let server = Self.servers.withLock({ $0[host] }) {
            server.recordStop()
        }
    }

    private func deliverRedirect(to destination: URL, from url: URL) {
        let response = HTTPURLResponse(
            url: url, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
        var redirected = request
        redirected.url = destination
        client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        // 重定向被拒绝时，任务以 307 响应结束
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLProtocol 收到的请求体在 httpBodyStream 里
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

/// 构造 SSE 事件文本
enum SSE {
    static func content(_ text: String) -> String {
        let chunk: [String: Any] = ["choices": [["index": 0, "delta": ["content": text]]]]
        let data = try! JSONSerialization.data(withJSONObject: chunk)
        return "data: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    static let done = "data: [DONE]\n\n"

    /// 把 JSON Lines 形式的完整输出拆成若干增量事件
    static func stream(_ output: String, pieces: Int = 3) -> [String] {
        let characters = Array(output)
        let size = max(1, characters.count / pieces)
        return stride(from: 0, to: characters.count, by: size).map {
            content(String(characters[$0..<min($0 + size, characters.count)]))
        } + [done]
    }
}

/// 收集翻译流：译文与结束时的错误
func collect(_ stream: AsyncThrowingStream<BlockTranslation, any Error>) async -> ([BlockTranslation], (any Error)?) {
    var results: [BlockTranslation] = []
    do {
        for try await item in stream { results.append(item) }
        return (results, nil)
    } catch {
        return (results, error)
    }
}

/// 构造测试块
func makeBlocks(_ texts: [String]) -> [TextBlock] {
    texts.enumerated().map { TextBlock(id: $0.offset, lines: [], alignment: .leading, text: $0.element) }
}
