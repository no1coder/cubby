import Foundation

/// 保存的 API Key：与保存时的接入地址来源（协议 + 主机 + 端口）绑定。
/// 地址换到别的主机后密钥视为不存在，绝不发往新主机（用户需为新地址重新填写）
public struct LLMStoredKey: Equatable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public let key: String
    /// 例如 https://api.deepseek.com、http://localhost:11434
    public let origin: String

    public init(key: String, boundTo baseURL: URL) {
        self.key = key
        origin = LLMBaseURL.origin(baseURL)
    }

    /// 当前地址与保存时是否为同一来源（路径可以不同）
    public func matches(_ baseURL: URL) -> Bool {
        LLMBaseURL.origin(baseURL) == origin
    }

    /// 保存时的主机（界面提示用）
    public var host: String {
        boundURL.map(LLMBaseURL.displayHost) ?? origin
    }

    var boundURL: URL? {
        URL(string: origin)
    }

    /// 钥匙串中保存的数据（JSON）
    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// 解码；旧格式、损坏或字段为空时返回 nil
    public static func decode(_ data: Data) -> LLMStoredKey? {
        guard let stored = try? JSONDecoder().decode(LLMStoredKey.self, from: data),
            !stored.key.isEmpty, !stored.origin.isEmpty
        else { return nil }
        return stored
    }

    // 打印、日志与断言失败信息中不出现密钥
    public var description: String {
        "LLMStoredKey(origin: \(origin), key: redacted)"
    }

    public var debugDescription: String {
        description
    }
}

/// 读取钥匙串的结果
public enum LLMStoredKeyLookup: Equatable, Sendable {
    /// 没有保存（或数据无法识别）
    case none
    case found(LLMStoredKey)
    /// 读取失败：用户拒绝访问、钥匙串已锁定等
    case inaccessible
}

/// 针对当前接入地址的密钥状态
public enum LLMKeyState: Equatable, Sendable {
    case missing
    case available(String)
    /// 保存的密钥属于另一个主机（关联值为那个主机），不能使用
    case savedForOtherHost(String)
    case inaccessible

    /// baseURL 为 nil（地址无效）时，已保存的密钥一律不可用
    public init(_ lookup: LLMStoredKeyLookup, baseURL: URL?) {
        switch lookup {
        case .none:
            self = .missing
        case .inaccessible:
            self = .inaccessible
        case .found(let stored):
            if let baseURL, stored.matches(baseURL) {
                self = .available(stored.key)
            } else {
                self = .savedForOtherHost(stored.host)
            }
        }
    }

    /// 可以随请求发送的密钥：只有与当前地址匹配时才有
    public var usableKey: String? {
        guard case .available(let key) = self else { return nil }
        return key
    }
}
