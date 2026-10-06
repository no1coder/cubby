import Foundation
import Testing
@testable import CubbyCore

/// 拆词的模糊测试：用组合符号、零宽连接符、泰文声调、emoji、中日文、标点与换行拼出的随机文本，
/// 检查分词的不变量，并确认全选与任意两块的拼接都不会崩溃（曾因块边界落在字符中间而构造反向区间）。
/// 默认 512 段，按 `CUBBY_FUZZ_SEEDS` 缩放（见 `FuzzBudget`）
@Suite("TextPick 模糊测试")
struct TextPickFuzzTests {
    private static let defaultCount = 512
    private static let maxLength = 24

    /// 容易让分词器与 Swift 字符边界不一致的片段
    private static let alphabet: [String] = [
        "a", "Z", "1", " ", "\n", "\r\n", "\t", "(", ")", ",", ".", "。", "，", "—", "…", "-", "@", "/", ":",
        "\u{0301}", "\u{0E48}", "ก", "\u{FE0F}", "\u{20E3}", "\u{200B}", "\u{200D}", "👨", "🎉", "会", "議", "の",
        "한", "é", "https://x.io/a", "a@b.co", "13812345678",
    ]

    @Test("随机文本：块按顺序、不重叠、落在字符边界上；全选与两两拼接不崩溃")
    func randomTexts() {
        var generator = SeededGenerator(seed: 0x7E57_91C4)
        for _ in 0..<FuzzBudget.scaled(Self.defaultCount) {
            let length = Int.random(in: 1...Self.maxLength, using: &generator)
            let source = (0..<length).map { _ in Self.alphabet.randomElement(using: &generator) ?? "" }.joined()
            check(source, generator: &generator)
        }
    }

    private func check(_ source: String, generator: inout SeededGenerator) {
        let document = TextPickTokenizer.document(for: source)
        let text = document.text
        let boundaries = Set(text.indices).union([text.endIndex])
        let ordered = zip(document.tokens, document.tokens.dropFirst()).allSatisfy {
            $0.range.upperBound <= $1.range.lowerBound
        }
        #expect(ordered, "tokens overlap in \(source.debugDescription)")
        for token in document.tokens {
            #expect(
                boundaries.contains(token.range.lowerBound) && boundaries.contains(token.range.upperBound),
                "token off a character boundary in \(source.debugDescription)")
            #expect(!token.text.allSatisfy(TextPickTokenizer.isBlank), "invisible token in \(source.debugDescription)")
        }
        let all = TextPickSelection().togglingAll(count: document.tokens.count)
        _ = TextPickResult.text(of: document, selection: all)
        guard document.tokens.count > 1 else { return }
        let first = Int.random(in: 0..<document.tokens.count, using: &generator)
        let second = Int.random(in: 0..<document.tokens.count, using: &generator)
        _ = TextPickResult.text(of: document, selection: TextPickSelection().toggling(first).toggling(second))
    }
}
