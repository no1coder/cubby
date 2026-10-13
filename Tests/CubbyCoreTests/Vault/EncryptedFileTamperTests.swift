import CryptoKit
import Foundation
import Testing
@testable import CubbyCore

@Suite("EncryptedFileFormat 篡改、截断、重排、换文件、错误密钥")
struct EncryptedFileTamperTests {
    private static let segment = EncryptedFileFormat.segmentPlaintextByteCount
    private static let fullSegment = segment + EncryptedFileFormat.tagByteCount
    private static let header = EncryptedFileFormat.headerByteCount
    /// 密钥 ID 在头部中的位置
    private static let keyIDRange = 6..<14
    /// 每文件随机盐在头部中的位置
    private static let saltRange = 14..<30

    private func sample(size: Int = 3 * segment + 100) throws -> (keys: HistoryKeys, file: Data) {
        let keys = try VaultFixtures.keys()
        return (keys, try EncryptedFileFormat.encrypt(VaultFixtures.bytes(size), keys: keys, role: "history"))
    }

    private func decryptError(_ file: Data, keys: HistoryKeys, role: String = "history") -> EncryptedFileError? {
        do {
            _ = try EncryptedFileFormat.decrypt(file, keys: keys, role: role)
            return nil
        } catch {
            return error
        }
    }

    private func flipping(_ file: Data, at offset: Int) -> Data {
        var copy = file
        copy[offset] ^= 0x01
        return copy
    }

    @Test("头部任一字节被改都会失败：魔数、版本、标志位 → 头部非法，密钥 ID → 密钥不对，盐与 nonce 前缀 → 损坏")
    func headerFlips() throws {
        let (keys, file) = try sample(size: 10)
        for offset in 0..<Self.header {
            let error = decryptError(flipping(file, at: offset), keys: keys)
            switch offset {
            // 版本 1 翻转最低位得到 0：低于任何已发布版本，视为头部非法
            case 0..<6: #expect(error == .malformedHeader, "offset \(offset)")
            case Self.keyIDRange: #expect(error == .keyMismatch, "offset \(offset)")
            default: #expect(error == .corrupted, "offset \(offset)")
            }
        }
    }

    @Test("盐的任一字节被改：派生出的段密钥不同，报损坏")
    func saltFlips() throws {
        let (keys, file) = try sample()
        for offset in Self.saltRange {
            #expect(decryptError(flipping(file, at: offset), keys: keys) == .corrupted, "offset \(offset)")
        }
    }

    @Test("密文与标签中任一位置的字节被改都报损坏")
    func bodyFlips() throws {
        let (keys, file) = try sample()
        let lastStart = Self.header + 3 * Self.fullSegment
        var offsets: [Int] = []
        for start in stride(from: Self.header, to: lastStart, by: Self.fullSegment) {
            offsets += [
                start, start + 1, start + Self.segment / 2, start + Self.segment - 1, start + Self.segment,
                start + Self.fullSegment - 1,
            ]
        }
        offsets += [lastStart, lastStart + 50, file.count - 17, file.count - 16, file.count - 1]

        for offset in offsets {
            #expect(decryptError(flipping(file, at: offset), keys: keys) == .corrupted, "offset \(offset)")
        }
    }

    @Test("小文件逐字节翻转全部被发现")
    func exhaustiveSmallFile() throws {
        let (keys, file) = try sample(size: 40)
        for offset in Self.header..<file.count {
            #expect(decryptError(flipping(file, at: offset), keys: keys) == .corrupted, "offset \(offset)")
        }
    }

    @Test("截断：去掉末段、截掉任意字节、只剩头部、短于头部")
    func truncation() throws {
        let (keys, file) = try sample()
        let withoutFinal = file.prefix(Self.header + 3 * Self.fullSegment)
        let withoutTwo = file.prefix(Self.header + 2 * Self.fullSegment)

        #expect(decryptError(withoutFinal, keys: keys) == .corrupted)
        #expect(decryptError(withoutTwo, keys: keys) == .corrupted)
        #expect(decryptError(file.dropLast(), keys: keys) == .corrupted)
        #expect(decryptError(file.dropLast(16), keys: keys) == .corrupted)
        #expect(decryptError(file.prefix(Self.header), keys: keys) == .corrupted)
        #expect(decryptError(file.prefix(Self.header + 15), keys: keys) == .corrupted)
        #expect(decryptError(file.prefix(Self.header - 1), keys: keys) == .malformedHeader)
        #expect(decryptError(Data(), keys: keys) == .malformedHeader)
        #expect(throws: EncryptedFileError.malformedHeader) {
            try EncryptedFileFormat.plaintextByteCount(ofFile: Data([1, 2, 3]))
        }
        #expect(throws: EncryptedFileError.corrupted) {
            try EncryptedFileFormat.plaintextByteCount(ofFile: file.prefix(Self.header + 3))
        }
    }

    @Test("恰好整段长度的明文：去掉末段（整段）后也能发现")
    func truncationAtExactSegmentMultiple() throws {
        let (keys, file) = try sample(size: 2 * Self.segment)
        #expect(file.count == Self.header + 2 * Self.fullSegment)
        #expect(decryptError(file.prefix(Self.header + Self.fullSegment), keys: keys) == .corrupted)
    }

    @Test("末尾追加数据：1 字节、一个标签长度、复制一整段", arguments: [1, 16, 0])
    func trailingData(extra: Int) throws {
        let (keys, file) = try sample()
        let appended =
            extra == 0 ? file + file[Self.header..<(Self.header + Self.fullSegment)] : file + Data(count: extra)
        #expect(decryptError(appended, keys: keys) == .corrupted)

        let (smallKeys, small) = try sample(size: 0)
        #expect(decryptError(small + Data(count: max(extra, 1)), keys: smallKeys) == .corrupted)
    }

    @Test("段重排：交换前两段、末段换到前面都报损坏")
    func reorder() throws {
        let (keys, file) = try sample(size: 3 * Self.segment)
        let head = file.prefix(Self.header)
        let segments = (0..<3).map { index in
            file[(Self.header + index * Self.fullSegment)..<(Self.header + (index + 1) * Self.fullSegment)]
        }
        let swapped = head + segments[1] + segments[0] + segments[2]
        let lastFirst = head + segments[2] + segments[1] + segments[0]

        #expect(decryptError(swapped, keys: keys) == .corrupted)
        #expect(decryptError(lastFirst, keys: keys) == .corrupted)
    }

    @Test("把另一个文件的段拼进来（同一密钥、不同 nonce 前缀）报损坏")
    func spliceFromOtherFile() throws {
        let keys = try VaultFixtures.keys()
        let plaintext = VaultFixtures.bytes(2 * Self.segment + 1)
        let first = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "history")
        let second = try EncryptedFileFormat.encrypt(plaintext, keys: keys, role: "history")
        let range = Self.header..<(Self.header + Self.fullSegment)
        var spliced = first
        spliced.replaceSubrange(range, with: second[range])

        #expect(decryptError(spliced, keys: keys) == .corrupted)
    }

    @Test("角色不符（把一个文件换成另一个）报损坏，而非密钥不对")
    func wrongRole() throws {
        let keys = try VaultFixtures.keys()
        let blob = try EncryptedFileFormat.encrypt(Data("img".utf8), keys: keys, role: "blob:aaa")

        #expect(decryptError(blob, keys: keys, role: "blob:bbb") == .corrupted)
        #expect(decryptError(blob, keys: keys, role: "history") == .corrupted)
        #expect(decryptError(blob, keys: keys, role: "blob:aaa") == nil)
    }

    @Test("错误的密钥报密钥不对；伪造了密钥 ID 的文件报损坏")
    func wrongKey() throws {
        let (keys, file) = try sample(size: 50)
        let otherKeys = try VaultFixtures.keys(0x99)

        #expect(decryptError(file, keys: otherKeys) == .keyMismatch)

        var forged = file
        forged.replaceSubrange(Self.keyIDRange, with: otherKeys.keyID)
        #expect(decryptError(forged, keys: otherKeys) == .corrupted)
        #expect(decryptError(forged, keys: keys) == .keyMismatch)
    }

    @Test("更高的格式版本报不支持（由更新版本的 Cubby 写入），并带出版本号")
    func newerVersion() throws {
        let (keys, file) = try sample(size: 10)
        var newer = file
        newer[4] = EncryptedFileFormat.currentVersion + 1
        let expected = EncryptedFileError.unsupportedVersion(found: Int(EncryptedFileFormat.currentVersion) + 1)

        #expect(decryptError(newer, keys: keys) == expected)
        #expect(throws: expected) { try EncryptedFileFormat.plaintextByteCount(ofFile: newer) }
    }

    @Test("非法头部的文件无法取得密钥 ID")
    func keyIDOfMalformedFile() {
        #expect(throws: EncryptedFileError.malformedHeader) {
            try EncryptedFileFormat.keyID(ofFile: Data("not an encrypted file at all".utf8))
        }
    }
}
