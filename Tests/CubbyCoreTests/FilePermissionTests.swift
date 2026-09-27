import Foundation
import Testing
@testable import CubbyCore

/// 剪贴板历史可能包含密码等敏感内容：目录 0700，文件 0600
@Suite("私有文件权限（0700 / 0600）")
struct FilePermissionTests {
    private let directoryMode = 0o700
    private let fileMode = 0o600

    @Test("权限常量")
    func constants() {
        #expect(PrivateFiles.directoryPermissions == directoryMode)
        #expect(PrivateFiles.filePermissions == fileMode)
    }

    // MARK: - BlobStore

    @Test("BlobStore 新建目录为 0700、文件为 0600")
    func blobStoreCreatesPrivateFiles() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let blobDir = root.appendingPathComponent("blobs", isDirectory: true)
        try BlobStore(directory: blobDir).write(Data([1, 2, 3]), name: "a.png")

        #expect(try TempDirectory.permissions(of: blobDir) == directoryMode)
        #expect(try TempDirectory.permissions(of: blobDir.appendingPathComponent("a.png")) == fileMode)
    }

    @Test("BlobStore 写入时把已存在的宽松目录收紧为 0700")
    func blobStoreTightensExistingDirectory() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let blobDir = root.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: blobDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]
        )
        #expect(try TempDirectory.permissions(of: blobDir) == 0o755)

        try BlobStore(directory: blobDir).write(Data([1]), name: "b.formats")

        #expect(try TempDirectory.permissions(of: blobDir) == directoryMode)
        #expect(try TempDirectory.permissions(of: blobDir.appendingPathComponent("b.formats")) == fileMode)
    }

    @Test("BlobStore 多级父目录均为 0700")
    func blobStoreIntermediateDirectories() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let parent = root.appendingPathComponent("a", isDirectory: true)
        let blobDir = parent.appendingPathComponent("b", isDirectory: true)
        try BlobStore(directory: blobDir).write(Data([1]), name: "x.png")

        #expect(try TempDirectory.permissions(of: parent) == directoryMode)
        #expect(try TempDirectory.permissions(of: blobDir) == directoryMode)
    }

    // MARK: - JSONHistoryStorage

    @Test("历史文件为 0600，所在目录为 0700")
    func historyFileIsPrivate() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let dir = root.appendingPathComponent("Cubby", isDirectory: true)
        let fileURL = dir.appendingPathComponent("history.json")
        try JSONHistoryStorage(fileURL: fileURL).save(ClipHistory(items: [Fixtures.text("secret")]))

        #expect(try TempDirectory.permissions(of: fileURL) == fileMode)
        #expect(try TempDirectory.permissions(of: dir) == directoryMode)
    }

    @Test("覆盖保存（原子写入产生新文件）后仍为 0600")
    func historyFileStaysPrivateAfterOverwrite() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let fileURL = root.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        try storage.save(ClipHistory(items: [Fixtures.text("first")]))
        try storage.save(ClipHistory(items: [Fixtures.text("second")]))

        #expect(try TempDirectory.permissions(of: fileURL) == fileMode)
        #expect(try storage.load().items.map(\.text) == ["second"])
    }

    @Test("旧版本遗留的 0644 历史文件在下次保存后收紧为 0600")
    func legacyHistoryFileIsTightened() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let fileURL = root.appendingPathComponent("history.json")
        try Data("{\"items\":[]}".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)

        try JSONHistoryStorage(fileURL: fileURL).save(.empty)

        #expect(try TempDirectory.permissions(of: fileURL) == fileMode)
        #expect(try TempDirectory.permissions(of: root) == directoryMode)
    }

    // MARK: - ClipStore 集成

    @MainActor
    @Test("ClipStore 记录图片与富文本时生成的 blob 均为 0600")
    func clipStoreBlobsArePrivate() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let blobDir = root.appendingPathComponent("blobs", isDirectory: true)
        let store = StoreFactory.make(dir: blobDir)
        let image = try #require(store.record(.image(png: Data("png".utf8), width: 1, height: 1), source: nil))
        let rich = try #require(store.record(.richText("粗体", formats: Fixtures.richFormats(for: "粗体")), source: nil))

        for name in image.blobNames + rich.blobNames {
            #expect(try TempDirectory.permissions(of: blobDir.appendingPathComponent(name)) == fileMode, "\(name)")
        }
        #expect(try TempDirectory.permissions(of: blobDir) == directoryMode)
    }
}
