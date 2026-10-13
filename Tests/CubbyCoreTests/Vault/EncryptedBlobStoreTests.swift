import Foundation
import Testing
@testable import CubbyCore

@Suite("EncryptedBlobStore 加密图片等二进制内容")
struct EncryptedBlobStoreTests {
    private func makeStore(_ root: URL, keyByte: UInt8 = 0x42) throws -> EncryptedBlobStore {
        EncryptedBlobStore(directory: root.appendingPathComponent("Blobs"), keys: try VaultFixtures.keys(keyByte))
    }

    @Test("写入后读回明文；磁盘上是密文，文件 0600、目录 0700")
    func writeAndRead() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)
        let data = Data("\u{89}PNG fake image bytes".utf8)

        try store.write(data, name: "abc")

        #expect(try store.data("abc") == data)
        let fileURL = store.directory.appendingPathComponent("abc")
        let raw = try Data(contentsOf: fileURL)
        #expect(raw.prefix(4) == Data("CBYV".utf8))
        #expect(raw.range(of: Data("PNG".utf8)) == nil)
        #expect(try TempDirectory.permissions(of: fileURL) == 0o600)
        #expect(try TempDirectory.permissions(of: store.directory) == 0o700)
    }

    @Test("空数据与跨多段的大数据都能往返", arguments: [0, 3 * EncryptedFileFormat.segmentPlaintextByteCount + 1])
    func sizes(size: Int) throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)
        let data = VaultFixtures.bytes(size)

        try store.write(data, name: "big")
        #expect(try store.data("big") == data)
    }

    @Test("同名已存在时跳过写入（名称由内容派生）")
    func writeSkipsExisting() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)

        try store.write(Data("first".utf8), name: "same")
        try store.write(Data("second".utf8), name: "same")
        #expect(try store.data("same") == Data("first".utf8))
    }

    @Test("文件改名（换成另一个 blob）后读取报损坏：角色绑定了文件名")
    func renamedBlobIsRejected() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)
        try store.write(Data("a".utf8), name: "aaa")
        try FileManager.default.copyItem(
            at: store.directory.appendingPathComponent("aaa"), to: store.directory.appendingPathComponent("bbb")
        )

        #expect(throws: EncryptedFileError.corrupted) { try store.data("bbb") }
        #expect(EncryptedBlobStore.role(forName: "aaa") == "blob:aaa")
    }

    @Test("密钥不对报 keyMismatch；被篡改报 corrupted；不存在抛文件错误")
    func readErrors() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        try makeStore(root, keyByte: 1).write(Data("x".utf8), name: "n")
        let store = try makeStore(root, keyByte: 2)

        #expect(throws: EncryptedFileError.keyMismatch) { try store.data("n") }

        let original = try makeStore(root, keyByte: 1)
        let url = original.directory.appendingPathComponent("n")
        var raw = try Data(contentsOf: url)
        raw[raw.count - 1] ^= 1
        try raw.write(to: url)
        #expect(throws: EncryptedFileError.corrupted) { try original.data("n") }

        #expect(throws: CocoaError.self) { try original.data("missing") }
    }

    @Test("非法名称：读写抛 invalidName，exists 为 false，不触碰目录外文件", arguments: ["../x", "", ".hidden", "a/b"])
    func invalidNames(name: String) throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)

        #expect(throws: BlobStoreError.invalidName(name)) { try store.write(Data([1]), name: name) }
        #expect(throws: BlobStoreError.invalidName(name)) { try store.data(name) }
        #expect(!store.exists(name))
        #expect(store.remove([name]) == [name])
    }

    @Test("exists、remove：不存在的文件不算失败")
    func existsAndRemove() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)
        try store.write(Data([1]), name: "a")
        try store.write(Data([2]), name: "b")

        #expect(store.exists("a"))
        #expect(!store.exists("zzz"))
        #expect(store.remove(["a", "missing"]).isEmpty)
        #expect(TempDirectory.fileNames(in: store.directory) == ["b"])
    }

    @Test("removeAll(except:)：只删未引用的合法普通文件，保留子目录与非法名称，清理过期临时文件")
    func removeAllExcept() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)
        #expect(try store.removeAll(except: []) == [])

        for name in ["keep", "drop1", "drop2"] { try store.write(Data(name.utf8), name: name) }
        let subdirectory = store.directory.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let stale = store.directory.appendingPathComponent(".drop3.\(UUID().uuidString).tmp")
        let fresh = store.directory.appendingPathComponent(".drop4.\(UUID().uuidString).tmp")
        let foreign = store.directory.appendingPathComponent(".DS_Store")
        for url in [stale, fresh, foreign] { try Data("t".utf8).write(to: url) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: stale.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: foreign.path)

        let removed = try store.removeAll(except: ["keep"])

        #expect(Set(removed) == ["drop1", "drop2"])
        #expect(TempDirectory.fileNames(in: store.directory) == ["keep", "sub"])
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test("写入失败（Blobs 路径被普通文件占用）时抛出，不留下任何文件")
    func failedWriteLeavesNothing() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try makeStore(root)
        try Data("occupied".utf8).write(to: store.directory)

        #expect(throws: (any Error).self) { try store.write(Data([1]), name: "y") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Blobs"])
        #expect(try Data(contentsOf: store.directory) == Data("occupied".utf8))
    }
}
