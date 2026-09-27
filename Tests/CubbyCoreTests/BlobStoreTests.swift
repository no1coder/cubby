import Foundation
import Testing
@testable import CubbyCore

@Suite("BlobStore 文件读写与名称校验")
struct BlobStoreTests {
    @Test("写入后可通过 url(for:) 取回内容，并自动创建目录")
    func writeAndRead() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root.appendingPathComponent("blobs"))
        let data = Data("png-bytes".utf8)
        try store.write(data, name: "abc.png")

        let url = try #require(store.url(for: "abc.png"))
        #expect(url.deletingLastPathComponent().standardizedFileURL == store.directory.standardizedFileURL)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("同名文件已存在时跳过写入")
    func writeSkipsExistingName() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root)
        try store.write(Data("first".utf8), name: "same.png")
        try store.write(Data("second".utf8), name: "same.png")

        let url = try #require(store.url(for: "same.png"))
        #expect(try Data(contentsOf: url) == Data("first".utf8))
    }

    @Test("删除文件；不存在的文件不算失败")
    func removeFiles() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root)
        try store.write(Data([1]), name: "a.png")
        try store.write(Data([2]), name: "b.png")

        let failed = store.remove(["a.png", "missing.png"])

        #expect(failed.isEmpty)
        #expect(TempDirectory.fileNames(in: root) == ["b.png"])
    }

    @Test("删除非法名称视为失败且不触碰其他文件")
    func removeInvalidNamesReportsFailure() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let parentFile = root.appendingPathComponent("victim.txt")
        try Data("keep".utf8).write(to: parentFile)
        let store = BlobStore(directory: root.appendingPathComponent("blobs"))

        let failed = store.remove(["../victim.txt", "ok.png"])

        #expect(failed == ["../victim.txt"])
        #expect(FileManager.default.fileExists(atPath: parentFile.path))
    }

    @Test(
        "非法名称：url(for:) 返回 nil，write 抛错",
        arguments: [
            "../x", ".hidden", "a/b", "", "..", ".", "a\\b", "名字.png", "a b.png", "a:b",
            String(repeating: "a", count: 256),
        ])
    func rejectsInvalidNames(_ name: String) throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root.appendingPathComponent("blobs"))
        #expect(store.url(for: name) == nil)
        #expect(throws: BlobStoreError.invalidName(name)) {
            try store.write(Data([0]), name: name)
        }
        // 父目录中不应出现任何被写入的文件
        #expect(TempDirectory.fileNames(in: root).isEmpty)
    }

    @Test(
        "合法名称",
        arguments: [
            "abc.png", "A-b_c.1.png", "0123456789abcdef.png", String(repeating: "a", count: 255),
        ])
    func acceptsValidNames(_ name: String) {
        let store = BlobStore(directory: URL(fileURLWithPath: "/tmp/blobs"))
        #expect(store.url(for: name)?.lastPathComponent == name)
    }

    @Test("removeAll(except:) 只删除未被引用的文件")
    func removeAllExcept() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root)
        for name in ["keep1.png", "keep2.png", "orphan1.png", "orphan2.png"] {
            try store.write(Data(name.utf8), name: name)
        }
        // 隐藏文件（如 .DS_Store）名称不合法，不应被清理
        try Data().write(to: root.appendingPathComponent(".DS_Store"))

        let removed = try store.removeAll(except: ["keep1.png", "keep2.png", "not-on-disk.png"])

        #expect(Set(removed) == ["orphan1.png", "orphan2.png"])
        #expect(TempDirectory.fileNames(in: root) == ["keep1.png", "keep2.png"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".DS_Store").path))
    }

    @Test("removeAll(except:) 在目录不存在时返回空")
    func removeAllWithoutDirectory() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root.appendingPathComponent("never-created"))
        #expect(try store.removeAll(except: []).isEmpty)
    }

    @Test("removeAll(except:) 全部被引用时不删除任何文件")
    func removeAllKeepsEverything() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root)
        try store.write(Data([1]), name: "a.png")
        #expect(try store.removeAll(except: ["a.png"]).isEmpty)
        #expect(TempDirectory.fileNames(in: root) == ["a.png"])
    }

    // MARK: - read / exists

    @Test("read 读回写入的数据")
    func readReturnsData() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root)
        let data = Data([0, 1, 2, 255])
        try store.write(data, name: "a.formats")
        #expect(try store.read("a.formats") == data)
    }

    @Test("read 非法名称抛 invalidName，文件不存在抛普通错误")
    func readErrors() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        try Data("secret".utf8).write(to: root.appendingPathComponent("secret.txt"))
        let store = BlobStore(directory: root.appendingPathComponent("blobs"))
        #expect(throws: BlobStoreError.invalidName("../secret.txt")) {
            try store.read("../secret.txt")
        }
        #expect {
            try store.read("missing.png")
        } throws: { error in
            !(error is BlobStoreError)
        }
    }

    @Test("exists 反映文件是否存在，非法名称返回 false")
    func existsChecks() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        try Data("x".utf8).write(to: root.appendingPathComponent("outside.png"))
        let store = BlobStore(directory: root.appendingPathComponent("blobs"))
        try store.write(Data([1]), name: "a.png")

        #expect(store.exists("a.png"))
        #expect(!store.exists("missing.png"))
        #expect(!store.exists("../outside.png"))
        #expect(!store.exists(""))
    }

    // MARK: - removeAll 不触碰子目录

    @Test("removeAll(except:) 只清理普通文件，保留子目录及其内容")
    func removeAllKeepsSubdirectories() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let store = BlobStore(directory: root)
        try store.write(Data([1]), name: "orphan.png")
        // 名称合法的子目录，甚至形似 blob 文件名
        for dirName in ["sub", "looks-like.png"] {
            let sub = root.appendingPathComponent(dirName, isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data("inner".utf8).write(to: sub.appendingPathComponent("inner.png"))
        }

        let removed = try store.removeAll(except: [])

        #expect(removed == ["orphan.png"])
        #expect(TempDirectory.fileNames(in: root) == ["sub", "looks-like.png"])
        #expect(TempDirectory.exists("sub/inner.png", in: root))
        #expect(TempDirectory.exists("looks-like.png/inner.png", in: root))
    }

    @Test("removeAll(except:) 不会删除符号链接指向的外部文件")
    func removeAllDoesNotFollowSymlinks() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }

        let outside = root.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)
        let blobDir = root.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: blobDir.appendingPathComponent("link.png"),
            withDestinationURL: outside
        )

        _ = try BlobStore(directory: blobDir).removeAll(except: [])

        #expect(try Data(contentsOf: outside) == Data("keep".utf8))
    }

    @Test("目录不可写时 remove 返回删除失败的文件名，文件保留")
    func removeReportsPermissionFailure() throws {
        let root = try TempDirectory.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            TempDirectory.remove(root)
        }

        let store = BlobStore(directory: root)
        try store.write(Data([1]), name: "locked.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        #expect(store.remove(["locked.png", "missing.png"]) == ["locked.png"])
        #expect(try store.removeAll(except: []).isEmpty)
        #expect(store.exists("locked.png"))
    }
}
