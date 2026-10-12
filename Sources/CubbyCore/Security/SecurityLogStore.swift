import Foundation

/// 安全记录的读写（数据目录下的 security-log.json，原子写入）。读不到或损坏时为空记录
public struct SecurityLogStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("security-log.json")
    }

    public func load() -> SecurityLog {
        // 文件不存在（从未记录）或损坏时从空记录开始：记录只用于展示，丢失不影响守护本身
        guard let data = try? Data(contentsOf: url) else { return SecurityLog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SecurityLog.self, from: data)) ?? SecurityLog()
    }

    /// 原子写入；目录不存在时创建。与历史记录一样只允许本人读写（0700 / 0600）
    public func save(_ log: SecurityLog) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(log)
        try PrivateFiles.createDirectory(at: url.deletingLastPathComponent())
        try PrivateFiles.write(data, to: url)
    }
}
