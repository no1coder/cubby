import Foundation
import Testing
@testable import CubbyCore

/// 可注入失败、记录读取次数的后端
@MainActor
private final class RecordingBackend: LLMSecretBackend {
    var items: [String: Data] = [:]
    var readError: (any Error)?
    var writeError: (any Error)?
    private(set) var reads = 0

    func read(account: String) throws -> Data? {
        reads += 1
        if let readError { throw readError }
        return items[account]
    }

    func write(_ data: Data, account: String) throws {
        if let writeError { throw writeError }
        items[account] = data
    }

    func delete(account: String) throws {
        items[account] = nil
    }
}

private struct BackendFailure: Error {}

private func url(_ string: String) -> URL {
    URL(string: string)!
}

@Suite("API Key 与接入地址绑定")
struct LLMStoredKeyTests {
    @Test(
        "来源：协议 + 主机 + 非默认端口；主机不区分大小写，路径不参与",
        arguments: [
            ("https://API.DeepSeek.com/v1", "https://api.deepseek.com"),
            ("https://api.deepseek.com:443", "https://api.deepseek.com"),
            ("https://example.com:8443/v1", "https://example.com:8443"),
            ("http://localhost:11434/v1", "http://localhost:11434"),
            ("http://127.0.0.1/v1", "http://127.0.0.1"),
            ("http://[::1]:11434/v1", "http://[::1]:11434"),
        ])
    func origin(_ input: String, _ expected: String) {
        #expect(LLMBaseURL.origin(url(input)) == expected)
    }

    @Test("编码后可解码回来；损坏或旧格式的数据无法解码")
    func codable() throws {
        let stored = LLMStoredKey(key: "sk-test-123456", boundTo: url("https://api.deepseek.com"))
        #expect(LLMStoredKey.decode(stored.encoded()) == stored)
        #expect(LLMStoredKey.decode(Data("sk-plain-old-key".utf8)) == nil)
        #expect(LLMStoredKey.decode(Data(#"{"key":"","origin":"https://a.com"}"#.utf8)) == nil)
        #expect(LLMStoredKey.decode(Data(#"{"key":"k"}"#.utf8)) == nil)
    }

    @Test("同一来源（路径可不同）才匹配；显示保存时的主机")
    func matches() {
        let stored = LLMStoredKey(key: "k", boundTo: url("https://api.moonshot.cn/v1"))
        #expect(stored.matches(url("https://api.moonshot.cn/v2")))
        #expect(!stored.matches(url("https://api.moonshot.ai/v1")))
        #expect(!stored.matches(url("http://api.moonshot.cn/v1")))
        #expect(stored.host == "api.moonshot.cn")
    }

    @Test("打印时不出现密钥")
    func redacted() {
        let stored = LLMStoredKey(key: "sk-secret-value", boundTo: url("https://a.com"))
        #expect(!String(describing: stored).contains("sk-secret-value"))
        #expect(!String(reflecting: stored).contains("sk-secret-value"))
        #expect(!String(describing: LLMStoredKeyLookup.found(stored)).contains("sk-secret-value"))
    }

    @Test("密钥状态：可用、缺失、属于其他主机、无法访问")
    func states() {
        let deepseek = url("https://api.deepseek.com")
        let stored = LLMStoredKey(key: "sk-1", boundTo: deepseek)
        #expect(LLMKeyState(.found(stored), baseURL: deepseek) == .available("sk-1"))
        #expect(LLMKeyState(.none, baseURL: deepseek) == .missing)
        #expect(LLMKeyState(.inaccessible, baseURL: deepseek) == .inaccessible)
        #expect(
            LLMKeyState(.found(stored), baseURL: url("https://proxy.example.com/v1"))
                == .savedForOtherHost("api.deepseek.com"))
        #expect(LLMKeyState(.found(stored), baseURL: nil) == .savedForOtherHost("api.deepseek.com"))
        #expect(LLMKeyState(.none, baseURL: nil) == .missing)
    }

    @Test("只有与当前地址匹配的密钥才可发送")
    func usableKey() {
        let stored = LLMStoredKey(key: "sk-1", boundTo: url("https://dashscope.aliyuncs.com/compatible-mode/v1"))
        let international = url("https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
        #expect(LLMKeyState(.found(stored), baseURL: international).usableKey == nil)
        #expect(LLMKeyState(.inaccessible, baseURL: international).usableKey == nil)
        #expect(LLMKeyState(.found(stored), baseURL: stored.boundURL).usableKey == "sk-1")
    }
}

@Suite("密钥存储：缓存与失败")
@MainActor
struct LLMKeyStoreTests {
    private let deepseek = url("https://api.deepseek.com")

    @Test("读取结果缓存：同一会话内只读一次后端")
    func cachesResult() throws {
        let backend = RecordingBackend()
        backend.items["deepseek"] = LLMStoredKey(key: "sk-1", boundTo: deepseek).encoded()
        let store = LLMKeyStore(backend: backend)
        #expect(store.lookup("deepseek") == .found(LLMStoredKey(key: "sk-1", boundTo: deepseek)))
        _ = store.lookup("deepseek")
        #expect(backend.reads == 1)
        #expect(store.lookup("kimi") == .none)
        _ = store.lookup("kimi")
        #expect(backend.reads == 2)
    }

    @Test("读取失败也缓存，不会反复询问；只有明确重试才重新读取")
    func cachesFailureUntilRetry() {
        let backend = RecordingBackend()
        backend.readError = BackendFailure()
        let store = LLMKeyStore(backend: backend)
        #expect(store.lookup("deepseek") == .inaccessible)
        #expect(store.lookup("deepseek") == .inaccessible)
        #expect(backend.reads == 1)

        backend.readError = nil
        backend.items["deepseek"] = LLMStoredKey(key: "sk-1", boundTo: deepseek).encoded()
        #expect(store.lookup("deepseek") == .inaccessible)
        #expect(store.retry("deepseek") == .found(LLMStoredKey(key: "sk-1", boundTo: deepseek)))
        #expect(backend.reads == 2)
    }

    @Test("保存：写入绑定了来源的数据并更新缓存，无需再读")
    func save() throws {
        let backend = RecordingBackend()
        let store = LLMKeyStore(backend: backend)
        try store.save("sk-new", for: "deepseek", boundTo: deepseek)
        #expect(store.lookup("deepseek") == .found(LLMStoredKey(key: "sk-new", boundTo: deepseek)))
        #expect(backend.reads == 0)
        let data = try #require(backend.items["deepseek"])
        #expect(LLMStoredKey.decode(data)?.origin == "https://api.deepseek.com")
    }

    @Test("保存失败时抛出，缓存保持原状")
    func saveFailure() {
        let backend = RecordingBackend()
        backend.writeError = BackendFailure()
        let store = LLMKeyStore(backend: backend)
        #expect(throws: BackendFailure.self) { try store.save("sk", for: "deepseek", boundTo: deepseek) }
        #expect(store.lookup("deepseek") == .none)
    }

    @Test("移除后缓存为无密钥")
    func remove() throws {
        let backend = RecordingBackend()
        let store = LLMKeyStore(backend: backend)
        try store.save("sk", for: "deepseek", boundTo: deepseek)
        try store.remove("deepseek")
        #expect(store.lookup("deepseek") == .none)
        #expect(backend.items.isEmpty)
    }

    @Test("无法解码的旧数据视为没有密钥")
    func undecodableIsAbsent() {
        let backend = RecordingBackend()
        backend.items["deepseek"] = Data("sk-plain-old-key".utf8)
        #expect(LLMKeyStore(backend: backend).lookup("deepseek") == .none)
    }

    @Test("内存后端：按账户读写删除")
    func inMemoryBackend() throws {
        let backend = InMemoryLLMSecretBackend(items: ["a": Data("1".utf8)])
        #expect(try backend.read(account: "a") == Data("1".utf8))
        try backend.write(Data("2".utf8), account: "b")
        try backend.delete(account: "a")
        #expect(try backend.read(account: "a") == nil)
        #expect(try backend.read(account: "b") == Data("2".utf8))
    }
}
