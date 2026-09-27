import CubbyCore
import Foundation
import Security
import os

/// 大模型 API Key 的存取（按服务预设分别保存，并与保存时的接入地址绑定，见 LLMStoredKey）。
/// 密钥只在这里读写：不进 UserDefaults、历史文件与日志。读取结果（包括失败）在本次运行内缓存
@MainActor
protocol TranslationKeyStoring: AnyObject {
    /// 缓存的读取结果；首次访问时读取
    func lookup(_ presetID: String) -> LLMStoredKeyLookup
    /// 用户在设置中点「重试」：丢弃缓存（包括缓存的失败）重新读取
    func retry(_ presetID: String) -> LLMStoredKeyLookup
    func save(_ key: String, for presetID: String, boundTo baseURL: URL) throws
    func remove(_ presetID: String) throws
}

/// 缓存与绑定规则由 Core 的 LLMKeyStore 实现，子类只决定后端
@MainActor
class TranslationKeyStore: TranslationKeyStoring {
    private let store: LLMKeyStore

    init(backend: any LLMSecretBackend) {
        store = LLMKeyStore(backend: backend)
    }

    func lookup(_ presetID: String) -> LLMStoredKeyLookup {
        store.lookup(presetID)
    }

    func retry(_ presetID: String) -> LLMStoredKeyLookup {
        store.retry(presetID)
    }

    func save(_ key: String, for presetID: String, boundTo baseURL: URL) throws {
        try store.save(key, for: presetID, boundTo: baseURL)
    }

    func remove(_ presetID: String) throws {
        try store.remove(presetID)
    }
}

/// 正式使用：登录钥匙串
final class KeychainTranslationKeyStore: TranslationKeyStore {
    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "io.github.no1coder.Cubby") {
        super.init(backend: KeychainSecretBackend(service: bundleIdentifier + ".translation"))
    }
}

/// 只在内存中：调试走查使用，从不接触钥匙串
final class InMemoryTranslationKeyStore: TranslationKeyStore {
    init(keys: [String: LLMStoredKey] = [:]) {
        let backend = InMemoryLLMSecretBackend(items: keys.mapValues { $0.encoded() })
        #if DEBUG
        // 走查「钥匙串无法访问」的界面：--fake-keychain-failure
        if DebugTranslationFixtures.simulatesKeychainFailure {
            super.init(backend: DebugTranslationFixtures.UnavailableBackend())
            return
        }
        #endif
        super.init(backend: backend)
    }
}

/// 钥匙串操作失败（只带状态码，不带任何内容）
struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// 登录钥匙串中的通用密码条目：service = `<bundle id>.translation`，account = 预设 id，
/// 数据为 LLMStoredKey 的 JSON（密钥 + 绑定的地址来源）。
///
/// 新建条目时可访问性设为 `WhenUnlockedThisDeviceOnly`（设计文档 §5）。Cubby 没有钥匙串访问组权限，
/// 使用的是 macOS 基于文件的登录钥匙串：该属性会被接受但不强制，条目的访问控制由钥匙串 ACL
/// 保证（只有创建它的 Cubby 可以静默读取，其他应用读取需要用户在系统弹窗中允许）
@MainActor
final class KeychainSecretBackend: LLMSecretBackend {
    private let service: String
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Translation")

    init(service: String) {
        self.service = service
    }

    func read(account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw failure(status, operation: "read")
        }
    }

    /// 已有条目时只更新数据，否则新建
    func write(_ data: Data, account: String) throws {
        let status = SecItemUpdate(
            baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrLabel as String] = "Cubby translation API key (\(account))"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added, operation: "add") }
        default:
            throw failure(status, operation: "update")
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status, operation: "delete")
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 只记录操作名与状态码
    private func failure(_ status: OSStatus, operation: String) -> KeychainError {
        Self.logger.error("Keychain \(operation, privacy: .public) failed with status \(status)")
        return KeychainError(status: status)
    }
}
