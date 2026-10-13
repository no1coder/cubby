import CryptoKit
import Foundation

extension EncryptedFileFormat {
    /// 文件解密后的明文长度（只看头部与文件长度，不验证内容）
    public static func plaintextByteCount(ofFile file: Data) throws(EncryptedFileError) -> Int {
        _ = try Header(parsing: file)
        return try segmentLayout(bodyByteCount: file.count - headerByteCount).plaintextByteCount
    }

    /// 解密整个文件，写入调用方提供的缓冲区（长度至少为 plaintextByteCount），返回写入的字节数。
    /// 先比对密钥 ID：不符抛 keyMismatch；相符但任何一段认证失败抛 corrupted。
    /// 失败时缓冲区里可能已有部分明文，调用方应直接丢弃整个缓冲区。
    public static func decrypt(
        _ file: Data,
        keys: HistoryKeys,
        role: String,
        into buffer: UnsafeMutableRawBufferPointer
    ) throws(EncryptedFileError) -> Int {
        let header = try Header(parsing: file)
        guard header.keyID == keys.keyID else { throw .keyMismatch }
        let layout = try segmentLayout(bodyByteCount: file.count - headerByteCount)
        precondition(buffer.count >= layout.plaintextByteCount, "Decryption buffer is too small")

        let authenticated = additionalData(header: header, role: role)
        let key = segmentKey(keys: keys, header: header, role: role)
        var offset = file.startIndex + headerByteCount
        var written = 0
        for index in 0...layout.middleSegmentCount {
            let isLast = index == layout.middleSegmentCount
            let length = isLast ? layout.lastSegmentByteCount : fullSegmentByteCount
            let tagStart = offset + length - tagByteCount
            let segmentNonce = nonce(prefix: header.noncePrefix, index: UInt32(index), isLast: isLast)
            let plaintext: Data
            do {
                let box = try AES.GCM.SealedBox(
                    nonce: segmentNonce, ciphertext: file[offset..<tagStart], tag: file[tagStart..<(offset + length)]
                )
                plaintext = try AES.GCM.open(box, using: key, authenticating: authenticated)
            } catch {
                throw .corrupted
            }
            plaintext.withUnsafeBytes { source in
                UnsafeMutableRawBufferPointer(rebasing: buffer[written...]).copyMemory(from: source)
            }
            written += plaintext.count
            offset += length
        }
        return written
    }

    /// 解密为普通 Data（图片等小文件）
    public static func decrypt(_ file: Data, keys: HistoryKeys, role: String) throws(EncryptedFileError) -> Data {
        var output = Data(count: try plaintextByteCount(ofFile: file))
        let written = try output.withUnsafeMutableBytes { (buffer) throws(EncryptedFileError) -> Int in
            try decrypt(file, keys: keys, role: role, into: buffer)
        }
        return output.prefix(written)
    }

    /// 解密到匿名映射内存，把明文的零复制视图交给 body，返回后立即归还内存（E12）。
    /// body 收到的 Data 只在闭包内有效，不得保存。用于历史、安全日志等大文件。
    public static func withDecryptedContents<R>(
        of file: Data,
        keys: HistoryKeys,
        role: String,
        _ body: (Data) throws -> R
    ) throws -> R {
        let buffer = try AnonymousBuffer(byteCount: try plaintextByteCount(ofFile: file))
        let written = try buffer.withUnsafeMutableBytes { (bytes) throws(EncryptedFileError) -> Int in
            try decrypt(file, keys: keys, role: role, into: bytes)
        }
        return try buffer.withData(count: written, body)
    }

    /// 密文主体的分段：若干整段 + 一个末段（1…整段长度，至少含一个标签）
    struct SegmentLayout: Equatable {
        let middleSegmentCount: Int
        let lastSegmentByteCount: Int

        var plaintextByteCount: Int {
            middleSegmentCount * EncryptedFileFormat.segmentPlaintextByteCount
                + lastSegmentByteCount - EncryptedFileFormat.tagByteCount
        }
    }

    /// 由主体长度推出分段；连一个标签都放不下（缺少末段）即视为截断
    static func segmentLayout(bodyByteCount: Int) throws(EncryptedFileError) -> SegmentLayout {
        guard bodyByteCount >= tagByteCount else { throw .corrupted }
        let middle = (bodyByteCount - 1) / fullSegmentByteCount
        let last = bodyByteCount - middle * fullSegmentByteCount
        guard last >= tagByteCount, middle < Int(UInt32.max) else { throw .corrupted }
        return SegmentLayout(middleSegmentCount: middle, lastSegmentByteCount: last)
    }
}
