import CryptoKit
import Foundation
import Testing
@testable import CubbyCore

@Suite("HistoryKeys 密钥派生与文件名")
struct HistoryKeysTests {
    @Test("同一主密钥派生结果确定；不同主密钥派生结果不同")
    func derivationIsDeterministic() throws {
        let first = try VaultFixtures.keys(1)
        let again = try VaultFixtures.keys(1)
        let other = try VaultFixtures.keys(2)

        #expect(first == again)
        #expect(first.keyID == again.keyID)
        #expect(first != other)
        #expect(first.keyID != other.keyID)
    }

    @Test("密钥 ID 为 8 字节，加密密钥与文件名密钥都是 256 位且互不相同、不等于主密钥")
    func derivedKeysAreSeparated() throws {
        let master = VaultFixtures.masterKey(9)
        let keys = try HistoryKeys(masterKey: master)

        #expect(keys.keyID.count == HistoryKeys.keyIDByteCount)
        #expect(keys.encryptionKey.bitCount == 256)
        #expect(keys.fileNameKey.bitCount == 256)
        let encryption = VaultFixtures.keyBytes(keys.encryptionKey)
        let fileName = VaultFixtures.keyBytes(keys.fileNameKey)
        let masterBytes = VaultFixtures.keyBytes(master)
        #expect(encryption != fileName)
        #expect(encryption != masterBytes)
        #expect(fileName != masterBytes)
        #expect(!encryption.starts(with: keys.keyID))
    }

    @Test("主密钥长度不是 256 位时拒绝", arguments: [0, 16, 31, 33, 64])
    func rejectsWrongKeyLength(byteCount: Int) {
        let key = SymmetricKey(data: Data(repeating: 1, count: byteCount))
        #expect(throws: HistoryKeyError.invalidKey) {
            try HistoryKeys(masterKey: key)
        }
    }

    @Test("生成的主密钥为 256 位且每次不同")
    func generatedMasterKeys() throws {
        let first = HistoryKeys.generateMasterKey()
        let second = HistoryKeys.generateMasterKey()
        #expect(first.bitCount == 256)
        #expect(VaultFixtures.keyBytes(first) != VaultFixtures.keyBytes(second))
        _ = try HistoryKeys(masterKey: first)
    }

    @Test("blobName：64 位小写十六进制，符合 BlobStore 文件名字符集，且与 HMAC 结果一致")
    func blobNameFormat() throws {
        let keys = try VaultFixtures.keys()
        let name = keys.blobName(kind: "image", contentHash: "image:abc123")

        #expect(name.count == 64)
        #expect(name.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) })
        #expect(BlobStore.isValidName(name))
        #expect(EncryptedBlobStore.isValidName(name))

        let expected = HMAC<SHA256>.authenticationCode(
            for: Data("image:image:abc123".utf8), using: keys.fileNameKey
        )
        #expect(name == expected.map { String(format: "%02x", $0) }.joined())
    }

    @Test("blobName：同输入相同；种类、哈希或密钥不同则不同；不暴露明文哈希")
    func blobNameSeparation() throws {
        let keys = try VaultFixtures.keys()
        let base = keys.blobName(kind: "image", contentHash: "h1")

        #expect(base == keys.blobName(kind: "image", contentHash: "h1"))
        #expect(base != keys.blobName(kind: "thumbnail", contentHash: "h1"))
        #expect(base != keys.blobName(kind: "image", contentHash: "h2"))
        #expect(base != (try VaultFixtures.keys(3)).blobName(kind: "image", contentHash: "h1"))
        #expect(!base.contains("h1"))
        // 特殊字符与空串同样得到合法文件名
        #expect(BlobStore.isValidName(keys.blobName(kind: "image", contentHash: "")))
        #expect(BlobStore.isValidName(keys.blobName(kind: "formats", contentHash: "../📋 中文\n")))
    }
}
