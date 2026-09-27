import Foundation
import Testing
@testable import CubbyCore

/// 纯文本分段器（docs/CLIP-TRANSLATION-DESIGN.md §2.1）：join(原文, 各段原文) == 原文 恒等，
/// 空行 / 硬换行 / 列表 / CJK / CRLF / 末尾换行，代码与网址行原样保留
@Suite("ClipTextSegmenter 纯文本分段")
struct ClipTextSegmenterTests {
    private func sources(_ text: String) -> [String] {
        ClipTextSegmenter.segments(of: text).map(\.source)
    }

    private func translatable(_ text: String) -> [String] {
        ClipTextSegmenter.segments(of: text).filter(\.isTranslatable).map(\.source)
    }

    private func identityHolds(_ text: String) -> Bool {
        let segments = ClipTextSegmenter.segments(of: text)
        return ClipTextSegmenter.join(original: text, segments: segments.map(\.original)) == text
            && ClipTextSegmenter.join(original: text, segments: segments.map { _ in nil }) == text
            && ClipTextSegmenter.join(original: text, segments: []) == text
    }

    static let corpus: [String] = [
        "", "   ", "\n\n\n", "Hello", "Hello\n", "\nHello\n\n", "Para one.\n\nPara two.", "a\r\nb\r\n\r\nc\r\n",
        "- Buy milk\n- Call mom\n", "  1. First\n  2) Second\n> quoted line\n## Heading\n", "Hello   \n\tWorld  ",
        "```swift\nlet x = 1\n\nprint(x)\n```\nAfter the fence", "https://example.com\n12:30\n2026-09-27\n---",
        "\u{8FD9}\u{662F}\u{4E2D}\u{6587}\u{3002}\n\n\u{7B2C}\u{4E8C}\u{6BB5}", "\u{1F600} emoji line\n\u{2022} bullet",
        "Line with trailing CR\r", "*\n-\n1.\n#", "   indented paragraph that goes on\n   and continues here",
    ]

    // MARK: - 恒等

    @Test("join(原文, 各段原文) == 原文；全部为 nil、空数组时也原样返回", arguments: corpus)
    func identity(_ text: String) {
        #expect(identityHolds(text))
    }

    @Test("随机文本（固定种子）：恒等始终成立，各段范围不重叠且按顺序")
    func randomizedIdentity() {
        var random = SeededGenerator(seed: 20_260_927)
        let pieces = [
            "Hello world", "- item", "1. step", "> quote", "## Title", "let x = 1;", "https://a.b/c", "42", "   ",
            "", "\u{4E2D}\u{6587}\u{6BB5}\u{843D}", "```", "word-", "tail.", "\t indented", "\u{1F44D}", "}",
            String(repeating: "long wrapped line ", count: 3),
        ]
        let separators = ["\n", "\r\n", "\n\n", " "]
        for _ in 0..<400 {
            let count = Int.random(in: 0...12, using: &random)
            let text = (0..<count).map { _ in
                (pieces.randomElement(using: &random) ?? "") + (separators.randomElement(using: &random) ?? "\n")
            }.joined()
            #expect(identityHolds(text), "\(text.debugDescription)")
            let segments = ClipTextSegmenter.segments(of: text)
            let ordered = zip(segments, segments.dropFirst()).allSatisfy { $0.range.upperBound <= $1.range.lowerBound }
            #expect(ordered)
            #expect(segments.map(\.index) == Array(segments.indices))
        }
    }

    // MARK: - 分段规则

    @Test("空行分段；空文本、只有空白时没有段")
    func blankLinesSeparate() {
        #expect(sources("Para one.\n\nPara two.") == ["Para one.", "Para two."])
        #expect(ClipTextSegmenter.segments(of: "").isEmpty)
        #expect(ClipTextSegmenter.segments(of: " \n\t\n").isEmpty)
    }

    @Test("硬换行的段落合并为一段：送翻译时以空格相连，译文替换整段")
    func hardWrappedParagraphMerges() {
        let text = """
            The quarterly report is due next Friday and we
            need everyone to send their numbers by Wednesday
            so that there is enough time to review them all.

            Thanks!
            """
        #expect(
            translatable(text) == [
                "The quarterly report is due next Friday and we need everyone to send their numbers by Wednesday "
                    + "so that there is enough time to review them all.",
                "Thanks!",
            ])
        #expect(ClipTextSegmenter.join(original: text, segments: ["A", "B"]) == "A\n\nB")
    }

    @Test("中文硬换行直接相连，不加空格")
    func cjkHardWrap() {
        let text = """
            这是一段从文档里复制出来的中文文字，每一行都在
            固定的宽度处被截断，中间没有空行也没有标点结尾
            所以应该被合并成一段来翻译。
            """
        #expect(translatable(text) == ["这是一段从文档里复制出来的中文文字，每一行都在固定的宽度处被截断，中间没有空行也没有标点结尾所以应该被合并成一段来翻译。"])
    }

    @Test("短行、句末标点结尾的行、宽度相差大的行不合并，逐行成段")
    func shortOrSentenceLinesStaySeparate() {
        #expect(
            sources("Meeting moved to 3 pm.\nPlease bring the slides.") == [
                "Meeting moved to 3 pm.", "Please bring the slides.",
            ])
        let sentences = """
            This is the first complete sentence of this note.
            This is the second complete sentence of the note.
            And the third one is here.
            """
        #expect(sources(sentences).count == 3)
        let ragged =
            "A fairly long first line that keeps going on and on\nshort\nanother fairly long line that keeps going on"
        #expect(sources(ragged).count == 3)
        #expect(ClipTextSegmenter.join(original: ragged, segments: ["1", "2", "3"]) == "1\n2\n3")
    }

    @Test("列表、引用、标题标记与缩进留在原文里，不送翻译；列表项各自成段、不与相邻行合并")
    func markersStayInOriginal() {
        let text =
            "- Buy milk\n  * Call mom\n1. First step\n2) Second step\n> Quoted text\n## Title here\n\u{2022} Bullet"
        #expect(
            sources(text) == [
                "Buy milk", "Call mom", "First step", "Second step", "Quoted text", "Title here", "Bullet",
            ])
        #expect(
            ClipTextSegmenter.join(original: text, segments: ["A", "B", "C", "D", "E", "F", "G"])
                == "- A\n  * B\n1. C\n2) D\n> E\n## F\n\u{2022} G")
    }

    @Test("不是标记的行首符号：-5、**粗体**、#hashtag、1.5 百万")
    func falseMarkers() {
        #expect(sources("-5 degrees today") == ["-5 degrees today"])
        #expect(sources("**Bold** start") == ["**Bold** start"])
        #expect(sources("#hashtag trending") == ["#hashtag trending"])
        #expect(sources("1.5 million users") == ["1.5 million users"])
        #expect(sources("1234. Too many digits") == ["1234. Too many digits"])
        #expect(sources("####### seven hashes") == ["####### seven hashes"])
    }

    @Test("缩进与行尾空白保留在原文里")
    func whitespaceStaysInOriginal() {
        let text = "    Indented text\t\nHello   \n"
        #expect(sources(text) == ["Indented text", "Hello"])
        #expect(ClipTextSegmenter.join(original: text, segments: ["A", "B"]) == "    A\t\nB   \n")
    }

    @Test("CRLF 与末尾换行原样保留")
    func crlfAndTrailingNewline() {
        let text = "Line one\r\nLine two\r\n\r\nLine three\r\n"
        #expect(sources(text) == ["Line one", "Line two", "Line three"])
        #expect(ClipTextSegmenter.join(original: text, segments: ["1", "2", "3"]) == "1\r\n2\r\n\r\n3\r\n")
    }

    // MARK: - 原样保留

    @Test("网址、没有字母的行、单行代码原样保留、不送翻译")
    func verbatimLines() {
        let text =
            "See below\nhttps://example.com/a?b=1\nwww.example.com\n12:30\n2026-09-27\n---\nlet x = 1;\n}\n// comment\nEnd"
        let segments = ClipTextSegmenter.segments(of: text)
        #expect(segments.filter(\.isTranslatable).map(\.source) == ["See below", "End"])
        #expect(segments.filter { !$0.isTranslatable }.count == 1)
        #expect(
            ClipTextSegmenter.join(original: text, segments: segments.map { _ in "X" }) == "X\n"
                + text.dropFirst(10).dropLast(3) + "X")
    }

    @Test("代码围栏内（含空行）原样保留；整块像代码的段原样保留")
    func codeBlocks() {
        let fenced = "Intro text\n```\nfunc a() {\n\n  return 1\n}\n```\nOutro text"
        #expect(translatable(fenced) == ["Intro text", "Outro text"])
        #expect(ClipTextSegmenter.segments(of: fenced).count == 3)
        #expect(
            ClipTextSegmenter.join(original: fenced, segments: ["A", nil, "B"]) == "A"
                + fenced.dropFirst(10).dropLast(10) + "B")
        let unclosed = "Text before\n```\ncode\n\nmore code"
        #expect(translatable(unclosed) == ["Text before"])
        let codeBlock = "Explanation here\n\nimport Foundation\nlet value = compute()\nprint(value)"
        #expect(translatable(codeBlock) == ["Explanation here"])
    }

    @Test("不翻译的段、空串、越界的译文都用原文")
    func ignoresUnusableTranslations() {
        let text = "Hello\nhttps://example.com\nWorld"
        #expect(ClipTextSegmenter.join(original: text, segments: ["A", "B", ""]) == "A\nhttps://example.com\nWorld")
        #expect(ClipTextSegmenter.join(original: text, segments: ["A", "B", "C", "D"]) == "A\nhttps://example.com\nC")
    }

    // MARK: - 工具

    @Test("合并硬换行：东亚文字直接相连，行尾连字符接小写字母时去掉，其余以空格相连")
    func unwrap() {
        #expect(ClipTextSegmenter.unwrap(["well-", "known"]) == "wellknown")
        #expect(ClipTextSegmenter.unwrap(["Anti-", "Virus"]) == "Anti- Virus")
        #expect(ClipTextSegmenter.unwrap(["\u{4E2D}", "\u{6587}"]) == "\u{4E2D}\u{6587}")
        #expect(ClipTextSegmenter.unwrap(["abc", "\u{6587}"]) == "abc\u{6587}")
        #expect(ClipTextSegmenter.unwrap(["a", "", "b"]) == "a b")
    }

    @Test("显示宽度：东亚宽字符计 2 列")
    func displayColumns() {
        #expect(ClipTextSegmenter.displayColumns("\u{4E2D}\u{6587}ab") == 6)
        #expect(ClipTextSegmenter.displayColumns("\u{D55C}\u{FF01}") == 4)
        #expect(ClipTextSegmenter.displayColumns("") == 0)
    }

    @Test("分段版本号写入缓存")
    func version() {
        #expect(ClipTextSegmenter.version == 1)
    }
}
