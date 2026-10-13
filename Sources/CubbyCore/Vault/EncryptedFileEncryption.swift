import CryptoKit
import Foundation

extension EncryptedFileFormat {
    /// 流式加密：先向 sink 写出头部，produce 可以任意大小多次写入明文，攒满一段即加密写出，最后写出末段。
    ///
    /// sink 可直接接 StreamingFileWriter.write 的写入闭包，整个过程不为整份明文或密文分配连续缓冲。
    /// - Parameters:
    ///   - role: 文件角色，参与认证（如 "history"、"security-log"、"blob:<名称>"），解密时必须相同
    ///   - produce: 通过传入的 write 闭包按顺序写出明文；抛出错误即放弃，错误原样透传
    public static func encrypt(
        keys: HistoryKeys,
        role: String,
        into sink: (Data) throws -> Void,
        _ produce: (_ write: (Data) throws -> Void) throws -> Void
    ) throws {
        try encrypt(keys: keys, role: role, header: Header(keyID: keys.keyID), into: sink, produce)
    }

    /// 指定头部（测试用于构造 nonce 前缀碰撞）
    static func encrypt(
        keys: HistoryKeys,
        role: String,
        header: Header,
        into sink: (Data) throws -> Void,
        _ produce: (_ write: (Data) throws -> Void) throws -> Void
    ) throws {
        // 两个非逃逸闭包互相嵌套调用需要显式声明：sink 只在本函数返回前使用，不会真正逃逸
        try withoutActuallyEscaping(sink) { emit in
            var sealer = SegmentSealer(keys: keys, role: role, header: header)
            try emit(sealer.header.bytes)
            try produce { try sealer.append($0, emit: emit) }
            try sealer.finish(emit: emit)
        }
    }

    /// 整块加密（小文件或测试用）
    public static func encrypt(_ plaintext: Data, keys: HistoryKeys, role: String) throws -> Data {
        var output = Data()
        try encrypt(keys: keys, role: role, into: { output.append($0) }) { try $0(plaintext) }
        return output
    }
}

/// 分段加密的状态：最多缓存一整段明文；只有确认后面还有数据时才把整段作为非末段写出
private struct SegmentSealer {
    let header: EncryptedFileFormat.Header
    private let key: SymmetricKey
    private let additionalData: Data
    private var index: UInt32 = 0
    private var pending: Data

    init(keys: HistoryKeys, role: String, header: EncryptedFileFormat.Header) {
        self.header = header
        key = EncryptedFileFormat.segmentKey(keys: keys, header: header, role: role)
        additionalData = EncryptedFileFormat.additionalData(header: header, role: role)
        pending = Data(capacity: EncryptedFileFormat.segmentPlaintextByteCount)
    }

    mutating func append(_ data: Data, emit: (Data) throws -> Void) throws {
        let segmentSize = EncryptedFileFormat.segmentPlaintextByteCount
        var offset = data.startIndex
        while offset < data.endIndex {
            if pending.count == segmentSize {
                try seal(isLast: false, emit: emit)
            }
            let end = min(offset + segmentSize - pending.count, data.endIndex)
            pending.append(data[offset..<end])
            offset = end
        }
    }

    mutating func finish(emit: (Data) throws -> Void) throws {
        try seal(isLast: true, emit: emit)
    }

    private mutating func seal(isLast: Bool, emit: (Data) throws -> Void) throws {
        let nonce = EncryptedFileFormat.nonce(prefix: header.noncePrefix, index: index, isLast: isLast)
        let box = try AES.GCM.seal(pending, using: key, nonce: nonce, authenticating: additionalData)
        try emit(box.ciphertext + box.tag)
        pending.removeAll(keepingCapacity: true)
        guard !isLast else { return }
        guard index < UInt32.max else { throw EncryptedFileError.tooLarge }
        index += 1
    }
}
