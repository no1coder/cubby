import AppKit
import Testing
@testable import CubbyCore

@Suite("PasteboardWriter 写入译文", .serializedPasteboardAccess, .timeLimit(.minutes(1)))
struct PasteboardWriterTranslationTests {
    private func types(of pasteboard: NSPasteboard) -> Set<NSPasteboard.PasteboardType> {
        Set(pasteboard.types ?? [])
    }

    @Test("纯文本译文：替换原有内容，只有纯文本与自身标记，监听器会忽略")
    func writesPlainText() throws {
        try withTemporaryPasteboard { pasteboard in
            pasteboard.setData(ImageFixtures.png(width: 1, height: 1), forType: .png)
            try PasteboardWriter.write(text: "你好，世界", to: pasteboard)

            #expect(pasteboard.string(forType: .string) == "你好，世界")
            #expect(!types(of: pasteboard).contains(.png))
            #expect(!types(of: pasteboard).contains(.rtf))
            #expect(PasteboardReader.shouldIgnore(pasteboard))
        }
    }

    @Test("富文本译文：同时写入 RTF、HTML 与纯文本，并带标记")
    func writesRichText() throws {
        var rich = AttributedString("Hello ")
        var bold = AttributedString("world")
        bold.inlinePresentationIntent = .stronglyEmphasized
        rich.append(bold)

        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(richText: rich, plainText: "Hello world", to: pasteboard)

            #expect(pasteboard.string(forType: .string) == "Hello world")
            let rtf = try #require(pasteboard.data(forType: .rtf))
            let html = try #require(pasteboard.data(forType: .html))
            #expect(String(decoding: html, as: UTF8.self).contains("world"))
            let decoded = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))
            #expect(decoded.string == "Hello world")
            let font = decoded.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
            #expect(PasteboardReader.shouldIgnore(pasteboard))
        }
    }

    @Test("富文本的纯文本以调用方给出的为准（与缓存拼接规则一致）")
    func richTextKeepsGivenPlainText() throws {
        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(
                richText: AttributedString("Title"), plainText: "Title\n\n", to: pasteboard)
            #expect(pasteboard.string(forType: .string) == "Title\n\n")
        }
    }

    @Test("译后图片：写入 PNG（TIFF 按需提供）并带标记")
    func writesTranslatedImage() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let png = ImageFixtures.png(width: 4, height: 3)
        let url = dir.appendingPathComponent("translated.png")
        try png.write(to: url)

        try withTemporaryPasteboard { pasteboard in
            pasteboard.setString("previous", forType: .string)
            try PasteboardWriter.write(pngAt: url, to: pasteboard)

            #expect(pasteboard.data(forType: .png) == png)
            #expect(pasteboard.string(forType: .string) == nil)
            let tiff = try #require(pasteboard.data(forType: .tiff))
            #expect(NSBitmapImageRep(data: tiff)?.pixelsWide == 4)
            #expect(PasteboardReader.shouldIgnore(pasteboard))
        }
    }

    @Test("译后图片缺失或无效时抛 imageUnavailable，且不清空剪贴板")
    func translatedImageUnavailable() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let invalid = dir.appendingPathComponent("broken.png")
        try Data("not png".utf8).write(to: invalid)

        for candidate in [dir.appendingPathComponent("missing.png"), invalid] {
            withTemporaryPasteboard { pasteboard in
                pasteboard.setString("previous", forType: .string)
                #expect(throws: PasteboardWriteError.imageUnavailable) {
                    try PasteboardWriter.write(pngAt: candidate, to: pasteboard)
                }
                #expect(pasteboard.string(forType: .string) == "previous")
            }
        }
    }
}
