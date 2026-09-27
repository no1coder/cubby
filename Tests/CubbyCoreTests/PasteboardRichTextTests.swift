import AppKit
import Testing
@testable import CubbyCore

@Suite("剪贴板富文本读写往返与大小限制")
struct PasteboardRichTextTests {
    private let rtfType = NSPasteboard.PasteboardType("public.rtf")
    private let htmlType = NSPasteboard.PasteboardType("public.html")

    // MARK: - 读取

    @Test(
        "纯文本 + RTF / HTML 读取为 richText",
        arguments: [
            ["public.rtf"], ["public.html"], ["public.rtf", "public.html"],
        ])
    func readsRichText(_ types: [String]) {
        withTemporaryPasteboard { pasteboard in
            let all = Fixtures.richFormats(for: "粗体")
            let formats = all.filter { types.contains($0.key) }
            let item = NSPasteboardItem()
            item.setString("粗体", forType: .string)
            formats.forEach { item.setData($0.value, forType: NSPasteboard.PasteboardType($0.key)) }
            pasteboard.writeObjects([item])

            #expect(PasteboardReader.read(from: pasteboard) == .richText("粗体", formats: formats))
        }
    }

    @Test("不支持的格式（如 webarchive）不会被采集")
    func ignoresUnsupportedFormats() {
        withTemporaryPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setString("text", forType: .string)
            item.setData(Data("archive".utf8), forType: NSPasteboard.PasteboardType("com.apple.webarchive"))
            pasteboard.writeObjects([item])

            #expect(PasteboardReader.read(from: pasteboard) == .text("text"))
        }
    }

    @Test("空的格式数据被跳过，退化为纯文本")
    func emptyFormatDataIsSkipped() {
        withTemporaryPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setString("text", forType: .string)
            item.setData(Data(), forType: rtfType)
            pasteboard.writeObjects([item])

            #expect(PasteboardReader.read(from: pasteboard) == .text("text"))
        }
    }

    @Test("单种格式超过 maxFormatBytes 时仅丢弃该格式，恰好等于上限时保留")
    func oversizedFormatIsDropped() {
        withTemporaryPasteboard { pasteboard in
            let exact = Data(repeating: 0x41, count: CaptureLimits.maxFormatBytes)
            let over = Data(repeating: 0x42, count: CaptureLimits.maxFormatBytes + 1)
            let item = NSPasteboardItem()
            item.setString("text", forType: .string)
            item.setData(exact, forType: htmlType)
            item.setData(over, forType: rtfType)
            pasteboard.writeObjects([item])

            #expect(PasteboardReader.read(from: pasteboard) == .richText("text", formats: ["public.html": exact]))
        }
    }

    @Test("只有 RTF 时系统会派生出纯文本，按富文本记录")
    func rtfOnlyDerivesPlainText() {
        withTemporaryPasteboard { pasteboard in
            let rtf = Fixtures.richFormats(for: "仅 RTF")["public.rtf"]
            pasteboard.setData(rtf, forType: rtfType)
            #expect(
                PasteboardReader.read(from: pasteboard) == .richText("仅 RTF", formats: ["public.rtf": rtf ?? Data()]))
        }
    }

    @Test("只有 HTML 没有纯文本时不记录（系统不从 HTML 派生纯文本）")
    func htmlWithoutPlainTextIsIgnored() {
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(Data("<b>x</b>".utf8), forType: htmlType)
            #expect(PasteboardReader.read(from: pasteboard) == nil)
        }
    }

    @Test("纯文本为空白时即使有格式也不记录")
    func blankTextWithFormatsIsIgnored() {
        withTemporaryPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setString("  \n", forType: .string)
            item.setData(Data("<p></p>".utf8), forType: htmlType)
            pasteboard.writeObjects([item])
            #expect(PasteboardReader.read(from: pasteboard) == nil)
        }
    }

    @Test("文件优先于富文本")
    func filesTakePriorityOverRichText() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)

        withTemporaryPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setString(file.absoluteString, forType: .fileURL)
            item.setString("a.txt", forType: .string)
            item.setData(Data("<b>a</b>".utf8), forType: htmlType)
            pasteboard.writeObjects([item])

            guard case .files = PasteboardReader.read(from: pasteboard) else {
                Issue.record("应优先读取为文件")
                return
            }
        }
    }

    // MARK: - 写入

    @Test("写入文本条目时同时写入各格式，并可原样读回为 richText")
    func writerRoundTrip() throws {
        let formats = Fixtures.richFormats(for: "往返 📋")
        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(Fixtures.text("往返 📋"), imageURL: nil, formats: formats, to: pasteboard)

            #expect(pasteboard.string(forType: .string) == "往返 📋")
            #expect(pasteboard.data(forType: rtfType) == formats["public.rtf"])
            #expect(pasteboard.data(forType: htmlType) == formats["public.html"])
            #expect(PasteboardReader.shouldIgnore(pasteboard))
            #expect(PasteboardReader.read(from: pasteboard) == .richText("往返 📋", formats: formats))
        }
    }

    @Test("写回的 RTF 可被其他应用解析出原样式（加粗）")
    func writtenRTFKeepsStyle() throws {
        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(
                Fixtures.text("加粗"), imageURL: nil, formats: Fixtures.richFormats(for: "加粗"), to: pasteboard
            )
            let rtf = try #require(pasteboard.data(forType: rtfType))
            let attributed = try NSAttributedString(
                data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
            )
            let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(attributed.string == "加粗")
            #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        }
    }

    @Test("formats 为空时只写纯文本")
    func writerWithoutFormats() throws {
        try withTemporaryPasteboard { pasteboard in
            try PasteboardWriter.write(Fixtures.text("plain"), imageURL: nil, to: pasteboard)
            #expect(pasteboard.data(forType: rtfType) == nil)
            #expect(pasteboard.data(forType: htmlType) == nil)
            #expect(PasteboardReader.read(from: pasteboard) == .text("plain"))
        }
    }

    @Test("非文本条目忽略 formats 参数")
    func formatsIgnoredForFiles() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let file = dir.appendingPathComponent("f.txt")
        try Data("f".utf8).write(to: file)

        try withTemporaryPasteboard { pasteboard in
            let formats = ["public.html": Data("<b>x</b>".utf8)]
            try PasteboardWriter.write(Fixtures.files([file.path]), imageURL: nil, formats: formats, to: pasteboard)
            #expect(pasteboard.data(forType: htmlType) == nil)
        }
    }

    @MainActor
    @Test("端到端：读取 → ClipStore 记录 → 取回格式 → 写回剪贴板，内容一致")
    func endToEndThroughStore() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let formats = Fixtures.richFormats(for: "端到端")
        let store = StoreFactory.make(dir: dir)

        let content: ClipContent? = withTemporaryPasteboard { source in
            let item = NSPasteboardItem()
            item.setString("端到端", forType: .string)
            formats.forEach { item.setData($0.value, forType: NSPasteboard.PasteboardType($0.key)) }
            source.writeObjects([item])
            return PasteboardReader.read(from: source)
        }
        let read = try #require(content)
        let recorded = try #require(store.record(read, source: nil))

        try withTemporaryPasteboard { target in
            try PasteboardWriter.write(recorded, imageURL: nil, formats: store.formats(for: recorded), to: target)
            #expect(PasteboardReader.read(from: target) == .richText("端到端", formats: formats))
        }
    }

    // MARK: - TIFF 大小限制

    @Test("TIFF 超过 maxTIFFBytes 时在解码前被拒绝，未超过时正常转换")
    func oversizedTIFFIsRejected() {
        // 在合法 TIFF 后追加填充字节：仍可解码，但体积可控
        let tiff = ImageFixtures.tiff(width: 2, height: 2)
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(tiff + Data(count: 1024), forType: .tiff)
            guard case .image(_, 2, 2) = PasteboardReader.read(from: pasteboard) else {
                Issue.record("带少量填充的 TIFF 应可正常读取")
                return
            }

            pasteboard.clearContents()
            pasteboard.setData(tiff + Data(count: CaptureLimits.maxTIFFBytes - tiff.count + 1), forType: .tiff)
            #expect(PasteboardReader.read(from: pasteboard) == nil)
        }
    }
}
