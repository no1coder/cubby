import CryptoKit
import Foundation
import Testing
@testable import CubbyCore

@Suite("EncryptedFileFormat 往返、头部与长度")
struct EncryptedFileFormatTests {
    private static let segment = EncryptedFileFormat.segmentPlaintextByteCount
    private static let sizes = [0, 1, 100, segment - 1, segment, segment + 1, 3 * segment + 5]

    @Test("任意长度、任意写入分块都能往返", arguments: sizes, [7, 4096, 100_000])
    func roundTrip(size: Int, chunkSize: Int) throws {
        let keys = try VaultFixtures.keys()
        let plaintext = VaultFixtures.bytes(size)
        let file = try VaultFixtures.encrypt(plaintext, keys: keys, role: "history", chunkSize: chunkSize)

        #expect(try EncryptedFileFormat.decrypt(file, keys: keys, role: "history") == plaintext)
        #expect(try EncryptedFileFormat.plaintextByteCount(ofFile: file) == size)
    }

    @Test("文件长度 = 头部 + 明文 + 每段 16 字节标签；空明文只有一个空的末段", arguments: sizes)
    func fileLayout(size: Int) throws {
        let keys = try VaultFixtures.keys()
        let file = try EncryptedFileFormat.encrypt(VaultFixtures.bytes(size), keys: keys, role: "r")
        let segments = max(1, (size + Self.segment - 1) / Self.segment)

        #expect(
            file.count == EncryptedFileFormat.headerByteCount + size + segments * EncryptedFileFormat.tagByteCount
        )
    }

    @Test("头部：魔数 CBYV、格式版本、保留标志位为 0、密钥 ID、16 字节随机盐、7 字节随机前缀")
    func headerLayout() throws {
        let keys = try VaultFixtures.keys()
        let file = try EncryptedFileFormat.encrypt(Data("hello".utf8), keys: keys, role: "r")

        #expect(EncryptedFileFormat.headerByteCount == 37)
        #expect(file.prefix(4) == Data("CBYV".utf8))
        #expect(file[4] == EncryptedFileFormat.currentVersion)
        #expect(file[5] == 0)
        #expect(file[6..<14] == keys.keyID)
        #expect(try EncryptedFileFormat.keyID(ofFile: file) == keys.keyID)
    }

    @Test("同一明文两次加密得到不同密文（随机盐与 nonce 前缀），且都不含明文")
    func randomizedNonce() throws {
        let keys = try VaultFixtures.keys()
        let plaintext = Data("secret clipboard text secret clipboard text".utf8)
        let first = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "r")
        let second = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "r")

        #expect(first[14..<30] != second[14..<30])
        #expect(first[30..<37] != second[30..<37])
        #expect(first != second)
        #expect(first.range(of: Data("secret".utf8)) == nil)
    }

    @Test("nonce 前缀相同（强制碰撞）但盐不同：两份密文毫无关联，且都能正确解密")
    func saltSeparatesNoncePrefixCollisions() throws {
        let keys = try VaultFixtures.keys()
        let plaintext = VaultFixtures.bytes(Self.segment + 100)
        let prefix = Data(repeating: 0xAB, count: EncryptedFileFormat.noncePrefixByteCount)
        let headers = [Data(repeating: 1, count: 16), Data(repeating: 2, count: 16)].map {
            EncryptedFileFormat.Header(keyID: keys.keyID, salt: $0, noncePrefix: prefix)
        }
        let files = try headers.map { header in
            var output = Data()
            try EncryptedFileFormat.encrypt(keys: keys, role: "r", header: header, into: { output.append($0) }) {
                try $0(plaintext)
            }
            return output
        }

        #expect(files[0][30..<37] == files[1][30..<37])
        let bodies = files.map { $0.dropFirst(EncryptedFileFormat.headerByteCount) }
        // 若 (密钥, nonce) 重用，两份密文的异或会等于两份明文的异或（此处为全 0）；不同的段密钥使其近似随机
        let identical = zip(bodies[0], bodies[1]).filter { $0 == $1 }.count
        #expect(identical < bodies[0].count / 64)
        for file in files {
            #expect(try EncryptedFileFormat.decrypt(file, keys: keys, role: "r") == plaintext)
        }
    }

    @Test("解密进调用方提供的缓冲区，返回写入的字节数")
    func decryptIntoBuffer() throws {
        let keys = try VaultFixtures.keys()
        let plaintext = VaultFixtures.bytes(2 * Self.segment + 9)
        let file = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "r")
        let count = try EncryptedFileFormat.plaintextByteCount(ofFile: file)
        var buffer = [UInt8](repeating: 0, count: count + 3)

        let written = try buffer.withUnsafeMutableBytes {
            try EncryptedFileFormat.decrypt(file, keys: keys, role: "r", into: $0)
        }

        #expect(written == plaintext.count)
        #expect(Data(buffer.prefix(written)) == plaintext)
    }

    @Test("withDecryptedContents：交给闭包的是明文，并透传闭包的返回值与错误")
    func withDecryptedContents() throws {
        struct Marker: Error {}
        let keys = try VaultFixtures.keys()
        let plaintext = VaultFixtures.bytes(Self.segment + 3)
        let file = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "r")

        let echoed = try EncryptedFileFormat.withDecryptedContents(of: file, keys: keys, role: "r") { Data($0) }
        #expect(echoed == plaintext)
        #expect(throws: Marker.self) {
            try EncryptedFileFormat.withDecryptedContents(of: file, keys: keys, role: "r") { _ in throw Marker() }
        }
        let empty = try EncryptedFileFormat.encrypt(Data(), keys: keys, role: "r")
        #expect(try EncryptedFileFormat.withDecryptedContents(of: empty, keys: keys, role: "r") { $0.count } == 0)
    }

    @Test("Data 切片（非零起始下标）同样可以解密")
    func decryptsSlices() throws {
        let keys = try VaultFixtures.keys()
        let plaintext = VaultFixtures.bytes(Self.segment + 10)
        let file = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "r")
        let padded = Data([9, 9, 9]) + file
        let slice = padded[3...]

        #expect(try EncryptedFileFormat.decrypt(slice, keys: keys, role: "r") == plaintext)
        #expect(try EncryptedFileFormat.keyID(ofFile: slice) == keys.keyID)
    }

    @Test("生产闭包抛错时错误原样透传")
    func produceErrorPropagates() throws {
        struct Marker: Error {}
        let keys = try VaultFixtures.keys()
        #expect(throws: Marker.self) {
            try EncryptedFileFormat.encrypt(keys: keys, role: "r", into: { _ in }) { _ in throw Marker() }
        }
    }
}
