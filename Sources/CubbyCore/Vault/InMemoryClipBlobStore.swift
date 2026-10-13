import Foundation
import os

/// 只存在于内存中的二进制内容存储：历史已锁定（E8 ①）或启动时密钥尚未就绪期间使用，什么都不写盘。
///
/// 文件名为 `mem-<种类>-<内容哈希>`：带连字符前缀，与加密存储的 64 位十六进制 HMAC 名永不相同，
/// 解锁时（ClipStore.unlock）据此认出哪些引用需要搬进加密存储并改名。
public final class InMemoryClipBlobStore: ClipBlobStoring, Sendable {
    static let namePrefix = "mem-"
    private static let separator = "-"

    private let files = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    public init() {}

    public var isPersistent: Bool { false }

    public func name(kind: ClipBlobKind, contentHash: String) -> String {
        Self.namePrefix + kind.rawValue + Self.separator + contentHash
    }

    /// 由本存储的文件名反推种类与内容哈希；不是本存储生成的名称时为 nil
    public static func parse(_ name: String) -> (kind: ClipBlobKind, contentHash: String)? {
        guard name.hasPrefix(namePrefix) else { return nil }
        let rest = name.dropFirst(namePrefix.count)
        // 种类本身可能含连字符（translated-image），按完整前缀匹配，取最长的一个
        let matches = ClipBlobKind.allCases.filter { rest.hasPrefix($0.rawValue + separator) }
        guard let kind = matches.max(by: { $0.rawValue.count < $1.rawValue.count }) else { return nil }
        let hash = rest.dropFirst(kind.rawValue.count + separator.count)
        return hash.isEmpty ? nil : (kind, String(hash))
    }

    public func write(_ data: Data, name: String) throws {
        guard BlobStore.isValidName(name) else { throw BlobStoreError.invalidName(name) }
        files.withLock { stored in
            if stored[name] == nil { stored[name] = data }
        }
    }

    public func data(_ name: String) throws -> Data {
        guard let data = files.withLock({ $0[name] }) else { throw CocoaError(.fileNoSuchFile) }
        return data
    }

    public func exists(_ name: String) -> Bool {
        files.withLock { $0[name] != nil }
    }

    @discardableResult
    public func remove(_ names: some Sequence<String>) -> [String] {
        let targets = Array(names)
        files.withLock { stored in
            for name in targets { stored[name] = nil }
        }
        return []
    }

    @discardableResult
    public func removeAll(except keep: Set<String>) throws -> [String] {
        files.withLock { stored in
            let orphans = stored.keys.filter { !keep.contains($0) }
            for name in orphans { stored[name] = nil }
            return orphans.sorted()
        }
    }

    /// 当前保存的全部文件名（测试与解锁时使用）
    public var names: Set<String> {
        files.withLock { Set($0.keys) }
    }
}
