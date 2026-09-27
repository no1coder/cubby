import Foundation

/// 密钥的持久化后端（App 层用登录钥匙串实现；测试与调试走查用内存）。account 为服务预设 id
@MainActor
public protocol LLMSecretBackend: AnyObject {
    /// 没有条目时返回 nil；无法访问（用户拒绝、钥匙串已锁定）时抛出
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String) throws
}

/// 按预设保存 API Key，并在本次运行内缓存读取结果（docs/TRANSLATION-DESIGN.md §5）。
///
/// 读取失败同样缓存：每次翻译都要取密钥，若每次都重新访问钥匙串，用户会被反复询问，
/// 容易被迫点「始终允许」。只有用户在设置中明确点「重试」时才重新读取
@MainActor
public final class LLMKeyStore {
    private let backend: any LLMSecretBackend
    private var cache: [String: LLMStoredKeyLookup] = [:]

    public init(backend: any LLMSecretBackend) {
        self.backend = backend
    }

    /// 缓存的读取结果（首次访问时读取后端）
    public func lookup(_ presetID: String) -> LLMStoredKeyLookup {
        if let cached = cache[presetID] { return cached }
        let result = read(presetID)
        cache[presetID] = result
        return result
    }

    /// 用户明确要求重试：丢弃缓存重新读取
    public func retry(_ presetID: String) -> LLMStoredKeyLookup {
        cache[presetID] = nil
        return lookup(presetID)
    }

    /// 保存密钥，绑定到当前接入地址的来源
    public func save(_ key: String, for presetID: String, boundTo baseURL: URL) throws {
        let stored = LLMStoredKey(key: key, boundTo: baseURL)
        try backend.write(stored.encoded(), account: presetID)
        cache[presetID] = .found(stored)
    }

    public func remove(_ presetID: String) throws {
        try backend.delete(account: presetID)
        cache[presetID] = LLMStoredKeyLookup.none
    }

    private func read(_ presetID: String) -> LLMStoredKeyLookup {
        do {
            guard let data = try backend.read(account: presetID), let stored = LLMStoredKey.decode(data) else {
                return .none
            }
            return .found(stored)
        } catch {
            return .inaccessible
        }
    }
}

/// 只在内存中的后端：测试与调试走查使用，从不接触钥匙串
@MainActor
public final class InMemoryLLMSecretBackend: LLMSecretBackend {
    private var items: [String: Data]

    public init(items: [String: Data] = [:]) {
        self.items = items
    }

    public func read(account: String) throws -> Data? {
        items[account]
    }

    public func write(_ data: Data, account: String) throws {
        items[account] = data
    }

    public func delete(account: String) throws {
        items[account] = nil
    }
}
