import Foundation

/// 纯文本条目的一个翻译单元
public struct ClipTextSegment: Equatable, Sendable {
    public let index: Int
    /// 原文中被译文替换的范围（不含行首标记、缩进与行尾空白）
    public let range: Range<String.Index>
    /// 该范围内的原文
    public let original: String
    /// 送去翻译的文字：硬换行的段落合并为一行，其余与 original 相同
    public let source: String
    /// 代码、网址、没有字母的行原样保留，不送翻译
    public let isTranslatable: Bool
}

/// 纯文本分段（docs/CLIP-TRANSLATION-DESIGN.md §2.1，纯函数）：
/// - 空行分段；段内若是硬换行（除末行外各行显示宽度接近且够宽、非列表项、少有句末标点）则合并为一块，否则逐行成块；
/// - 列表 / 引用 / 标题标记、缩进与行尾空白留在原文里，不送翻译；
/// - 代码行（含代码围栏内、整块像代码的段）、网址、没有字母的行原样保留、不送翻译。
/// `join(original:segments:)` 按原文的分隔符拼回；传入各段原文时结果与原文逐字相同
public enum ClipTextSegmenter {
    /// 分段算法版本，写入 ClipTranslation.segmentation；改动分段规则时递增
    public static let version = 1

    /// 硬换行判定：非末行的显示宽度（汉字等宽字符计 2）至少为最宽行的该比例
    static let wrapRatio = 0.7
    /// 硬换行判定：最宽的非末行至少这么宽（显示列）
    static let minWrapColumns = 40

    public static func segments(of text: String) -> [ClipTextSegment] {
        let lines = ClipTextLine.lines(of: text)
        let groups = blocks(of: lines).flatMap { groupsInBlock($0, text: text) }
        return groups.enumerated().map { index, group in
            makeSegment(index: index, group: group, text: text)
        }
    }

    /// 用译文替换各段（nil、空串、越界或不翻译的段用原文），段与段之间的原文（换行、空行、标记、缩进）原样保留
    public static func join(original: String, segments translations: [String?]) -> String {
        join(original: original, segments: segments(of: original), translations: translations)
    }

    /// 同上，分段已算好（segments 必须来自同一原文）
    static func join(original: String, segments: [ClipTextSegment], translations: [String?]) -> String {
        let pieces = segments.reduce(into: (text: "", cursor: original.startIndex)) { state, segment in
            let translated = translations.indices.contains(segment.index) ? translations[segment.index] : nil
            let usable = translated.flatMap { $0.isEmpty ? nil : $0 }
            let replacement = segment.isTranslatable ? usable ?? segment.original : segment.original
            state.text += original[state.cursor..<segment.range.lowerBound]
            state.text += replacement
            state.cursor = segment.range.upperBound
        }
        return pieces.text + original[pieces.cursor...]
    }

    // MARK: - 分组

    /// 一组连续行构成一段
    private struct Group {
        let lines: [ClipTextLine]
        let isTranslatable: Bool
        let isWrapped: Bool
    }

    /// 以空行分块（块内行连续，不含空行）；代码围栏自成一块（围栏内的空行不分块）
    private static func blocks(of lines: [ClipTextLine]) -> [[ClipTextLine]] {
        lines.reduce(into: [[ClipTextLine]]()) { blocks, line in
            guard line.kind != .blank else {
                if blocks.last?.isEmpty == false { blocks.append([]) }
                return
            }
            let continues = blocks.last.map { block in
                block.last.map { ($0.kind == .fenced) == (line.kind == .fenced) } ?? true
            }
            if continues == true {
                blocks[blocks.count - 1].append(line)
            } else {
                blocks.append([line])
            }
        }.filter { !$0.isEmpty }
    }

    /// 整块判定为代码至少需要的行数（行数太少时 TextHeuristics 容易把散文误判为代码）
    static let minCodeBlockLines = 3

    /// 块内分组：代码围栏、整块像代码时整块原样保留；否则连续的原样行合为一组，带标记的行各自一组，
    /// 连续的普通行按硬换行合并或逐行
    private static func groupsInBlock(_ block: [ClipTextLine], text: String) -> [Group] {
        let blockText = String(text[block[0].range.lowerBound..<block[block.count - 1].range.upperBound])
        if block[0].kind == .fenced || (block.count >= minCodeBlockLines && TextHeuristics.looksLikeCode(blockText)) {
            return [Group(lines: block, isTranslatable: false, isWrapped: false)]
        }
        let runs = block.reduce(into: [[ClipTextLine]]()) { runs, line in
            if let last = runs.last?.last, line.kind == last.kind, line.kind != .marked {
                runs[runs.count - 1].append(line)
            } else {
                runs.append([line])
            }
        }
        return runs.flatMap { run -> [Group] in
            switch run[0].kind {
            case .verbatim, .blank, .fenced:
                return [Group(lines: run, isTranslatable: false, isWrapped: false)]
            case .marked:
                return [Group(lines: run, isTranslatable: true, isWrapped: false)]
            case .prose:
                guard isHardWrapped(run, text: text) else {
                    return run.map { Group(lines: [$0], isTranslatable: true, isWrapped: false) }
                }
                return [Group(lines: run, isTranslatable: true, isWrapped: true)]
            }
        }
    }

    private static func makeSegment(index: Int, group: Group, text: String) -> ClipTextSegment {
        let range = group.lines[0].content.lowerBound..<group.lines[group.lines.count - 1].content.upperBound
        let original = String(text[range])
        let source = group.isWrapped ? unwrap(group.lines.map { text[$0.content] }) : original
        return ClipTextSegment(
            index: index, range: range, original: original, source: source, isTranslatable: group.isTranslatable)
    }

    // MARK: - 硬换行

    private static let sentenceEndings: Set<Character> = [
        ".", "!", "?", ":", "\u{2026}", "\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{FF1A}",
    ]

    /// 多行、非末行都够宽且宽度接近、末行不比它们宽、非末行至多三分之一以句末标点结尾
    static func isHardWrapped(_ run: [ClipTextLine], text: String) -> Bool {
        guard run.count > 1 else { return false }
        let contents = run.map { text[$0.content] }
        let heads = contents.dropLast()
        let widths = heads.map(displayColumns)
        guard let widest = widths.max(), widest >= minWrapColumns,
            widths.allSatisfy({ Double($0) >= Double(widest) * wrapRatio }),
            displayColumns(contents[contents.count - 1]) <= widest + 2
        else { return false }
        let endings = heads.filter { $0.last.map(sentenceEndings.contains) == true }.count
        return endings * 3 <= heads.count
    }

    /// 显示宽度：东亚宽字符计 2 列，其余计 1 列
    static func displayColumns(_ text: Substring) -> Int {
        text.reduce(0) { $0 + ($1.unicodeScalars.first.map(isWide) == true ? 2 : 1) }
    }

    /// 合并硬换行的各行：两侧有东亚宽字符时直接相连；行尾「字母-」接小写字母开头时去掉连字符相连；其余以空格相连
    static func unwrap(_ lines: [Substring]) -> String {
        lines.dropFirst().reduce(String(lines[0])) { joined, line in
            guard let last = joined.last, let first = line.first else { return joined + line }
            if isWide(last.unicodeScalars.first ?? " ") || isWide(first.unicodeScalars.first ?? " ") {
                return joined + line
            }
            let beforeHyphen = joined.dropLast().last
            if last == "-", beforeHyphen?.isLetter == true, first.isLowercase {
                return String(joined.dropLast()) + line
            }
            return joined + " " + line
        }
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD,
    ]

    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        wideRanges.contains { $0.contains(scalar.value) }
    }
}
