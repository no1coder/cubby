import AppKit
import Testing
@testable import CubbyCore

@Suite("RichTextExport 富文本译文转 AppKit 属性")
struct RichTextExportTests {
    /// 按段落意图拼出一个块（与 Foundation 解析 Markdown 的表示一致：块之间没有换行字符）
    private func block(_ text: String, _ intent: PresentationIntent) -> AttributedString {
        var block = AttributedString(text)
        block.presentationIntent = intent
        return block
    }

    private func paragraph(_ text: String, identity: Int) -> AttributedString {
        block(text, PresentationIntent(.paragraph, identity: identity))
    }

    private func bold(at index: Int, in string: NSAttributedString) -> Bool {
        let font = string.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.bold) == true
    }

    @Test("没有段落意图的纯文本原样输出，使用正文字号")
    func plainTextStaysAsIs() {
        let result = RichTextExport.appKitString(from: AttributedString("Line one\nLine two"))
        #expect(result.string == "Line one\nLine two")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == RichTextExport.bodyFontSize)
    }

    @Test("块之间补换行；已以换行结尾的块不重复补")
    func blocksAreSeparatedByNewlines() {
        var text = paragraph("First", identity: 1)
        text.append(paragraph("Second", identity: 2))
        #expect(RichTextExport.appKitString(from: text).string == "First\nSecond")

        var withNewline = paragraph("First\n", identity: 1)
        withNewline.append(paragraph("Second", identity: 2))
        #expect(RichTextExport.appKitString(from: withNewline).string == "First\nSecond")
    }

    @Test("标题加粗并放大，级别越高字号越大")
    func headingsAreBoldAndLarger() {
        var text = block("Big", PresentationIntent(.header(level: 1), identity: 1))
        text.append(block("Small", PresentationIntent(.header(level: 3), identity: 2)))
        text.append(paragraph("Body", identity: 3))
        let result = RichTextExport.appKitString(from: text)
        #expect(result.string == "Big\nSmall\nBody")
        let big = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let small = result.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        let body = result.attribute(.font, at: 10, effectiveRange: nil) as? NSFont
        #expect(bold(at: 0, in: result))
        #expect(bold(at: 4, in: result))
        #expect(!bold(at: 10, in: result))
        #expect((big?.pointSize ?? 0) > (small?.pointSize ?? 0))
        #expect((small?.pointSize ?? 0) > (body?.pointSize ?? 0))
    }

    @Test("无序列表项加「• 」，有序列表项加序号")
    func listItemsGetMarkers() {
        let bullets = PresentationIntent(.unorderedList, identity: 10)
        let numbers = PresentationIntent(.orderedList, identity: 20)
        var text = block("Apples", PresentationIntent(.listItem(ordinal: 1), identity: 11, parent: bullets))
        text.append(block("Pears", PresentationIntent(.listItem(ordinal: 2), identity: 12, parent: bullets)))
        text.append(block("Wash", PresentationIntent(.listItem(ordinal: 1), identity: 21, parent: numbers)))
        text.append(block("Dry", PresentationIntent(.listItem(ordinal: 2), identity: 22, parent: numbers)))
        #expect(RichTextExport.appKitString(from: text).string == "• Apples\n• Pears\n1. Wash\n2. Dry")
    }

    @Test("有序列表里嵌套的无序项用项目符号：只看紧邻的父级列表")
    func nestedListUsesImmediateParent() {
        let numbers = PresentationIntent(.orderedList, identity: 20)
        let outer = PresentationIntent(.listItem(ordinal: 1), identity: 21, parent: numbers)
        let bullets = PresentationIntent(.unorderedList, identity: 30, parent: outer)
        var text = block("Step", outer)
        text.append(block("Detail", PresentationIntent(.listItem(ordinal: 1), identity: 31, parent: bullets)))
        #expect(RichTextExport.appKitString(from: text).string == "1. Step\n• Detail")
    }

    @Test("代码块整块等宽")
    func codeBlockIsMonospaced() {
        let text = block("let x = 1", PresentationIntent(.codeBlock(languageHint: "swift"), identity: 1))
        let result = RichTextExport.appKitString(from: text)
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test("已带项目符号的列表项不重复加")
    func existingBulletIsKept() {
        let list = PresentationIntent(.unorderedList, identity: 10)
        let text = block("• Done", PresentationIntent(.listItem(ordinal: 1), identity: 11, parent: list))
        #expect(RichTextExport.appKitString(from: text).string == "• Done")
    }

    @Test("行内样式：粗体、斜体、行内代码、删除线与链接")
    func inlineStyles() throws {
        var text = AttributedString("a")
        var strong = AttributedString("b")
        strong.inlinePresentationIntent = .stronglyEmphasized
        var emphasis = AttributedString("c")
        emphasis.inlinePresentationIntent = .emphasized
        var code = AttributedString("d")
        code.inlinePresentationIntent = .code
        var struck = AttributedString("e")
        struck.inlinePresentationIntent = .strikethrough
        var link = AttributedString("f")
        link.link = URL(string: "https://example.com/guide")
        for part in [strong, emphasis, code, struck, link] {
            text.append(part)
        }

        let result = RichTextExport.appKitString(from: text)
        #expect(result.string == "abcdef")
        #expect(!bold(at: 0, in: result))
        #expect(bold(at: 1, in: result))
        let italic = result.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(italic?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        let mono = result.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect(mono?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect(result.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int == 1)
        let url = try #require(result.attribute(.link, at: 5, effectiveRange: nil) as? URL)
        #expect(url.absoluteString == "https://example.com/guide")
    }

    @Test("RTF 与 HTML 数据可生成且可读回文字")
    func exportsData() throws {
        var text = block("Title", PresentationIntent(.header(level: 2), identity: 1))
        text.append(paragraph("Body", identity: 2))
        let data = try #require(RichTextExport.data(from: text))
        let rtf = try #require(NSAttributedString(rtf: data.rtf, documentAttributes: nil))
        #expect(rtf.string == "Title\nBody")
        #expect(String(decoding: data.html, as: UTF8.self).contains("Title"))
    }

    @Test("空字符串也能导出")
    func emptyExport() {
        #expect(RichTextExport.appKitString(from: AttributedString()).length == 0)
        #expect(RichTextExport.data(from: AttributedString()) != nil)
    }
}
