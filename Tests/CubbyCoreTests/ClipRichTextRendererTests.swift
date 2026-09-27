import Foundation
import Testing
@testable import CubbyCore

/// 段落结构 → AttributedString / 纯文本 / HTML / RTF
@Suite("ClipRichTextRenderer 富文本输出")
struct ClipRichTextRendererTests {
    private let link = URL(string: "https://example.com/guide")!

    private var sample: ClipRichDocument {
        ClipRichDocument(paragraphs: [
            ClipRichParagraph(style: .heading(level: 1), runs: [ClipRichRun("Title <1>")]),
            ClipRichParagraph(
                style: .body,
                runs: [
                    ClipRichRun("Read "), ClipRichRun("this", isBold: true), ClipRichRun(" "),
                    ClipRichRun("guide", link: link), ClipRichRun(" & "), ClipRichRun("a<b", isCode: true),
                ]),
            ClipRichParagraph(style: .listItem(ordinal: nil, level: 1), runs: [ClipRichRun("One")]),
            ClipRichParagraph(style: .listItem(ordinal: nil, level: 2), runs: [ClipRichRun("Nested")]),
            ClipRichParagraph(style: .listItem(ordinal: nil, level: 1), runs: [ClipRichRun("Two")]),
            ClipRichParagraph(style: .listItem(ordinal: 3, level: 1), runs: [ClipRichRun("Three")]),
            ClipRichParagraph(style: .listItem(ordinal: 4, level: 1), runs: [ClipRichRun("Four")]),
            ClipRichParagraph(style: .preformatted, runs: [ClipRichRun("let x = 1\nlet y = 2")]),
        ])
    }

    @Test("AttributedString：段落样式写入 presentationIntent 并可读回，行内样式写入 inlinePresentationIntent 与 link")
    func attributedParagraphs() {
        for (index, paragraph) in sample.paragraphs.enumerated() {
            let attributed = ClipRichTextRenderer.attributed(paragraph, identity: index + 1)
            #expect(ClipRichTextRenderer.paragraphStyle(of: attributed) == paragraph.style, "\(index)")
            #expect(String(attributed.characters) == paragraph.text)
        }
        let body = ClipRichTextRenderer.attributed(sample.paragraphs[1])
        let runs = Array(body.runs)
        #expect(runs.map(\.inlinePresentationIntent) == [nil, .stronglyEmphasized, nil, nil, nil, .code])
        #expect(runs.map(\.link) == [nil, nil, nil, link, nil, nil])
        #expect(ClipRichTextRenderer.paragraphStyle(of: AttributedString("plain")) == .body)
        let deep = ClipRichParagraph(style: .listItem(ordinal: nil, level: 12), runs: [ClipRichRun("x")])
        #expect(
            ClipRichTextRenderer.paragraphStyle(of: ClipRichTextRenderer.attributed(deep))
                == .listItem(ordinal: nil, level: 8))
    }

    @Test("整篇 AttributedString：段落以换行分隔")
    func attributedDocument() {
        let attributed = ClipRichTextRenderer.attributed(sample)
        #expect(String(attributed.characters) == sample.paragraphs.map(\.text).joined(separator: "\n"))
        #expect(ClipRichTextRenderer.paragraphStyle(of: attributed) == .heading(level: 1))
    }

    @Test("纯文本：段落间空一行，相邻列表项只换行，列表项带前缀、按层级缩进")
    func plainText() {
        #expect(
            ClipRichTextRenderer.plainText(sample) == """
                Title <1>

                Read this guide & a<b

                \u{2022} One
                \t\u{2022} Nested
                \u{2022} Two
                3. Three
                4. Four

                let x = 1
                let y = 2
                """)
    }
}
