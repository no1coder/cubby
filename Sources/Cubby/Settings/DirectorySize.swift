import Foundation

/// 统计目录占用的磁盘空间（在后台线程执行）
enum DirectorySize {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// 目录不存在时返回 0
    static func bytes(at url: URL) async -> Int64 {
        await Task.detached(priority: .utility) { compute(at: url) }.value
    }

    private static func compute(at url: URL) -> Int64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [],
                errorHandler: { _, _ in true }
            )
        else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
