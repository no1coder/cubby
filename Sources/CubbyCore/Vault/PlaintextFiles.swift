import Foundation

/// 数据目录中旧版本留下的明文文件（E6）：history.json、Images/、history.v*.bak.json、history.corrupt-*.json，
/// 以及迁移中途的 `.migrated-plain/`。只负责定位、读取与原子改名，不做加密。
public struct PlaintextFiles: Sendable {
    /// 迁移第 ⑤ 步的中转目录：其中的内容必然已写进 Vault，任何时候都可以整个删除
    public static let leftoverDirectoryName = ".migrated-plain"
    static let historyFileName = "history.json"
    static let imagesDirectoryName = "Images"
    private static let historyBaseName = "history."
    private static let migrationBackupSuffix = ".bak.json"
    private static let corruptBackupPrefix = "history.corrupt-"
    private static let jsonExtension = ".json"

    public let dataDirectory: URL

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
    }

    public var historyURL: URL { dataDirectory.appendingPathComponent(Self.historyFileName, isDirectory: false) }
    public var imagesDirectory: URL {
        dataDirectory.appendingPathComponent(Self.imagesDirectoryName, isDirectory: true)
    }
    public var leftoverDirectory: URL {
        dataDirectory.appendingPathComponent(Self.leftoverDirectoryName, isDirectory: true)
    }

    /// 是否还有任何需要迁移或移走的明文
    public var containsPlaintext: Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: historyURL.path) || fileManager.fileExists(atPath: imagesDirectory.path) {
            return true
        }
        return !((try? migrationBackups()) ?? []).isEmpty || !((try? corruptBackups()) ?? []).isEmpty
    }

    /// 删除上次迁移残留的中转目录（每次启动都调用）
    public func removeLeftovers() throws {
        guard FileManager.default.fileExists(atPath: leftoverDirectory.path) else { return }
        try FileManager.default.removeItem(at: leftoverDirectory)
    }

    /// 读取旧图片目录中的文件；不存在（或名称非法、本就无法读取）时为 nil，其他读取错误抛出（不得当作丢失）
    func readLegacyBlob(_ name: String) throws -> Data? {
        let store = BlobStore(directory: imagesDirectory)
        guard let url = store.url(for: name) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        }
    }

    /// 旧格式迁移时留下的明文备份 history.v<N>.bak.json
    func migrationBackups() throws -> [URL] {
        try topLevelFiles { $0.hasPrefix(Self.historyBaseName) && $0.hasSuffix(Self.migrationBackupSuffix) }
    }

    /// 明文历史损坏时留下的备份 history.corrupt-<时间>-<后缀>.json
    func corruptBackups() throws -> [URL] {
        try topLevelFiles { $0.hasPrefix(Self.corruptBackupPrefix) && $0.hasSuffix(Self.jsonExtension) }
    }

    /// 把全部明文逐个原子改名进中转目录：history.json 最先（之后中断，下次启动不会再读到它），
    /// 然后 Images/ 与各备份。afterHistory 是测试用的检查点
    func moveAside(after afterHistory: () throws -> Void) throws {
        try PrivateFiles.createDirectory(at: leftoverDirectory)
        try moveIntoLeftovers(historyURL)
        try afterHistory()
        try moveIntoLeftovers(imagesDirectory)
        for url in try migrationBackups() + corruptBackups() {
            try moveIntoLeftovers(url)
        }
    }

    private func moveIntoLeftovers(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let destination = leftoverDirectory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
    }

    private func topLevelFiles(matching include: (String) -> Bool) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: dataDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)
            .filter(include)
            .sorted()
            .map { dataDirectory.appendingPathComponent($0, isDirectory: false) }
    }
}
