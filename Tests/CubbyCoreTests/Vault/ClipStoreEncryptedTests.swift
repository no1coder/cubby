import Foundation
import Testing
@testable import CubbyCore

/// ClipStore 直接使用加密存储：磁盘上只有密文与 HMAC 文件名；损坏时不清理（E8 ④）
@Suite("ClipStore 加密存储", .timeLimit(.minutes(1)))
@MainActor
struct ClipStoreEncryptedTests {
    @Test("记录大图：原图与缩略图都以 HMAC 名加密写入，数据接口读回原图")
    func recordsEncrypted() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        let png = LargeImageFixtures.png(width: 2400, height: 1300)

        let item = try #require(store.record(.image(png: png, width: 2400, height: 1300), source: nil))
        store.flush()

        let name = try #require(item.image?.name)
        #expect(name == environment.blobs.name(kind: .image, contentHash: ContentHasher.sha256(png)))
        #expect(environment.encryptedFileNames == [name, environment.blobs.thumbnailName(forImage: name)])
        for file in environment.encryptedFileNames {
            let raw = try Data(contentsOf: environment.vault.blobsDirectory.appendingPathComponent(file))
            #expect(raw.starts(with: Data("CBYV".utf8)))
        }
        #expect(store.imageData(for: item) == png)
        let history = try Data(contentsOf: environment.storage.fileURL)
        #expect(history.range(of: Data(name.utf8)) == nil)
    }

    @Test("名称非法（被篡改的历史）：读不到数据，不越出 Blobs 目录")
    func invalidNameReadsNothing() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let store = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        let evil = Fixtures.image(name: "../../etc/passwd")
        #expect(store.imageData(for: evil) == nil)
        #expect(store.imageSource(for: Fixtures.text("t")) == nil)
    }

    @Test("历史损坏（密钥对、认证失败）：移入 Backups，本次运行一个文件都不删，之后的删除也不删文件")
    func corruptionKeepsBlobs() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let first = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        let item = try #require(first.record(.image(png: Data("p".utf8), width: 4, height: 4), source: nil))
        first.flush()
        var file = try Data(contentsOf: environment.storage.fileURL)
        file[file.count - 1] ^= 0xFF
        try file.write(to: environment.storage.fileURL)

        let store = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        guard case .restoredFromCorruption = store.loadIssue else {
            Issue.record("expected a corruption issue, got \(String(describing: store.loadIssue))")
            return
        }
        #expect(store.canPersist)
        #expect(environment.encryptedFileNames == [try #require(item.image?.name)])
        let fresh = try #require(store.record(.image(png: Data("q".utf8), width: 4, height: 4), source: nil))
        store.remove(id: fresh.id)
        store.discardUndo()
        #expect(environment.encryptedFileNames.count == 2)
        #expect(TempDirectory.fileNames(in: environment.vault.backupsDirectory).count == 1)
    }

    @Test("密钥不对：只读、不清理、不移动历史文件")
    func keyMismatchIsReadOnly() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let other = EncryptedHistoryStorage(vaultDirectory: environment.vault.url, keys: try VaultFixtures.keys(0x01))
        try other.save(ClipHistory(items: [Fixtures.text("other key")]))
        let orphan = environment.blobs.name(kind: .image, contentHash: "o")
        try environment.blobs.write(Data("o".utf8), name: orphan)

        let store = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        #expect(!store.canPersist)
        #expect(store.loadIssue == .unreadable)
        #expect(environment.blobs.exists(orphan))
        #expect(FileManager.default.fileExists(atPath: environment.storage.fileURL.path))
    }

    @Test("干净加载：删除孤儿文件，保留历史引用的原图与缩略图")
    func cleanLoadRemovesOrphans() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let first = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        let png = LargeImageFixtures.png(width: 2600, height: 1200)
        let item = try #require(first.record(.image(png: png, width: 2600, height: 1200), source: nil))
        first.flush()
        let orphan = environment.blobs.name(kind: .image, contentHash: "o")
        try environment.blobs.write(Data("o".utf8), name: orphan)

        _ = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 10)
        let name = try #require(item.image?.name)
        #expect(environment.encryptedFileNames == [name, environment.blobs.thumbnailName(forImage: name)])
    }
}
