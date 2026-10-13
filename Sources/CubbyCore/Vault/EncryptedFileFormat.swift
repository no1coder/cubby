import CryptoKit
import Foundation

/// 加密文件无法读取的原因
public enum EncryptedFileError: Error, Equatable, Sendable {
    /// 不是本格式的文件：长度不足一个头部、魔数不符、版本号低于最早版本或保留位非 0
    case malformedHeader
    /// 由更新版本的 Cubby 写入（格式版本更高），调用方不应改动该文件
    case unsupportedVersion(found: Int)
    /// 文件的密钥 ID 与当前密钥不符：换了密钥，而不是内容损坏
    case keyMismatch
    /// 密钥正确但认证失败：被篡改、截断、追加、段重排或角色（文件名）不符
    case corrupted
    /// 明文过大，段序号溢出（约 256 TiB，正常不会发生）
    case tooLarge
}

/// Cubby 加密文件格式（E4），纯函数，不接触文件系统。
///
/// 布局：头部 37 字节 = 魔数 "CBYV"(4) + 格式版本(1) + 保留标志位(1，当前为 0) + 密钥 ID(8) + 随机盐(16)
/// + 随机 nonce 前缀(7)；之后是若干段，每段 = AES-256-GCM 密文 + 16 字节标签。明文按 64 KiB 分段，
/// 非末段必须是整段，末段 0…64 KiB（空明文即一个空的末段）。
///
/// 每文件段密钥（Tink AES-GCM-HKDF 流式构造）：段密钥 = HKDF-SHA256(加密密钥, 盐, "cubby.file.v1" ‖ 角色)。
/// 同一把主密钥一生中会写出海量文件（历史每次改动都重写、图片不断累积），仅靠 56 位 nonce 前缀会撞上生日界、
/// 重用 (密钥, nonce)；有了 128 位随机盐，每个文件用各自的密钥，前缀碰撞也无害。
///
/// STREAM 构造：第 i 段的 nonce = 前缀(7) ‖ i(4，大端) ‖ 末段标记(1)，因此段重排、截断（末段标记对不上）、
/// 追加数据都会认证失败。每段的 AAD = 头部字节 ‖ 角色（如 "history"、"blob:<名称>"），文件被换位置也会失败。
public enum EncryptedFileFormat {
    public static let currentVersion: UInt8 = 1
    public static let headerByteCount =
        magic.count + 2 + HistoryKeys.keyIDByteCount + saltByteCount + noncePrefixByteCount
    /// 每段明文长度
    public static let segmentPlaintextByteCount = 64 * 1024
    /// 每段 GCM 标签长度
    public static let tagByteCount = 16

    static let magic = Data("CBYV".utf8)
    static let noncePrefixByteCount = 7
    /// 每文件随机盐长度
    static let saltByteCount = 16
    /// 段密钥派生的 info 前缀（其后紧跟角色字节）
    private static let segmentKeyInfo = Data("cubby.file.v1".utf8)
    /// 当前版本唯一合法的标志位
    static let currentFlags: UInt8 = 0
    static let fullSegmentByteCount = segmentPlaintextByteCount + tagByteCount
    /// nonce 中末段标记的取值
    private static let lastSegmentMarker: UInt8 = 1
    private static let middleSegmentMarker: UInt8 = 0

    /// 读取文件头部中的密钥 ID（无需密钥），用于识别保留的旧数据属于哪把密钥（E8 ②）
    public static func keyID(ofFile file: Data) throws(EncryptedFileError) -> Data {
        try Header(parsing: file).keyID
    }

    /// 第 index 段的 nonce
    static func nonce(prefix: Data, index: UInt32, isLast: Bool) -> AES.GCM.Nonce {
        var bytes = prefix
        withUnsafeBytes(of: index.bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(isLast ? lastSegmentMarker : middleSegmentMarker)
        // 12 字节恒为合法的 GCM nonce
        guard let nonce = try? AES.GCM.Nonce(data: bytes) else { preconditionFailure("Invalid nonce length") }
        return nonce
    }

    /// 本文件的段密钥：由加密密钥、头部中的盐与角色派生
    static func segmentKey(keys: HistoryKeys, header: Header, role: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: keys.encryptionKey, salt: header.salt, info: segmentKeyInfo + Data(role.utf8),
            outputByteCount: HistoryKeys.derivedKeyByteCount
        )
    }

    /// 每段共用的附加认证数据
    static func additionalData(header: Header, role: String) -> Data {
        header.bytes + Data(role.utf8)
    }

    /// 文件头部
    struct Header: Equatable {
        let keyID: Data
        let salt: Data
        let noncePrefix: Data

        /// 新文件的头部：当前版本、随机盐与随机 nonce 前缀
        init(keyID: Data) {
            self.init(
                keyID: keyID, salt: Self.randomBytes(saltByteCount), noncePrefix: Self.randomBytes(noncePrefixByteCount)
            )
        }

        /// 指定盐与前缀（测试用，用于构造前缀碰撞）
        init(keyID: Data, salt: Data, noncePrefix: Data) {
            precondition(salt.count == saltByteCount && noncePrefix.count == noncePrefixByteCount)
            self.keyID = keyID
            self.salt = salt
            self.noncePrefix = noncePrefix
        }

        private static func randomBytes(_ count: Int) -> Data {
            var generator = SystemRandomNumberGenerator()
            return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        }

        init(parsing file: Data) throws(EncryptedFileError) {
            guard file.count >= headerByteCount else { throw .malformedHeader }
            let start = file.startIndex
            let versionIndex = start + magic.count
            guard file[start..<versionIndex] == magic else { throw .malformedHeader }
            let version = file[versionIndex]
            guard version <= currentVersion else { throw .unsupportedVersion(found: Int(version)) }
            guard version == currentVersion, file[versionIndex + 1] == currentFlags else { throw .malformedHeader }
            let keyIDStart = versionIndex + 2
            let saltStart = keyIDStart + HistoryKeys.keyIDByteCount
            let prefixStart = saltStart + saltByteCount
            keyID = Data(file[keyIDStart..<saltStart])
            salt = Data(file[saltStart..<prefixStart])
            noncePrefix = Data(file[prefixStart..<(prefixStart + noncePrefixByteCount)])
        }

        var bytes: Data {
            magic + Data([currentVersion, currentFlags]) + keyID + salt + noncePrefix
        }
    }
}
