import Foundation

/// 加密数据目录 `<数据目录>/Vault/` 的布局（E5）
public struct VaultDirectory: Sendable, Equatable {
    public static let defaultName = "Vault"
    static let historyFileName = "history.cubby"
    static let securityLogFileName = "security-log.cubby"
    static let blobsDirectoryName = "Blobs"
    static let backupsDirectoryName = "Backups"
    static let lockFileName = ".lock"
    static let vaultIDFileName = "vault-id"
    /// 不算加密数据的条目：锁文件、自定义目录的 vault-id（在查找密钥之前就会创建），以及访达生成的 .DS_Store
    private static let bookkeepingNames: Set<String> = [lockFileName, vaultIDFileName, ".DS_Store"]

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var historyURL: URL { url.appendingPathComponent(Self.historyFileName, isDirectory: false) }
    public var securityLogURL: URL { url.appendingPathComponent(Self.securityLogFileName, isDirectory: false) }
    public var blobsDirectory: URL { url.appendingPathComponent(Self.blobsDirectoryName, isDirectory: true) }
    public var backupsDirectory: URL { url.appendingPathComponent(Self.backupsDirectoryName, isDirectory: true) }
    public var lockURL: URL { url.appendingPathComponent(Self.lockFileName, isDirectory: false) }
    public var vaultIDURL: URL { url.appendingPathComponent(Self.vaultIDFileName, isDirectory: false) }

    /// Vault 中是否已有加密数据（VaultKeyResolver 的 vaultHasData）。
    ///
    /// 「Vault/ 不存在」不能简单地看目录是否存在：持锁与写 vault-id 都会先创建目录。
    /// 除锁文件、vault-id、.DS_Store 之外的任何条目（含残留临时文件、未知文件）都算已有数据；
    /// 无法确定时（路径是文件、无权列目录）同样返回 true，宁可报「密钥丢失」也不生成新密钥。
    public func containsEncryptedData() -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        guard isDirectory.boolValue, let names = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return true
        }
        return names.contains { !Self.bookkeepingNames.contains($0) }
    }
}
