import AppKit
import Foundation
import Testing
@testable import CubbyCore

/// 富文本格式 → 段落结构：HTML（XMLDocument 整理）优先，RTF 兜底
@Suite("ClipRichTextParser 富文本解析")
struct ClipRichTextParserTests {
    private func html(_ source: String) -> ClipRichDocument? {
        ClipRichTextParser.html(Data(source.utf8))
    }

    private func paragraphs(_ source: String) -> [ClipRichParagraph] {
        html(source)?.paragraphs ?? []
    }

    // MARK: - HTML

    @Test("标题、段落、粗体、链接、行内代码（Chrome 的 meta charset 也按 UTF-8 读）")
    func htmlBasics() throws {
        let result = paragraphs(
            """
            <meta charset='utf-8'><h1 style="color:red">Why local-first</h1>
            <p>When your data <b>lives</b> on the <a href="https://example.com/a">device</a>,
               usually <code>SQLite</code> &amp; more — 中文 📋</p>
            """)
        #expect(result.count == 2)
        #expect(result[0] == ClipRichParagraph(style: .heading(level: 1), runs: [ClipRichRun("Why local-first")]))
        #expect(result[1].style == .body)
        #expect(
            result[1].runs == [
                ClipRichRun("When your data "), ClipRichRun("lives", isBold: true), ClipRichRun(" on the "),
                ClipRichRun("device", link: URL(string: "https://example.com/a")), ClipRichRun(", usually "),
                ClipRichRun("SQLite", isCode: true), ClipRichRun(" & more — 中文 📋"),
            ])
    }

    @Test("没有字符集声明的中文不乱码")
    func htmlWithoutCharset() {
        #expect(paragraphs("<p>中文内容 <strong>粗体</strong></p>").map(\.text) == ["中文内容 粗体"])
    }

    @Test("列表：无序 / 有序（start）/ 嵌套层级与序号")
    func htmlLists() {
        let result = paragraphs(
            "<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul><ol start=\"3\"><li>three</li><li>four</li></ol>")
        #expect(
            result.map(\.style) == [
                .listItem(ordinal: nil, level: 1), .listItem(ordinal: nil, level: 1), .listItem(ordinal: nil, level: 2),
                .listItem(ordinal: 3, level: 1), .listItem(ordinal: 4, level: 1),
            ])
        #expect(result.map(\.text) == ["One", "Two", "Nested", "three", "four"])
    }

    @Test("pre 保留换行与空白、不翻译；br 分段；空白折叠；script / style / 注释忽略")
    func htmlPreformattedAndWhitespace() {
        let result = paragraphs(
            """
            <html><head><style>p{}</style><script>alert(1)</script></head><body><!--StartFragment-->
            <p>  Many    spaces
            and newlines  </p><pre>let x = 1
              let y = 2</pre><p>first<br>second</p><!--EndFragment--></body></html>
            """)
        #expect(result.map(\.text) == ["Many spaces and newlines", "let x = 1\n  let y = 2", "first", "second"])
        #expect(result[1].style == .preformatted)
        #expect(!result[1].isTranslatable)
    }

    @Test("Google 文档用 font-weight:normal 的 <b> 包住全文：按样式取消粗体；span 的 font-weight:700 算粗体")
    func htmlFontWeight() {
        let result = paragraphs(
            #"<b style="font-weight:normal;" id="docs-internal-guid-1"><p><span style="font-weight:700">Bold</span><span> normal</span></p></b>"#
        )
        #expect(result.first?.runs == [ClipRichRun("Bold", isBold: true), ClipRichRun(" normal")])
        #expect(
            paragraphs(#"<p><span style="font-weight: 400">x</span><span style="font-weight:bold">y</span></p>"#).first?
                .runs
                == [ClipRichRun("x"), ClipRichRun("y", isBold: true)])
    }

    @Test("只接受 http(s) 与 mailto 链接：javascript:、相对地址只保留文字")
    func htmlLinkSchemes() {
        let result = paragraphs(
            #"<p><a href="javascript:alert(1)">a</a> <a href="/relative">b</a> <a href="mailto:x@y.z">c</a></p>"#)
        #expect(result.first?.runs.compactMap(\.link) == [URL(string: "mailto:x@y.z")!])
        #expect(result.first?.text == "a b c")
    }

    @Test("不受信的有序列表起始序号（超大、负数、非数字）夹紧，不会溢出")
    func htmlListStartIsClamped() {
        let huge = paragraphs(#"<ol start="9223372036854775807"><li>a</li><li>b</li></ol>"#)
        #expect(
            huge.map(\.style) == [.listItem(ordinal: 1_000_000, level: 1), .listItem(ordinal: 1_000_001, level: 1)])
        #expect(paragraphs(#"<ol start="-5"><li>a</li></ol>"#).map(\.style) == [.listItem(ordinal: 0, level: 1)])
        #expect(paragraphs(#"<ol start="x"><li>a</li></ol>"#).map(\.style) == [.listItem(ordinal: 1, level: 1)])
    }

    @Test("RTF 列表的起始序号同样夹紧")
    func rtfListStartIsClamped() throws {
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = Int(Int32.max)
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        let text = NSMutableAttributedString(string: "Intro ", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        text.append(NSAttributedString(string: "bold\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
        text.append(
            NSAttributedString(
                string: "a\nb", attributes: [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: style]))
        let parsed = try #require(ClipRichTextParser.rtf(Self.rtf(text))).paragraphs
        let ordinals = parsed.compactMap { paragraph -> Int? in
            guard case .listItem(let ordinal, _) = paragraph.style else { return nil }
            return ordinal
        }
        #expect(ordinals.count == 2)
        #expect(ordinals.allSatisfy { $0 <= ClipRichTextParser.maxListOrdinal + 1 })
    }

    @Test("过深的嵌套不再展开；无法解析的数据为 nil")
    func htmlLimits() {
        let deep = String(repeating: "<span>", count: 300) + "deep" + String(repeating: "</span>", count: 300)
        #expect(paragraphs("<p>top</p>" + deep).map(\.text) == ["top"])
        #expect(ClipRichTextParser.html(Data())?.paragraphs.isEmpty == true)
        #expect(ClipRichTextParser.html(Data([0xFF, 0xFE, 0x00])) == nil)
    }

    // MARK: - RTF

    private static func rtf(_ text: NSAttributedString) -> Data {
        text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) ?? Data()
    }

    @Test("RTF：大字号粗体段落为标题，粗体、链接、等宽行内代码、列表（含序号）")
    func rtfStructure() throws {
        let body = NSFont.systemFont(ofSize: 12)
        let ordered = NSTextList(markerFormat: .decimal, options: 0)
        ordered.startingItemNumber = 3
        let listStyle = NSMutableParagraphStyle()
        listStyle.textLists = [ordered]
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]))
        text.append(NSAttributedString(string: "Sub\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]))
        text.append(NSAttributedString(string: "Use ", attributes: [.font: body]))
        text.append(
            NSAttributedString(
                string: "git", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]))
        text.append(NSAttributedString(string: " and ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "docs", attributes: [.font: body, .link: URL(string: "https://a.b")!]))
        text.append(NSAttributedString(string: " now\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
        text.append(NSAttributedString(string: "three\nfour\n", attributes: [.font: body, .paragraphStyle: listStyle]))
        text.append(
            NSAttributedString(
                string: "let x = 1", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]))

        let result = try #require(ClipRichTextParser.rtf(Self.rtf(text))).paragraphs

        #expect(
            result.map(\.style) == [
                .heading(level: 1), .heading(level: 2), .body, .listItem(ordinal: 3, level: 1),
                .listItem(ordinal: 4, level: 1), .preformatted,
            ])
        #expect(result[0].runs == [ClipRichRun("Title")])
        #expect(
            result[2].runs == [
                ClipRichRun("Use "), ClipRichRun("git", isCode: true), ClipRichRun(" and "),
                ClipRichRun("docs", link: URL(string: "https://a.b")), ClipRichRun(" now", isBold: true),
            ])
    }

    @Test("RTF：整篇等宽（终端、代码编辑器）不当作富文本；无法解析为 nil")
    func rtfMonospacedOrInvalid() {
        let terminal = NSAttributedString(
            string: "Deploy failed: the key was rejected.\nRotate it and retry.",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)])
        #expect(ClipRichTextParser.rtf(Self.rtf(terminal)) == nil)
        #expect(ClipRichTextParser.rtf(Data("not rtf".utf8)) == nil)
        #expect(ClipRichTextParser.rtf(Data()) == nil)
    }

    // MARK: - 选择

    @Test("优先 HTML；HTML 无法解析或没有文字时用 RTF；都没有时为 nil")
    func documentPrefersHTML() {
        let formats = Fixtures.richFormats(for: "Hello")
        #expect(
            ClipRichTextParser.document(from: formats)?.paragraphs.first?.runs == [ClipRichRun("Hello", isBold: true)])
        let rtfOnly = ["public.rtf": formats["public.rtf"] ?? Data(), "public.html": Data("<p> </p>".utf8)]
        #expect(ClipRichTextParser.document(from: rtfOnly)?.paragraphs.map(\.text) == ["Hello"])
        #expect(ClipRichTextParser.document(from: [:]) == nil)
        #expect(ClipRichTextParser.document(from: ["public.html": Data("<p> </p>".utf8)]) == nil)
    }

    // MARK: - 模型

    @Test("段落：相邻同样式合并、空文字丢弃；只含空白的段落丢弃；可翻译判定")
    func paragraphModel() {
        let paragraph = ClipRichParagraph(
            style: .body, runs: [ClipRichRun("a"), ClipRichRun(""), ClipRichRun("b"), ClipRichRun("c", isBold: true)])
        #expect(paragraph.runs == [ClipRichRun("ab"), ClipRichRun("c", isBold: true)])
        #expect(
            ClipRichDocument(paragraphs: [ClipRichParagraph(style: .body, runs: [ClipRichRun(" \n")])]).paragraphs
                .isEmpty)
        #expect(!ClipRichParagraph(style: .body, runs: [ClipRichRun("https://a.b")]).isTranslatable)
        #expect(
            !ClipRichParagraph(style: .body, runs: [ClipRichRun("run"), ClipRichRun("x", isCode: true)]).withRuns([
                ClipRichRun("42")
            ]).isTranslatable)
        #expect(
            !ClipRichParagraph(style: .body, runs: [ClipRichRun("code", isCode: true), ClipRichRun(" 1")])
                .isTranslatable)
        #expect(!ClipRichParagraph(style: .preformatted, runs: [ClipRichRun("text")]).isTranslatable)
        #expect(ClipRichParagraph(style: .heading(level: 2), runs: [ClipRichRun("Title")]).isTranslatable)
        #expect(
            !ClipRichDocument(paragraphs: [ClipRichParagraph(style: .body, runs: [ClipRichRun("plain")])]).hasStructure)
    }
}
