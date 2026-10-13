import CryptoKit
import Foundation
@testable import CubbyCore

/// 加密存储测试共用的密钥与数据构造
enum VaultFixtures {
    /// 固定字节的主密钥：同一测试内可重复构造出相同的派生密钥
    static func masterKey(_ byte: UInt8 = 0x42) -> SymmetricKey {
        SymmetricKey(data: Data(repeating: byte, count: HistoryKeys.masterKeyByteCount))
    }

    static func keys(_ byte: UInt8 = 0x42) throws -> HistoryKeys {
        try HistoryKeys(masterKey: masterKey(byte))
    }

    /// 伪随机但可复现的数据，便于定位失败
    static func bytes(_ count: Int, seed: UInt8 = 7) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    /// 按给定分块大小把数据交给加密器
    static func encrypt(_ plaintext: Data, keys: HistoryKeys, role: String, chunkSize: Int) throws -> Data {
        var output = Data()
        try EncryptedFileFormat.encrypt(keys: keys, role: role, into: { output.append($0) }) { write in
            var offset = plaintext.startIndex
            repeat {
                let end = min(offset + chunkSize, plaintext.endIndex)
                try write(plaintext[offset..<end])
                offset = end
            } while offset < plaintext.endIndex
        }
        return output
    }

    static func keyBytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

/// 一个临时数据目录及其中的加密 Vault：ClipStore、迁移、启动流程测试共用
struct VaultEnvironment {
    let root: URL
    let keys: HistoryKeys

    init(keyByte: UInt8 = 0x42) throws {
        root = try TempDirectory.make()
        keys = try VaultFixtures.keys(keyByte)
    }

    var vault: VaultDirectory {
        VaultDirectory(url: root.appendingPathComponent(VaultDirectory.defaultName, isDirectory: true))
    }

    var storage: EncryptedHistoryStorage {
        EncryptedHistoryStorage(vaultDirectory: vault.url, keys: keys)
    }

    var blobs: EncryptedBlobStore {
        EncryptedBlobStore(directory: vault.blobsDirectory, keys: keys)
    }

    /// 旧版本的明文布局
    var plain: PlaintextFiles {
        PlaintextFiles(dataDirectory: root)
    }

    var legacyBlobs: BlobStore {
        BlobStore(directory: plain.imagesDirectory)
    }

    /// Blobs 目录中的文件名（不含隐藏的临时文件）
    var encryptedFileNames: Set<String> {
        TempDirectory.fileNames(in: vault.blobsDirectory)
    }

    func remove() {
        TempDirectory.remove(root)
    }
}
