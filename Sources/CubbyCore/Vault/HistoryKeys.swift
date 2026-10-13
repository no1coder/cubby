import CryptoKit
import Foundation

/// 由 256 位主密钥经 HKDF-SHA256 派生出的各用途密钥（E3）。
///
/// 三者使用不同的 info 标签，彼此独立：泄露文件名密钥或密钥 ID 不影响加密密钥。
public struct HistoryKeys: Sendable {
    /// 主密钥长度（字节）
    public static let masterKeyByteCount = 32
    /// 密钥 ID 长度（字节），写入每个加密文件的头部
    public static let keyIDByteCount = 8
    /// 派生密钥长度（字节）
    static let derivedKeyByteCount = 32

    /// HKDF 的固定盐与各用途的 info 标签（改动任何一个都会让已有数据无法解密）
    private static let salt = Data("io.github.no1coder.Cubby.vault".utf8)
    private static let encryptionInfo = Data("cubby-vault-v1-encryption".utf8)
    private static let fileNameInfo = Data("cubby-vault-v1-file-name".utf8)
    private static let keyIDInfo = Data("cubby-vault-v1-key-id".utf8)
    /// blobName 中种类与内容哈希之间的分隔符（种类本身不应包含它）
    private static let blobNameSeparator = ":"

    /// 文件内容加密密钥（AES-256-GCM）
    let encryptionKey: SymmetricKey
    /// 文件名 HMAC 密钥
    let fileNameKey: SymmetricKey
    /// 密钥 ID：区分「密钥不对」与「内容损坏」，不可用于推出任何密钥
    public let keyID: Data

    public init(masterKey: SymmetricKey) throws(HistoryKeyError) {
        guard masterKey.bitCount == Self.masterKeyByteCount * 8 else { throw .invalidKey }
        encryptionKey = Self.derive(masterKey, info: Self.encryptionInfo, byteCount: Self.derivedKeyByteCount)
        fileNameKey = Self.derive(masterKey, info: Self.fileNameInfo, byteCount: Self.derivedKeyByteCount)
        keyID = Self.derive(masterKey, info: Self.keyIDInfo, byteCount: Self.keyIDByteCount)
            .withUnsafeBytes { Data($0) }
    }

    /// 生成新的随机主密钥（只应在 VaultKeyResolver 判定可以生成时调用）
    public static func generateMasterKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// 加密存储中的文件名：小写十六进制的 HMAC-SHA256(文件名密钥, 种类 + ":" + 内容哈希)。
    /// 保持按内容去重，又不暴露明文哈希与扩展名；结果符合 BlobStore.isValidName 的字符集。
    /// - Parameter kind: 内容种类（如 image、thumbnail），不应包含 ":"
    public func blobName(kind: String, contentHash: String) -> String {
        let message = Data((kind + Self.blobNameSeparator + contentHash).utf8)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: fileNameKey)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    private static func derive(_ master: SymmetricKey, info: Data, byteCount: Int) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: info, outputByteCount: byteCount)
    }
}

extension HistoryKeys: Equatable {
    /// 比较派生出的全部密钥字节
    public static func == (lhs: HistoryKeys, rhs: HistoryKeys) -> Bool {
        lhs.keyID == rhs.keyID
            && lhs.encryptionKey.withUnsafeBytes { Data($0) } == rhs.encryptionKey.withUnsafeBytes { Data($0) }
            && lhs.fileNameKey.withUnsafeBytes { Data($0) } == rhs.fileNameKey.withUnsafeBytes { Data($0) }
    }
}
