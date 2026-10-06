import Foundation
import Testing
@testable import CubbyCore

/// 拆词分词（docs/TEXT-PICK-DESIGN.md P5、P6）：系统分词 + 网址 / 邮箱 / 电话保护成一块；空白不成块；
/// 标点单独成块（同一字符的连续标点合成一块）；换行计数；只拆前 20,000 个字符
@Suite("TextPickTokenizer 拆词分词")
struct TextPickTokenizerTests {
    private func texts(_ text: String) -> [String] {
        TextPickTokenizer.document(for: text).tokens.map(\.text)
    }

    private func token(_ text: String, in source: String) -> TextPickToken? {
        TextPickTokenizer.document(for: source).tokens.first { $0.text == text }
    }

    // MARK: - 基本拆分

    @Test("英文：单词与标点各成一块，空白不成块")
    func englishWordsAndPunctuation() {
        let document = TextPickTokenizer.document(for: "Hello,   world!")
        #expect(document.tokens.map(\.text) == ["Hello", ",", "world", "!"])
        #expect(document.tokens.map(\.kind) == [.word, .punctuation, .word, .punctuation])
        #expect(document.wordCount == 2)
    }

    @Test("中文按词拆分，标点（含全角）单独成块")
    func chineseWords() {
        let tokens = texts("会议改到周四下午3点，地址：北京市朝阳区")
        #expect(tokens.contains("会议"))
        #expect(tokens.contains("周四"))
        #expect(tokens.contains("北京市"))
        #expect(tokens.contains("，"))
        #expect(tokens.contains("："))
        #expect(tokens.joined() == "会议改到周四下午3点，地址：北京市朝阳区")
    }

    @Test("中英混排与日文")
    func mixedScripts() {
        #expect(texts("今天用 SwiftUI 写了一个 NSScrollView").contains("SwiftUI"))
        #expect(texts("今天用 SwiftUI 写了一个 NSScrollView").contains("NSScrollView"))
        #expect(texts("明日の会議は午後3時に変更になりました。").contains("会議"))
    }

    @Test("emoji 与数字是普通词块")
    func emojiAndNumbers() {
        let document = TextPickTokenizer.document(for: "Ship 2 🎉")
        #expect(document.tokens.map(\.text) == ["Ship", "2", "🎉"])
        #expect(document.tokens.allSatisfy { $0.kind == .word })
    }

    @Test(
        "同一字符的连续标点合成一块，不同字符各成一块",
        arguments: [
            ("Wait...", ["Wait", "..."]),
            ("ok?!", ["ok", "?", "!"]),
            ("好——的", ["好", "——", "的"]),
            ("C++", ["C", "++"]),
            ("a……b", ["a", "……", "b"]),
        ])
    func punctuationRuns(_ text: String, _ expected: [String]) {
        #expect(texts(text) == expected)
    }

    @Test("空白（含全角空格、零宽空格、制表符）不成块")
    func blanksAreSkipped() {
        #expect(texts(" \t a\u{3000}b\u{200B}c \u{00A0}") == ["a", "b", "c"])
    }

    @Test("空文本与纯空白：没有词块")
    func emptyText() {
        #expect(TextPickTokenizer.document(for: "").isEmpty)
        #expect(TextPickTokenizer.document(for: " \n\t\u{3000}").isEmpty)
        #expect(TextPickTokenizer.document(for: " \n").wordCount == 0)
    }

    // MARK: - 实体保护

    @Test("网址保护成一整块（分词器会拆成 https | github | com）")
    func linksAreProtected() {
        let source = "Please review https://github.com/no1coder/cubby/pull/1234 before 5:30pm."
        let link = token("https://github.com/no1coder/cubby/pull/1234", in: source)
        #expect(link?.kind == .entity)
        #expect(!texts(source).contains("github"))
        #expect(texts(source).last == ".")
    }

    @Test("邮箱保护成一整块，后面的全角句号仍单独成块")
    func emailsAreProtected() {
        let source = "邮箱 wang.xm@example.com。"
        #expect(texts(source) == ["邮箱", "wang.xm@example.com", "。"])
        #expect(token("wang.xm@example.com", in: source)?.kind == .entity)
    }

    @Test("电话号码保护成一整块（含空格与括号的格式也是一块）")
    func phonesAreProtected() {
        #expect(token("13812345678", in: "联系人王小明 13812345678，")?.kind == .entity)
        let source = "Call +1 (555) 123-4567 today"
        #expect(token("+1 (555) 123-4567", in: source)?.kind == .entity)
        #expect(texts(source) == ["Call", "+1 (555) 123-4567", "today"])
    }

    @Test("实体紧贴中文时，两侧的中文仍按词拆分")
    func entityGluedToChinese() {
        let tokens = texts("联系人王小明13812345678邮箱wang.xm@example.com")
        #expect(tokens.contains("王"))
        #expect(tokens.contains("小明"))
        #expect(tokens.contains("13812345678"))
        #expect(tokens.contains("邮箱"))
        #expect(tokens.last == "wang.xm@example.com")
    }

    @Test("地址与日期不合并（用户常只要其中一段）")
    func addressesAndDatesAreNotMerged() {
        let address = texts("地址：北京市朝阳区建国路88号SOHO现代城A座1203室")
        #expect(address.contains("北京市"))
        #expect(address.contains("朝阳区"))
        #expect(address.contains("88"))
        let date = TextPickTokenizer.document(for: "Due 2026-10-04 at noon")
        #expect(date.tokens.allSatisfy { $0.kind != .entity })
        #expect(date.tokens.map(\.text).contains("2026"))
    }

    // MARK: - 换行

    @Test("每块记录与上一块之间的换行数（CRLF 算一个）")
    func lineBreaks() {
        let document = TextPickTokenizer.document(for: "\n\na b\nc\r\nd\n\n\ne")
        #expect(document.tokens.map(\.text) == ["a", "b", "c", "d", "e"])
        #expect(document.tokens.map(\.lineBreaksBefore) == [2, 0, 1, 1, 3])
    }

    @Test("标点前的换行同样记录")
    func lineBreakBeforePunctuation() {
        let document = TextPickTokenizer.document(for: "a\n。")
        #expect(document.tokens.map(\.lineBreaksBefore) == [0, 1])
    }

    // MARK: - 长度上限

    @Test("只拆前 limit 个字符，超出时标记 isTruncated")
    func truncation() {
        let source = String(repeating: "ab ", count: 10)
        let document = TextPickTokenizer.document(for: source, limit: 5)
        #expect(document.text == "ab ab")
        #expect(document.isTruncated)
        #expect(document.tokens.map(\.text) == ["ab", "ab"])
        #expect(!TextPickTokenizer.document(for: "abcde", limit: 5).isTruncated)
        #expect(!TextPickTokenizer.document(for: "abc").isTruncated)
    }

    @Test("默认上限 20,000 个字符（与预览一致）")
    func defaultLimit() {
        #expect(TextPickDocument.characterLimit == 20_000)
        let source = String(repeating: "word ", count: 4_001)
        let document = TextPickTokenizer.document(for: source)
        #expect(document.isTruncated)
        #expect(document.text.count == 20_000)
        #expect(document.tokens.count == 4_000)
    }

    // MARK: - 不变量

    static let corpus: [String] =
        [
            "会议改到周四下午3点，地址：北京市朝阳区建国路88号SOHO现代城A座1203室，联系人王小明 13812345678，邮箱 wang.xm@example.com。\n\n请提前十分钟到。",
            "Please review PR #1234 at https://github.com/no1coder/cubby/pull/1234 before 5:30pm. It's ready (v0.2.1).",
            "Price $5.99 — 100% done... 🎉 e.g. U.S.A. state-of-the-art\r\n\r\nNext 👨‍👩‍👧 family",
            "明日の会議は午後3時に変更になりました。資料は事前に共有します。",
            "안녕하세요 반갑습니다", "   ", "", "\u{200B}", "a\u{0301}b", "x=1;y=[2,3]",
        ] + combining

    /// 标点后紧跟组合符号（OCR、分解式变音符、泰文声调）：Swift 把它们算作一个字符，分词器却可能从组合符号起词
    static let combining: [String] = [
        "(\u{0301}abc)", "。\u{0301}b", ",\u{0E48}ก", "1\u{FE0F}\u{20E3}\u{0E48}—", "e\u{0301}\u{0301}x (y)",
    ]

    @Test("组合字符：块的边界落在字符边界上，任意两块一起选都能拼出结果", arguments: combining)
    func combiningMarks(_ source: String) {
        let document = TextPickTokenizer.document(for: source)
        let text = document.text
        let boundaries = Set(text.indices).union([text.endIndex])
        for token in document.tokens {
            #expect(boundaries.contains(token.range.lowerBound) && boundaries.contains(token.range.upperBound))
        }
        for first in document.tokens.indices {
            for second in document.tokens.indices where second > first {
                let selection = TextPickSelection().toggling(first).toggling(second)
                #expect(!TextPickResult.text(of: document, selection: selection).isEmpty)
            }
        }
    }

    @Test("组合符号后的标点不会被跳过")
    func punctuationAfterCombiningMark() {
        #expect(texts("1\u{FE0F}\u{20E3}\u{0E48}—").last == "—")
    }

    @Test("只有零宽字符或孤立的变体选择符时没有词块")
    func invisibleOnly() {
        #expect(TextPickTokenizer.document(for: "\u{200B}").isEmpty)
        #expect(TextPickTokenizer.document(for: "\u{FE0F}").isEmpty)
        #expect(TextPickTokenizer.document(for: "\u{200B}\u{200D}").isEmpty)
    }

    @Test("每块的文字等于原文对应范围；范围按顺序且不重叠；除空白外每个字符都在某块里", arguments: corpus)
    func invariants(_ source: String) {
        let document = TextPickTokenizer.document(for: source)
        for token in document.tokens {
            #expect(String(document.text[token.range]) == token.text)
            #expect(!token.text.isEmpty)
        }
        let ordered = zip(document.tokens, document.tokens.dropFirst()).allSatisfy {
            $0.range.upperBound <= $1.range.lowerBound
        }
        #expect(ordered)
        let text = document.text
        let uncovered = text.indices.filter { index in
            !document.tokens.contains { $0.range.contains(index) }
        }
        #expect(uncovered.allSatisfy { TextPickTokenizer.isBlank(text[$0]) })
    }
}
