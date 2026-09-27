import Foundation

/// 大模型服务的 HTTP 细节：会话配置、请求构造、重定向策略与状态码检查（翻译、模型列表共用）
public enum LLMHTTP {
    /// 非流式响应体（模型列表、忽略 stream 的翻译响应）的上限，超过即视为无法识别，防止异常响应占满内存
    static let maxBodyBytes = 4 << 20

    /// 临时会话：不写缓存、不存 Cookie、不带凭据存储。超时由调用方按阶段控制，这里只设兜底值
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }

    /// 构造请求：密钥存在时带 `Authorization: Bearer`，否则不带（Ollama 等本机服务）
    static func request(
        _ endpoint: LLMEndpoint, path: String, method: String, accept: String, body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: LLMBaseURL.endpoint(endpoint.baseURL, path: path))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = endpoint.apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// 发起流式请求，在 firstByte 内等到响应头；非 2xx 映射为 TranslationFailure
    static func openStream(
        _ request: URLRequest, session: URLSession, firstByte: Duration
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let redirectGuard = RedirectGuard(original: request.url)
        let (bytes, response) = try await CaptureDeadline.run(firstByte) {
            try await session.bytes(for: request, delegate: redirectGuard)
        }
        return (bytes, try checked(response))
    }

    /// 发起普通请求并读取完整响应体（模型列表）：整个过程限时，响应体限长
    static func load(_ request: URLRequest, session: URLSession, timeout: Duration) async throws -> Data {
        let redirectGuard = RedirectGuard(original: request.url)
        return try await CaptureDeadline.run(timeout) {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirectGuard)
            _ = try checked(response)
            return try await collect(bytes)
        }
    }

    /// 读取完整响应体，超过 maxBodyBytes 立即停止并视为无法识别
    static func collect(_ bytes: URLSession.AsyncBytes, limit: Int = maxBodyBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= limit else { throw TranslationFailure.invalidResponse }
        }
        return data
    }

    /// 响应是否为普通 JSON（服务忽略了 stream: true）
    static func isJSON(_ response: HTTPURLResponse) -> Bool {
        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return type.contains("application/json")
    }

    private static func checked(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw TranslationFailure.invalidResponse }
        if let failure = LLMFailureMapping.failure(forStatus: http.statusCode) { throw failure }
        return http
    }
}

/// 拒绝跨主机与降级的重定向（见 LLMBaseURL.allowsRedirect）：返回 nil 时任务以 3xx 响应结束，
/// Authorization 不会被转发到其他主机
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let original: URL?

    init(original: URL?) {
        self.original = original
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original, let destination = request.url,
            LLMBaseURL.allowsRedirect(from: original, to: destination)
        else { return nil }
        return request
    }
}
