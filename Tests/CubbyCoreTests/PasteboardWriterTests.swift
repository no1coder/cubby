import AppKit
import Testing
@testable import CubbyCore

@Suite("PasteboardWriter 写回剪贴板", .serializedPasteboardAccess, .timeLimit(.minutes(1)))
struct PasteboardWriterTests {
    private func types(of pasteboard: NSPasteboard) -> Set<NSPasteboard.PasteboardType> {
        Set(pasteboard.types ?? [])
    }

    @Test("写入文本：内容可读回，带自身标记且应被监听忽略")
    func writesText() throws {
        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(Fixtures.text("hello 📋"), imageURL: nil, to: pasteboard)

            #expect(pasteboard.string(forType: .string) == "hello 📋")
            #expect(types(of: pasteboard).contains(PasteboardReader.markerType))
            #expect(PasteboardReader.shouldIgnore(pasteboard))
            #expect(PasteboardReader.read(from: pasteboard) == .text("hello 📋"))
        }
    }

    @Test("写入会替换剪贴板原有内容")
    func writeReplacesExistingContent() throws {
        try withTemporaryPasteboard { pasteboard in
            pasteboard.setData(ImageFixtures.png(width: 1, height: 1), forType: .png)
            try PasteboardWriter.write(Fixtures.text("new"), imageURL: nil, to: pasteboard)
            #expect(!types(of: pasteboard).contains(.png))
        }
    }

    @Test("写入图片：同时提供 PNG 与 TIFF，并带标记")
    func writesImage() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let png = ImageFixtures.png(width: 3, height: 2)
        let url = dir.appendingPathComponent("img.png")
        try png.write(to: url)

        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(Fixtures.image(name: "img.png"), imageURL: url, to: pasteboard)

            #expect(pasteboard.data(forType: .png) == png)
            let tiff = try #require(pasteboard.data(forType: .tiff))
            #expect(NSBitmapImageRep(data: tiff)?.pixelsWide == 3)
            #expect(PasteboardReader.shouldIgnore(pasteboard))
        }
    }

    @Test("图片 URL 为 nil、不存在或内容无效时抛 imageUnavailable，且不清空剪贴板")
    func imageUnavailable() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let invalid = dir.appendingPathComponent("broken.png")
        try Data("not png".utf8).write(to: invalid)
        let candidates: [URL?] = [nil, dir.appendingPathComponent("missing.png"), invalid]

        for candidate in candidates {
            withTemporaryPasteboard { pasteboard in
                pasteboard.setString("previous", forType: .string)
                #expect(throws: PasteboardWriteError.imageUnavailable) {
                    try PasteboardWriter.write(Fixtures.image(name: "x.png"), imageURL: candidate, to: pasteboard)
                }
                #expect(pasteboard.string(forType: .string) == "previous")
            }
        }
    }

    @Test("写入文件：只写入仍存在的文件，并带标记")
    func writesExistingFilesOnly() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let existing = dir.appendingPathComponent("exists.txt")
        try Data("x".utf8).write(to: existing)
        let missing = dir.appendingPathComponent("gone.txt")
        let item = Fixtures.files([existing.path, missing.path])

        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(item, imageURL: nil, to: pasteboard)

            guard case .files(let urls) = PasteboardReader.read(from: pasteboard) else {
                Issue.record("应写入文件")
                return
            }
            #expect(urls.map { $0.resolvingSymlinksInPath().path } == [existing.resolvingSymlinksInPath().path])
            #expect(types(of: pasteboard).contains(PasteboardReader.markerType))
            #expect(PasteboardReader.shouldIgnore(pasteboard))
        }
    }

    @Test("写入多个文件时全部可读回")
    func writesMultipleFiles() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let urls = try ["a.txt", "b.txt", "c.txt"].map { name in
            let url = dir.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }

        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(Fixtures.files(urls.map(\.path)), imageURL: nil, to: pasteboard)
            guard case .files(let read) = PasteboardReader.read(from: pasteboard) else {
                Issue.record("应写入文件")
                return
            }
            #expect(read.map(\.lastPathComponent) == ["a.txt", "b.txt", "c.txt"])
            #expect(PasteboardReader.shouldIgnore(pasteboard))
        }
    }

    @Test("文件全部不存在时抛 filesMissing，且不清空剪贴板")
    func filesMissing() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let item = Fixtures.files([dir.appendingPathComponent("a").path, dir.appendingPathComponent("b").path])

        withTemporaryPasteboard { pasteboard in
            pasteboard.setString("previous", forType: .string)
            #expect(throws: PasteboardWriteError.filesMissing) {
                try PasteboardWriter.write(item, imageURL: nil, to: pasteboard)
            }
            #expect(pasteboard.string(forType: .string) == "previous")
        }
    }

    @Test("空文件列表抛 filesMissing")
    func emptyFileList() {
        withTemporaryPasteboard { pasteboard in
            #expect(throws: PasteboardWriteError.filesMissing) {
                try PasteboardWriter.write(Fixtures.files([]), imageURL: nil, to: pasteboard)
            }
        }
    }
}
