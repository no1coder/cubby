import Foundation
import NaturalLanguage

/// 拆词分词（docs/TEXT-PICK-DESIGN.md P5、P6）：
/// 1. 先用 NSDataDetector 把网址（含邮箱）与电话号码保护成一整块——实测 NLTokenizer 会把
///    「https://github.com/x」拆成 https | github | com、把邮箱拆成四段；地址与日期范围太大，不合并；
/// 2. 实体之间的每一段交给 NLTokenizer(.word)（语言取 NLLanguageRecognizer 的判断），中日文按词；
///    分段单独分词：整段分词再取子范围时，跨过实体边界的词会被整个丢掉（「王小明13812345678」）；
/// 3. 其余不属于任何词的非空白字符成为标点块（同一字符的连续标点合成一块）；空白不成块，换行计入下一块。
/// 纯函数，可在后台调用（长文本的数据检测要上百毫秒）
public enum TextPickTokenizer {
    /// 判断语言只取开头这么多字符
    private static let languageSample = 2_000

    public static func document(for text: String, limit: Int = TextPickDocument.characterLimit) -> TextPickDocument {
        let head = text.prefix(max(limit, 0))
        let shown = String(head)
        let spans = coveredSpans(in: shown)
        var scanner = TokenScanner(text: shown)
        return TextPickDocument(
            text: shown, tokens: scanner.scan(spans), isTruncated: head.endIndex < text.endIndex)
    }

    /// 空白、零宽字符、控制字符，以及只由组合符号构成的字符（孤立的 U+0301、变体选择符 U+FE0F）：不成块
    static func isBlank(_ character: Character) -> Bool {
        character.isWhitespace
            || character.unicodeScalars.allSatisfy { invisibleCategories.contains($0.properties.generalCategory) }
    }

    private static let invisibleCategories: Set<Unicode.GeneralCategory> = [
        .format, .control, .nonspacingMark, .enclosingMark,
    ]

    // MARK: - 词与实体

    /// 已确定的块：实体与实体之间各段的词，按位置排序
    struct Span {
        let range: Range<String.Index>
        let kind: TextPickToken.Kind
    }

    private static func coveredSpans(in text: String) -> [Span] {
        let entities = entityRanges(in: text)
        let starts = [text.startIndex] + entities.map(\.upperBound)
        let ends = entities.map(\.lowerBound) + [text.endIndex]
        let tokenizer = NLTokenizer(unit: .word)
        let language = dominantLanguage(of: text)
        let spans = zip(starts, ends).enumerated().flatMap { offset, gap -> [Span] in
            let words = wordRanges(in: text, gap.0..<gap.1, tokenizer: tokenizer, language: language)
                .map { Span(range: $0, kind: .word) }
            let entity = entities.indices.contains(offset) ? [Span(range: entities[offset], kind: .entity)] : []
            return words + entity
        }
        return aligned(spans, in: text)
    }

    /// 两端对齐到字符边界（起点向前、终点向后取整），再合并因此重叠的块（有实体参与时整块算实体）
    private static func aligned(_ spans: [Span], in text: String) -> [Span] {
        let boundaries = TextPickCharacterBoundaries(text)
        return spans.reduce(into: []) { result, span in
            let range =
                boundaries.roundingDown(span.range.lowerBound)..<boundaries.roundingUp(span.range.upperBound)
            guard !range.isEmpty else { return }
            guard let last = result.last, range.lowerBound < last.range.upperBound else {
                result.append(Span(range: range, kind: span.kind))
                return
            }
            let kind: TextPickToken.Kind = last.kind == .entity || span.kind == .entity ? .entity : .word
            let merged = last.range.lowerBound..<max(last.range.upperBound, range.upperBound)
            result[result.count - 1] = Span(range: merged, kind: kind)
        }
    }

    /// 网址（含 mailto 邮箱）与电话号码；跨行的结果不保护（换行必须留给排版）
    private static func entityRanges(in text: String) -> [Range<String.Index>] {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard !text.isEmpty, let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        let ranges = detector.matches(in: text, range: whole).compactMap { match -> Range<String.Index>? in
            guard let range = Range(match.range, in: text), !text[range].contains(where: \.isNewline) else {
                return nil
            }
            return range
        }
        // 防御：只保留按顺序、互不重叠的结果
        return ranges.reduce(into: []) { kept, range in
            if kept.last.map({ $0.upperBound <= range.lowerBound }) ?? true {
                kept.append(range)
            }
        }
    }

    /// 一段文字里的词（片段单独分词，再把位置按 UTF-8 偏移换回原文）
    private static func wordRanges(
        in text: String, _ gap: Range<String.Index>, tokenizer: NLTokenizer, language: NLLanguage?
    ) -> [Range<String.Index>] {
        guard !gap.isEmpty else { return [] }
        let piece = String(text[gap])
        tokenizer.string = piece
        if let language {
            tokenizer.setLanguage(language)
        }
        let base = text.utf8.distance(from: text.startIndex, to: gap.lowerBound)
        return tokenizer.tokens(for: piece.startIndex..<piece.endIndex).map { range in
            let lower = base + piece.utf8.distance(from: piece.startIndex, to: range.lowerBound)
            let upper = base + piece.utf8.distance(from: piece.startIndex, to: range.upperBound)
            return text.utf8.index(text.startIndex, offsetBy: lower)..<text.utf8.index(text.startIndex, offsetBy: upper)
        }
    }

    private static func dominantLanguage(of text: String) -> NLLanguage? {
        let language = NLLanguageRecognizer.dominantLanguage(for: String(text.prefix(languageSample)))
        return language == .undetermined ? nil : language
    }
}

/// 按顺序走一遍原文：遇到已确定的块（词 / 实体）整体输出，其余非空白字符输出为标点块，换行计入下一块
private struct TokenScanner {
    let text: String
    private var tokens: [TextPickToken] = []
    private var newlines = 0

    init(text: String) {
        self.text = text
    }

    mutating func scan(_ spans: [TextPickTokenizer.Span]) -> [TextPickToken] {
        var pending = spans[...]
        var index = text.startIndex
        while index < text.endIndex {
            if let span = pending.first, index >= span.range.lowerBound {
                pending = pending.dropFirst()
                // 分词器会把零宽字符当成一个「词」：看不见的块不输出
                if !text[span.range].allSatisfy(TextPickTokenizer.isBlank) {
                    emit(span.range, kind: span.kind)
                }
                // 块已对齐到字符边界且互不重叠；只前进到块尾，不再多跳一个字符（否则会漏掉紧随的标点）
                index = max(index, span.range.upperBound)
                continue
            }
            let next = text.index(after: index)
            consume(text[index], at: index..<next)
            index = next
        }
        return tokens
    }

    private mutating func consume(_ character: Character, at range: Range<String.Index>) {
        if character.isNewline {
            newlines += 1
        } else if !TextPickTokenizer.isBlank(character) {
            appendPunctuation(character, at: range)
        }
    }

    /// 同一字符的连续标点（中间没有空白）合成一块：「...」「——」「!!!」
    private mutating func appendPunctuation(_ character: Character, at range: Range<String.Index>) {
        guard let last = tokens.last, last.kind == .punctuation, last.range.upperBound == range.lowerBound,
            last.text.last == character
        else {
            emit(range, kind: .punctuation)
            return
        }
        tokens[tokens.count - 1] = TextPickToken(
            range: last.range.lowerBound..<range.upperBound, text: last.text + String(character), kind: .punctuation,
            lineBreaksBefore: last.lineBreaksBefore)
    }

    private mutating func emit(_ range: Range<String.Index>, kind: TextPickToken.Kind) {
        tokens.append(
            TextPickToken(range: range, text: String(text[range]), kind: kind, lineBreaksBefore: newlines))
        newlines = 0
    }
}
