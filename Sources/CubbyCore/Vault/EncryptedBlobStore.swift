import Foundation

/// 加密的图片等二进制内容 `<Vault>/Blobs/<名称>`（E5、E10）。
///
/// 与 BlobStore 的区别：每个文件是一个加密文件，角色绑定文件名（"blob:<名称>"），改名或互换即认证失败；
/// 只提供数据接口，不返回文件 URL——磁盘上的文件对其他应用毫无用处。
/// 写入经 StreamingFileWriter：临时文件创建时即为 0600，加密后原子替换，任何时刻都不落明文。
public struct EncryptedBlobStore: Sendable {
    private static let rolePrefix = "blob:"

    public let directory: URL
    let keys: HistoryKeys

    public init(directory: URL, keys: HistoryKeys) {
        self.directory = directory
        self.keys = keys
    }

    /// 名称合法性与 BlobStore 相同（防止路径穿越）；HistoryKeys.blobName 的结果总是合法
    public static func isValidName(_ name: String) -> Bool {
        BlobStore.isValidName(name)
    }

    /// 文件的加密角色
    static func role(forName name: String) -> String {
        rolePrefix + name
    }

    /// 写入数据；同名文件已存在时跳过（名称由内容派生，内容必然相同）
    public func write(_ data: Data, name: String) throws {
        let url = try fileURL(for: name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try PrivateFiles.createDirectory(at: directory)
        try StreamingFileWriter.write(to: url) { write in
            try EncryptedFileFormat.encrypt(keys: keys, role: Self.role(forName: name), into: write) { try $0(data) }
        }
    }

    /// 读取并解密。文件不存在抛 CocoaError；密钥不对抛 EncryptedFileError.keyMismatch；被篡改或改名抛 .corrupted
    public func data(_ name: String) throws -> Data {
        let file = try Data(contentsOf: try fileURL(for: name))
        return try EncryptedFileFormat.decrypt(file, keys: keys, role: Self.role(forName: name))
    }

    public func exists(_ name: String) -> Bool {
        guard let url = try? fileURL(for: name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 删除指定文件，返回删除失败的文件名（非法名称算失败，不存在不算）
    @discardableResult
    public func remove(_ names: some Sequence<String>) -> [String] {
        names.filter { name in
            guard let url = try? fileURL(for: name) else { return true }
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

    /// 删除所有未被引用的文件，返回被删除的文件名；顺带清理写入中途被杀遗留的过期临时文件
    @discardableResult
    public func removeAll(except keep: Set<String>) throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        StreamingFileWriter.removeStaleTemporaryFiles(in: directory)
        // 只清理普通文件，避免误删子目录；隐藏文件名本身不合法，不会被删
        let orphans = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .map(\.lastPathComponent)
        .filter { !keep.contains($0) && Self.isValidName($0) }
        let failed = Set(remove(orphans))
        return orphans.filter { !failed.contains($0) }
    }

    private func fileURL(for name: String) throws(BlobStoreError) -> URL {
        guard Self.isValidName(name) else { throw .invalidName(name) }
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}
