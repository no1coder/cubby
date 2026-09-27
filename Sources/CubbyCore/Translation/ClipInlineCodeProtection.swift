import Foundation

/// 系统翻译的行内代码保护（docs/CLIP-TRANSLATION-DESIGN.md §0.1 A2、§7 缺口 3，纯函数）。
///
/// 大模型收到的是受限 Markdown，行内代码已换成 `` `c1` `` 占位符；系统翻译只收纯文本，代码原文会被一起翻译。
/// 这里把送给系统翻译的段落里的行内代码换成 `{1}`、`{2}`…，译文返回后按编号还原：
/// - 译文里的全角括号与数字（`｛１｝`）、其他文字的数字、括号内的空白同样接受；占位符的顺序可以变（语序不同）；
/// - 任一占位符缺失、重复或出现多余编号即判定保护失败（`restore` 返回 nil），调用方应不带保护重译该段——
///   结果不会比不保护更差；
/// - 原文（代码以外的部分）里本就有形如占位符的文字时不保护，避免还原到错误的位置。
///
/// 富文本段落（markup 为 true）：译文中占位符以外的文字按受限 Markdown 转义，代码还原为 `` `cN` ``，
/// 交给 `ClipTranslationDocument.storableTranslation(_:at:markup: true)` 还原代码原文与样式，行内代码因此保持代码样式；
/// 纯文本段落：代码还原为原文里的整段 `` `代码` ``（含反引号）
struct ClipInlineCodeProtection: Equatable, Sendable {
    /// 段落的组成：普通文字与行内代码
    enum Piece: Equatable, Sendable {
        case text(String)
        case code(String)
    }

    /// 送给引擎的文字
    let sent: String
    /// 第 N 个占位符（从 1 起）还原成的文字
    let restorations: [String]
    /// 译文中占位符以外的文字是否按受限 Markdown 转义（富文本段落）
    let escapesText: Bool

    private static let escapable: Set<Character> = ["\\", "*", "[", "]", "`"]
    private static let openers: Set<Character> = ["{", "\u{FF5B}"]
    private static let closers: Set<Character> = ["}", "\u{FF5D}"]

    /// 由段落组成构造。plainText：不设占位符时发送的原文（含代码原文）；markup：富文本段落（结果按受限 Markdown 存储）。
    /// protects 为 false、没有行内代码或原文里本就有形如占位符的文字时，按 plainText 发送、不设占位符
    init(pieces: [Piece], plainText: String, markup: Bool, protects: Bool = true) {
        let hasCode = pieces.contains { if case .code = $0 { true } else { false } }
        let collides = pieces.contains { piece in
            if case .text(let text) = piece { Self.containsToken(text) } else { false }
        }
        guard protects, hasCode, !collides else {
            self.init(sent: plainText, restorations: [], escapesText: markup)
            return
        }
        var sent = ""
        var restorations: [String] = []
        for piece in pieces {
            switch piece {
            case .text(let text):
                sent += text
            case .code(let code):
                restorations.append(markup ? "`c\(restorations.count + 1)`" : code)
                sent += "{\(restorations.count)}"
            }
        }
        self.init(sent: sent, restorations: restorations, escapesText: markup)
    }

    private init(sent: String, restorations: [String], escapesText: Bool) {
        self.sent = sent
        self.restorations = restorations
        self.escapesText = escapesText
    }

    /// 富文本段落：代码行内文字为代码，其余为普通文字（相邻的普通文字合并）
    static func pieces(of runs: [ClipRichRun]) -> [Piece] {
        runs.reduce(into: [Piece]()) { pieces, run in
            if run.isCode {
                pieces.append(.code(run.text))
            } else if case .text(let previous)? = pieces.last {
                pieces[pieces.count - 1] = .text(previous + run.text)
            } else {
                pieces.append(.text(run.text))
            }
        }
    }

    /// 纯文本段落：同一行内成对反引号括起的非空文字（`` `npm install` ``）视为行内代码，含反引号整段保留；
    /// 空的一对反引号与不成对的反引号按普通文字
    static func pieces(of text: String) -> [Piece] {
        var pieces: [Piece] = []
        var pending = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "`") {
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(where: { $0 == "`" || $0.isNewline }), rest[close] == "`"
            else {
                pending += rest[..<after]
                rest = rest[after...]
                continue
            }
            // 空的一对反引号：两个都按文字
            guard close > after else {
                pending += rest[...close]
                rest = rest[rest.index(after: close)...]
                continue
            }
            pending += rest[..<open]
            if !pending.isEmpty { pieces.append(.text(pending)) }
            pending = ""
            pieces.append(.code(String(rest[open...close])))
            rest = rest[rest.index(after: close)...]
        }
        pending += rest
        if !pending.isEmpty { pieces.append(.text(pending)) }
        return pieces
    }

    /// 是否有要还原的占位符或要转义的文字；都没有时引擎的输出原样使用
    var isIdentity: Bool {
        restorations.isEmpty && !escapesText
    }

    /// 引擎的输出 → 还原后的文字；占位符不完整（缺失、重复、多余）时为 nil
    func restore(_ output: String) -> String? {
        guard !restorations.isEmpty else { return escapesText ? Self.escaped(output[...]) : output }
        var result = ""
        var used = Set<Int>()
        var cursor = output.startIndex
        for token in Self.tokens(in: output) {
            guard (1...restorations.count).contains(token.number), used.insert(token.number).inserted else {
                return nil
            }
            result += text(output[cursor..<token.range.lowerBound]) + restorations[token.number - 1]
            cursor = token.range.upperBound
        }
        guard used.count == restorations.count else { return nil }
        return result + text(output[cursor...])
    }

    // MARK: - 内部

    private func text(_ slice: Substring) -> String {
        escapesText ? Self.escaped(slice) : String(slice)
    }

    private static func escaped(_ text: Substring) -> String {
        text.reduce(into: "") { output, character in
            if escapable.contains(character) { output.append("\\") }
            output.append(character)
        }
    }

    private static func containsToken(_ text: String) -> Bool {
        !tokens(in: text).isEmpty
    }

    /// 形如占位符的片段：开括号、可选空白、十进制数字（任何文字的数字）、可选空白、闭括号
    private static func tokens(in text: String) -> [(range: Range<String.Index>, number: Int)] {
        var found: [(range: Range<String.Index>, number: Int)] = []
        var index = text.startIndex
        while index < text.endIndex {
            if openers.contains(text[index]), let token = token(in: text, openingAt: index) {
                found.append(token)
                index = token.range.upperBound
            } else {
                index = text.index(after: index)
            }
        }
        return found
    }

    private static func token(in text: String, openingAt start: String.Index) -> (
        range: Range<String.Index>, number: Int
    )? {
        var index = text.index(after: start)
        skipSpaces(in: text, from: &index)
        var digits: [Int] = []
        while index < text.endIndex, let digit = decimalDigit(text[index]) {
            digits.append(digit)
            index = text.index(after: index)
        }
        skipSpaces(in: text, from: &index)
        guard !digits.isEmpty, digits.count <= 4, index < text.endIndex, closers.contains(text[index]) else {
            return nil
        }
        let number = digits.reduce(0) { $0 * 10 + $1 }
        return (start..<text.index(after: index), number)
    }

    private static func skipSpaces(in text: String, from index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace, !text[index].isNewline {
            index = text.index(after: index)
        }
    }

    /// 十进制数字（含全角与其他文字的数字）的值
    private static func decimalDigit(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
            scalar.properties.numericType == .decimal
        else { return nil }
        return character.wholeNumberValue
    }
}
