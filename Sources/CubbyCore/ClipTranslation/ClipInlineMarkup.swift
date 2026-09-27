import Foundation

/// 受限 Markdown（docs/CLIP-TRANSLATION-DESIGN.md §0.1 A2）：大模型收发富文本段落时的行内标记。
/// - 语法只有 `**粗体**`、`[文字](链接)`、`` `代码` ``；文字里的 \ * [ ] ` 以反斜杠转义，代码里的 \ ` 以反斜杠转义，
///   链接地址里的括号与空格按百分号编码；
/// - 发送时行内代码换成占位符 `` `c1` ``…、链接地址换成占位符 `[文字](L1)`…：代码与链接地址都不发送
///   （地址里常带令牌，而疑似密钥检查只看得到文字）；收到后按编号还原；
/// - 缓存里保存还原后的「规范形式」（代码与链接地址写原文），自成一体：搜索与重建都不需要再读原文；
/// - 解析容错：不成对的 `**` 丢弃，其余不合语法的标记按字面保留；链接只接受原文里的：
///   大模型译文里编号未知、重复出现的占位符与任何直接写出的地址都只保留文字
enum ClipInlineMarkup {
    private static let escapable: Set<Character> = ["\\", "*", "[", "]", "`"]
    private static let codeEscapable: Set<Character> = ["\\", "`"]
    private static let placeholderPrefix = "c"
    private static let linkPlaceholderPrefix = "L"
    /// 解析时暂代链接占位符的地址（只在本类型内部出现，还原前即被替换）
    private static let slotScheme = "x-cubby-link-slot:"

    /// 行内文字 → 标记文字；placeholders 为 true 时行内代码与链接地址写成占位符（发送用），否则写原文（缓存用）
    static func serialize(_ runs: [ClipRichRun], placeholders: Bool) -> String {
        let ordinals = runs.reduce(into: [Int]()) { $0.append(($0.last ?? 0) + ($1.isCode ? 1 : 0)) }
        let atoms = zip(runs, ordinals).map { run, ordinal in
            (run: run, text: atom(run, ordinal: ordinal, placeholders: placeholders))
        }
        let groups = atoms.consecutiveGroups { $0.run.link }
        let linkOrdinals = groups.reduce(into: [Int]()) { $0.append(($0.last ?? 0) + ($1[0].run.link == nil ? 0 : 1)) }
        return zip(groups, linkOrdinals).map { group, ordinal in
            let body = group.consecutiveGroups { $0.run.isBold }.map { stretch in
                let text = stretch.map(\.text).joined()
                return stretch[0].run.isBold ? bolded(text) : text
            }.joined()
            guard let link = group[0].run.link else { return body }
            let destination = placeholders ? linkPlaceholderPrefix + String(ordinal) : target(of: link)
            return "[" + body + "](" + destination + ")"
        }.joined()
    }

    /// 行内代码的原文（按出现顺序，第 N 段对应占位符 cN）
    static func codeSpans(in runs: [ClipRichRun]) -> [String] {
        runs.filter(\.isCode).map(\.text)
    }

    /// 各处链接的地址（按出现顺序，第 N 处对应占位符 LN；同一地址出现两处就占两个编号）
    static func linkSlots(in runs: [ClipRichRun]) -> [URL] {
        runs.consecutiveGroups(by: \.link).compactMap { $0[0].link }
    }

    /// 标记文字 → 行内文字。codeSpans 非 nil 时把占位符 cN 还原为对应代码。
    /// linkSlots 非 nil（大模型译文）时只接受链接占位符 LN 并还原为对应地址，编号未知或重复出现的、直接写出的地址都只保留文字；
    /// 否则（缓存的规范形式）只接受 allowedLinks 中的地址
    static func parse(
        _ markup: String, codeSpans: [String]? = nil, linkSlots: [URL]? = nil, allowedLinks: [URL] = []
    ) -> [ClipRichRun] {
        guard let linkSlots else {
            let allowed = allowedLinks.reduce(into: [String: URL]()) { map, link in
                map[link.absoluteString] = link
                map[target(of: link)] = link
            }
            return Parser(chars: Array(markup), codeSpans: codeSpans, allowed: allowed).parseAll()
        }
        let sentinels = linkSlots.indices.reduce(into: [String: URL]()) { map, index in
            map[linkPlaceholderPrefix + String(index + 1)] = URL(string: slotScheme + String(index + 1))
        }
        let runs = Parser(chars: Array(markup), codeSpans: codeSpans, allowed: sentinels).parseAll()
        return resolvingSlots(runs, linkSlots)
    }

    /// 暂代地址 → 原文地址；同一占位符出现不止一处（含义不明）时每一处都只保留文字
    private static func resolvingSlots(_ runs: [ClipRichRun], _ slots: [URL]) -> [ClipRichRun] {
        let groups = runs.consecutiveGroups(by: \.link)
        let uses = groups.compactMap { $0[0].link }.reduce(into: [URL: Int]()) { $0[$1, default: 0] += 1 }
        return groups.flatMap { group -> [ClipRichRun] in
            guard let sentinel = group[0].link else { return group }
            let number = Int(sentinel.absoluteString.dropFirst(slotScheme.count)) ?? 0
            let link = uses[sentinel] == 1 && slots.indices.contains(number - 1) ? slots[number - 1] : nil
            return group.map { ClipRichRun($0.text, isBold: $0.isBold, link: link, isCode: $0.isCode) }
        }
    }

    /// 去掉标记的纯文本（搜索、卡片上的译文首行）
    static func plainText(_ markup: String) -> String {
        parse(markup).map(\.text).joined()
    }

    // MARK: - 写出

    private static func atom(_ run: ClipRichRun, ordinal: Int, placeholders: Bool) -> String {
        guard run.isCode else { return escaped(run.text, escapable) }
        return "`" + (placeholders ? placeholderPrefix + String(ordinal) : escaped(run.text, codeEscapable)) + "`"
    }

    /// 粗体：首尾空白挪到标记外（`**a **b` 易被模型改坏）
    private static func bolded(_ text: String) -> String {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }),
            let last = text.lastIndex(where: { !$0.isWhitespace })
        else { return text }
        return String(text[..<first]) + "**" + String(text[first...last]) + "**"
            + String(text[text.index(after: last)...])
    }

    private static func escaped(_ text: String, _ characters: Set<Character>) -> String {
        text.reduce(into: "") { output, character in
            if characters.contains(character) { output.append("\\") }
            output.append(character)
        }
    }

    /// 链接地址：括号与空格百分号编码，保证 `)` 能结束链接
    private static func target(of link: URL) -> String {
        link.absoluteString
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    // MARK: - 解析

    private struct Parser {
        let chars: [Character]
        let codeSpans: [String]?
        let allowed: [String: URL]
        /// 从每个位置起、括号配对后第一个未配对的 `)` 的位置（没有时为 chars.count）：链接地址 O(1) 定位，
        /// 大模型的异常输出（如成千上万个 `[a](`）也保持线性
        private let closingParens: [Int]
        /// 从每个位置起第一个空白的位置（没有时为 chars.count）
        private let nextWhitespace: [Int]

        init(chars: [Character], codeSpans: [String]?, allowed: [String: URL]) {
            self.chars = chars
            self.codeSpans = codeSpans
            self.allowed = allowed
            (closingParens, nextWhitespace) = Self.scanTables(chars)
        }

        /// 从后往前一次扫描：`(` 的配对是其后第一个未配对的 `)`，越过它再找
        private static func scanTables(_ chars: [Character]) -> (closing: [Int], whitespace: [Int]) {
            let count = chars.count
            return chars.indices.reversed().reduce(
                into: (
                    closing: [Int](repeating: count, count: count + 1),
                    whitespace: [Int](repeating: count, count: count + 1)
                )
            ) { tables, index in
                tables.whitespace[index] = chars[index].isWhitespace ? index : tables.whitespace[index + 1]
                switch chars[index] {
                case ")":
                    tables.closing[index] = index
                case "(":
                    let match = tables.closing[index + 1]
                    tables.closing[index] = match < count ? tables.closing[match + 1] : count
                default:
                    tables.closing[index] = tables.closing[index + 1]
                }
            }
        }

        func parseAll() -> [ClipRichRun] {
            parse(0..<chars.count, bold: false, link: nil)
        }

        func parse(_ range: Range<Int>, bold: Bool, link: URL?) -> [ClipRichRun] {
            var runs: [ClipRichRun] = []
            var literal = ""
            var index = range.lowerBound
            while index < range.upperBound {
                if let character = escapedCharacter(at: index, in: range, ClipInlineMarkup.escapable) {
                    literal.append(character)
                    index += 2
                } else if let found = construct(at: index, in: range, bold: bold, link: link) {
                    runs += [ClipRichRun(literal, isBold: bold, link: link)] + found.runs
                    literal = ""
                    index = found.end
                } else {
                    literal.append(chars[index])
                    index += 1
                }
            }
            return (runs + [ClipRichRun(literal, isBold: bold, link: link)]).filter { !$0.text.isEmpty }
        }

        /// 识别从 index 起的标记结构，返回它产生的行内文字与结束位置；不是标记时为 nil
        private func construct(
            at index: Int, in range: Range<Int>, bold: Bool, link: URL?
        ) -> (runs: [ClipRichRun], end: Int)? {
            switch chars[index] {
            case "`":
                guard let close = codeEnd(after: index, in: range) else { return nil }
                return ([code(index + 1..<close, bold: bold, link: link)], close + 1)
            case "*" where index + 1 < range.upperBound && chars[index + 1] == "*":
                // 已在粗体内（嵌套）或找不到结束标记：丢弃这个 **
                guard !bold, let close = boldEnd(from: index + 2, in: range) else { return ([], index + 2) }
                return (parse(index + 2..<close, bold: true, link: link), close + 2)
            case "[" where link == nil:
                guard let end = linkEnd(after: index, in: range) else { return nil }
                let target = String(chars[(end.textEnd + 2)..<end.targetEnd])
                return (parse(index + 1..<end.textEnd, bold: bold, link: allowed[target]), end.targetEnd + 1)
            default:
                return nil
            }
        }

        private func escapedCharacter(at index: Int, in range: Range<Int>, _ set: Set<Character>) -> Character? {
            guard chars[index] == "\\", index + 1 < range.upperBound, set.contains(chars[index + 1]) else { return nil }
            return chars[index + 1]
        }

        private func code(_ range: Range<Int>, bold: Bool, link: URL?) -> ClipRichRun {
            let content = String(
                range.reduce(into: (text: "", skip: false)) { state, index in
                    if state.skip {
                        state.skip = false
                    } else if let escaped = escapedCharacter(at: index, in: range, ClipInlineMarkup.codeEscapable) {
                        state.text.append(escaped)
                        state.skip = true
                    } else {
                        state.text.append(chars[index])
                    }
                }.text)
            return ClipRichRun(restoringPlaceholder(content), isBold: bold, link: link, isCode: true)
        }

        /// 占位符 cN → 第 N 段代码原文；不是占位符或编号越界时按字面
        private func restoringPlaceholder(_ content: String) -> String {
            guard let codeSpans, content.hasPrefix(ClipInlineMarkup.placeholderPrefix),
                let number = Int(content.dropFirst(ClipInlineMarkup.placeholderPrefix.count)),
                codeSpans.indices.contains(number - 1)
            else { return content }
            return codeSpans[number - 1]
        }

        /// 行内代码的结束反引号（跳过转义）
        private func codeEnd(after index: Int, in range: Range<Int>) -> Int? {
            var cursor = index + 1
            while cursor < range.upperBound {
                if escapedCharacter(at: cursor, in: range, ClipInlineMarkup.codeEscapable) != nil {
                    cursor += 2
                } else if chars[cursor] == "`" {
                    return cursor
                } else {
                    cursor += 1
                }
            }
            return nil
        }

        /// 粗体的结束 **（跳过转义、行内代码与完整的链接）
        private func boldEnd(from index: Int, in range: Range<Int>) -> Int? {
            var cursor = index
            while cursor + 1 < range.upperBound {
                if let next = skipped(at: cursor, in: range) {
                    cursor = next
                } else if chars[cursor] == "[", let link = linkEnd(after: cursor, in: range) {
                    cursor = link.targetEnd + 1
                } else if chars[cursor] == "*", chars[cursor + 1] == "*" {
                    return cursor
                } else {
                    cursor += 1
                }
            }
            return nil
        }

        /// 链接 [文字](地址)：返回 ] 与 ) 的位置。文字里不能再有 [（可含转义与行内代码）；地址不含空白，括号须配对
        private func linkEnd(after index: Int, in range: Range<Int>) -> (textEnd: Int, targetEnd: Int)? {
            var cursor = index + 1
            while cursor < range.upperBound, chars[cursor] != "]" {
                if chars[cursor] == "[" { return nil }
                cursor = skipped(at: cursor, in: range) ?? cursor + 1
            }
            let textEnd = cursor
            guard textEnd + 1 < range.upperBound, chars[textEnd + 1] == "(" else { return nil }
            return targetEnd(from: textEnd + 2, in: range).map { (textEnd, $0) }
        }

        /// 转义字符或完整的行内代码之后的位置；都不是时为 nil
        private func skipped(at cursor: Int, in range: Range<Int>) -> Int? {
            if escapedCharacter(at: cursor, in: range, ClipInlineMarkup.escapable) != nil { return cursor + 2 }
            guard chars[cursor] == "`", let close = codeEnd(after: cursor, in: range) else { return nil }
            return close + 1
        }

        /// 链接地址的结束 `)`：地址非空、不含空白、括号配对，且在范围内
        private func targetEnd(from start: Int, in range: Range<Int>) -> Int? {
            let end = closingParens[start]
            guard end > start, end < range.upperBound, end < nextWhitespace[start] else { return nil }
            return end
        }
    }
}

extension Array {
    /// 相邻且键相同的元素分为一组（保持顺序）
    fileprivate func consecutiveGroups<Key: Equatable>(by key: (Element) -> Key) -> [[Element]] {
        reduce(into: [[Element]]()) { groups, element in
            if let last = groups.last?.last, key(last) == key(element) {
                groups[groups.count - 1].append(element)
            } else {
                groups.append([element])
            }
        }
    }
}
