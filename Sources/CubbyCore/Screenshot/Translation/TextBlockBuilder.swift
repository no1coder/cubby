import CoreGraphics
import Foundation

// 识别出的行 → 翻译块（docs/TRANSLATION-DESIGN.md §3.2 第 6 步）。纯函数，实现线 T3 拥有。

public enum TextBlockBuilder {
    /// 每组是同一个最小容器（段落、列表项、表格单元格）里的行，组内顺序不限。
    /// 返回的块按阅读顺序（先上后下、同一行先左后右）从 0 连续编号；空行与空组被丢弃。
    /// 对齐：多行块由各行边缘推断；单行块借同列上下相邻的块推断（见 ColumnAlignment），没有证据时 leading
    public static func blocks(from groups: [[RecognizedLine]]) -> [TextBlock] {
        let cleaned = groups.compactMap { group -> [RecognizedLine]? in
            let lines = group.compactMap { line -> RecognizedLine? in
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : RecognizedLine(text: text, frame: line.frame)
            }
            return lines.isEmpty ? nil : lines.sorted(by: isAbove)
        }
        let ordered = readingOrder(cleaned)
        let frames = ordered.map { lines in lines.dropFirst().reduce(lines[0].frame) { $0.union($1.frame) } }
        let heights = ordered.map { TranslationMath.median($0.map(\.frame.height)) }
        return ordered.enumerated().map { index, lines in
            let alignment =
                lines.count > 1
                ? alignment(of: lines.map(\.frame))
                : ColumnAlignment.alignment(of: index, frames: frames, heights: heights) ?? .leading
            return TextBlock(id: index, lines: lines, alignment: alignment, text: joined(lines.map(\.text)))
        }
    }

    /// 按文字规则拼接各行：拉丁文字以空格连接，行尾连字符接小写字母时去掉连字符；
    /// CJK 行间（或 CJK 标点之后）直接相连；CJK 与拉丁文字相接时加空格
    public static func joined(_ lines: [String]) -> String {
        let parts = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.dropFirst().reduce(parts.first ?? "") { join($0, $1) }
    }

    /// 由各行外框推断对齐：左缘齐 → leading；中线齐 → center；右缘齐 → trailing；单行或都不齐 → leading。
    /// 「齐」= 最大差值 ≤ 0.5 × 中位行高
    public static func alignment(of frames: [CGRect]) -> TextBlockAlignment {
        guard frames.count > 1 else { return .leading }
        let tolerance = 0.5 * TranslationMath.median(frames.map(\.height))
        func aligned(_ values: [CGFloat]) -> Bool {
            (values.max() ?? 0) - (values.min() ?? 0) <= tolerance
        }
        if aligned(frames.map(\.minX)) { return .leading }
        if aligned(frames.map(\.midX)) { return .center }
        if aligned(frames.map(\.maxX)) { return .trailing }
        return .leading
    }

    // MARK: - 内部

    private static func isAbove(_ lhs: RecognizedLine, _ rhs: RecognizedLine) -> Bool {
        lhs.frame.midY != rhs.frame.midY ? lhs.frame.midY < rhs.frame.midY : lhs.frame.minX < rhs.frame.minX
    }

    /// 以各组首行分行：首行垂直中心落在某行锚点首行的上下边界内即同一行；行内从左到右
    private static func readingOrder(_ groups: [[RecognizedLine]]) -> [[RecognizedLine]] {
        let sorted = groups.sorted { $0[0].frame.minY < $1[0].frame.minY }
        let rows = sorted.reduce(into: [[[RecognizedLine]]]()) { rows, group in
            if let anchor = rows.last?.first?[0].frame, anchor.minY...anchor.maxY ~= group[0].frame.midY {
                rows[rows.count - 1].append(group)
            } else {
                rows.append([group])
            }
        }
        return rows.flatMap { row in row.sorted { $0[0].frame.minX < $1[0].frame.minX } }
    }

    private static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        if last == "-", let beforeHyphen = head.dropLast().last, beforeHyphen.isLetter || beforeHyphen.isNumber {
            // infor-\nmation → information；Apple-\nWatch、10-\n20 保留连字符
            return first.isLowercase && beforeHyphen.isLetter ? head.dropLast() + tail : head + tail
        }
        if TextScript.isCJK(last) && (TextScript.isCJK(first) || isCJKPunctuation(last)) {
            return head + tail
        }
        return head + " " + tail
    }

    /// CJK 标点与全角符号（其后不加空格）
    private static func isCJKPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let isFullwidthSymbol = (0xFF00...0xFFEF).contains(scalar.value) && !character.isLetter && !character.isNumber
        return (0x3000...0x303F).contains(scalar.value) || isFullwidthSymbol
    }
}
