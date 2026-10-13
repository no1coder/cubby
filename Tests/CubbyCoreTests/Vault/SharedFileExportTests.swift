import Foundation
import Testing
@testable import CubbyCore

@Suite("SharedFileExport：交给其他应用的临时副本（E9）")
struct SharedFileExportTests {
    @Test("写到 <根>/<随机子目录>/<文件名>：目录 0700、文件 0600，同名不覆盖")
    func exportsPrivately() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let export = SharedFileExport(root: root.appendingPathComponent("Cubby-Shared"))

        let first = try export.export(Data("one".utf8), name: "Image 10×20", fileExtension: "png")
        let second = try export.export(Data("two".utf8), name: "Image 10×20", fileExtension: "png")

        #expect(first.lastPathComponent == "Image 10×20.png")
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("one".utf8))
        #expect(try TempDirectory.permissions(of: first) == 0o600)
        #expect(try TempDirectory.permissions(of: first.deletingLastPathComponent()) == 0o700)
        #expect(try TempDirectory.permissions(of: export.root) == 0o700)
        #expect(first.deletingLastPathComponent().deletingLastPathComponent().path == export.root.path)
    }

    @Test("文件名：去掉路径分隔、冒号与换行，不以点开头，空名用 Cubby，过长截断")
    func sanitizesNames() {
        #expect(SharedFileExport.fileName("../a/b:c\nd", fileExtension: "png") == "a b c d.png")
        #expect(SharedFileExport.fileName("  ...  ", fileExtension: "png") == "Cubby.png")
        #expect(SharedFileExport.fileName("x", fileExtension: "") == "x")
        #expect(SharedFileExport.fileName(String(repeating: "a", count: 300), fileExtension: "png").count == 124)
    }

    @Test("removeAll 删除全部副本；根目录不存在时不报错")
    func removesEverything() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let export = SharedFileExport(root: root.appendingPathComponent("Cubby-Shared"))
        try export.removeAll()
        let url = try export.export(Data("x".utf8), name: "x", fileExtension: "png")
        try export.removeAll()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: export.root.path))
        #expect(SharedFileExport.temporary.root.lastPathComponent == "Cubby-Shared")
    }
}
