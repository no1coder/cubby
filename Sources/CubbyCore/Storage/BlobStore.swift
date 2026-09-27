import Foundation

public enum BlobStoreError: Error, Equatable {
    case invalidName(String)
}

/// 以独立文件保存图片等二进制内容
public struct BlobStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 返回文件地址；名称不合法（可能来自被篡改的历史文件）时返回 nil，防止路径穿越
    public func url(for name: String) -> URL? {
        guard Self.isValidName(name) else { return nil }
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    /// 写入数据；同名文件已存在时跳过（文件名基于内容哈希，内容必然相同）
    public func write(_ data: Data, name: String) throws {
        guard let url = url(for: name) else { throw BlobStoreError.invalidName(name) }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try PrivateFiles.createDirectory(at: directory)
        try PrivateFiles.write(data, to: url)
    }

    public func read(_ name: String) throws -> Data {
        guard let url = url(for: name) else { throw BlobStoreError.invalidName(name) }
        return try Data(contentsOf: url)
    }

    public func exists(_ name: String) -> Bool {
        guard let url = url(for: name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 删除指定文件，返回删除失败的文件名
    @discardableResult
    public func remove(_ names: some Sequence<String>) -> [String] {
        names.filter { name in
            guard let url = url(for: name) else { return true }
            do {
                try FileManager.default.removeItem(at: url)
                return false
            } catch CocoaError.fileNoSuchFile {
                return false
            } catch {
                return true
            }
        }
    }

    /// 删除所有未被引用的文件，返回被删除的文件名
    @discardableResult
    public func removeAll(except keep: Set<String>) throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        // 只清理普通文件，避免误删子目录
        let orphans = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .map(\.lastPathComponent)
        .filter { !keep.contains($0) && Self.isValidName($0) }
        let failed = Set(remove(orphans))
        return orphans.filter { !failed.contains($0) }
    }

    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("."), name.count <= 255 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
                || scalar == "." || scalar == "-" || scalar == "_"
        }
    }
}
