import Foundation

/// 纯文本的一行及其分类（ClipTextSegmenter 用）。范围都指向原文，拼回译文时原文的分隔符、缩进与标记原样保留
struct ClipTextLine: Equatable {
    enum Kind: Equatable {
        case blank
        /// 普通文字行：可能与相邻行合并（硬换行的段落）
        case prose
        /// 带列表 / 引用 / 标题标记的行：标记不送翻译，自成一段、不与相邻行合并
        case marked
        /// 代码、网址、没有字母的行：原样保留，不翻译
        case verbatim
        /// 代码围栏（``` / ~~~，含围栏行与其中的空行）：原样保留，自成一块
        case fenced
    }

    /// 整行，不含换行符
    let range: Range<String.Index>
    /// 去掉缩进、行首标记与行尾空白后的内容；verbatim、fenced 与 blank 行为整行
    let content: Range<String.Index>
    let kind: Kind

    // MARK: - 分行与分类

    /// 按换行（含 CRLF）分行并分类；``` / ~~~ 围栏之间（含围栏行，未闭合时直到结尾）一律原样保留
    static func lines(of text: String) -> [ClipTextLine] {
        let raw = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return raw.reduce(into: (lines: [ClipTextLine](), inFence: false)) { state, line in
            let isFence = isFenceLine(line)
            state.lines.append(classify(line, fenced: state.inFence || isFence))
            if isFence { state.inFence.toggle() }
        }.lines
    }

    private static func classify(_ line: Substring, fenced: Bool) -> ClipTextLine {
        let whole = line.startIndex..<line.endIndex
        if fenced { return ClipTextLine(range: whole, content: whole, kind: .fenced) }
        if line.allSatisfy(\.isWhitespace) { return ClipTextLine(range: whole, content: whole, kind: .blank) }
        let body = line[markerEnd(of: line)...]
        let trimmedEnd = body.lastIndex { !$0.isWhitespace }.map(body.index(after:)) ?? body.startIndex
        let content = body[body.startIndex..<trimmedEnd]
        guard isTranslatable(content), !looksLikeCodeLine(content) else {
            return ClipTextLine(range: whole, content: whole, kind: .verbatim)
        }
        let kind: Kind = content.startIndex == firstNonWhitespace(of: line) ? .prose : .marked
        return ClipTextLine(range: whole, content: content.startIndex..<content.endIndex, kind: kind)
    }

    /// 值得送去翻译：含字母（含汉字、假名等），且不只是一个网址
    static func isTranslatable(_ text: Substring) -> Bool {
        text.contains(where: \.isLetter) && !isURL(text.trimmingCharacters(in: .whitespaces))
    }

    /// 只含一个网址（http(s)、www.、其他带 :// 的地址、mailto:）
    static func isURL(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        let lower = text.lowercased()
        return ContentClassifier.isLink(text) || lower.hasPrefix("www.") || lower.contains("://")
            || lower.hasPrefix("mailto:")
    }

    /// 单行代码的保守判定（误判散文的代价是不翻译该行，因此只认强特征）
    static func looksLikeCodeLine(_ text: Substring) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if codeLineEndings.contains(where: trimmed.hasSuffix) || trimmed.hasPrefix("}") { return true }
        return codeLinePrefixes.contains(where: trimmed.hasPrefix)
    }

    private static let codeLineEndings = [";", "{", "}"]
    private static let codeLinePrefixes = ["//", "/*", "#!", "#include", "#import", "$ "]

    // MARK: - 行首标记

    /// 行首缩进与标记之后的位置：无序列表（- * + • ◦ ▪ ‣）、有序列表（1. 1)）、引用（>）、Markdown 标题（# ）
    private static func markerEnd(of line: Substring) -> Substring.Index {
        let start = firstNonWhitespace(of: line)
        let rest = line[start...]
        guard let marker = markerLength(of: rest) else { return start }
        let afterMarker = rest.index(rest.startIndex, offsetBy: marker)
        return rest[afterMarker...].firstIndex { !$0.isWhitespace } ?? line.endIndex
    }

    /// 标记本身的字符数（不含其后的空白）；不是标记时为 nil
    private static func markerLength(of text: Substring) -> Int? {
        guard let first = text.first else { return nil }
        if first == ">" { return text.prefix { $0 == ">" || $0 == " " }.count }
        let followedBySpace = { (length: Int) in
            text.dropFirst(length).first.map { $0 == " " || $0 == "\t" } == true ? length : nil
        }
        if bulletMarkers.contains(first) { return followedBySpace(1) }
        if first == "#" {
            let hashes = text.prefix { $0 == "#" }.count
            return hashes <= 6 ? followedBySpace(hashes) : nil
        }
        let digits = text.prefix { $0.isASCII && $0.isNumber }.count
        guard (1...3).contains(digits), let delimiter = text.dropFirst(digits).first,
            delimiter == "." || delimiter == ")"
        else { return nil }
        return followedBySpace(digits + 1)
    }

    private static let bulletMarkers: Set<Character> = ["-", "*", "+", "\u{2022}", "\u{25E6}", "\u{25AA}", "\u{2023}"]

    private static func firstNonWhitespace(of line: Substring) -> Substring.Index {
        line.firstIndex { !$0.isWhitespace } ?? line.endIndex
    }

    private static func isFenceLine(_ line: Substring) -> Bool {
        let trimmed = line.drop(while: \.isWhitespace)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }
}
