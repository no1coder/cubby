import Foundation

/// 拆词结果的拼接规则（docs/TEXT-PICK-DESIGN.md P8）：
/// - 相邻选中的块（中间只有空白）按原文连成一段，保留原有空格与换行；
/// - 段与段之间：原文间隔含换行 → 一个换行；两侧字符都是中日韩文字 → 直接相连；否则 → 一个空格
public enum TextPickResult {
    public static func text(of document: TextPickDocument, selection: TextPickSelection) -> String {
        let tokens = document.tokens
        let picked = selection.sortedIndices.filter(tokens.indices.contains)
        guard let first = picked.first else { return "" }
        // 逐段追加（全选上万块时不能每步复制整串）
        return zip(picked, picked.dropFirst()).reduce(into: tokens[first].text) { result, pair in
            let (previous, current) = pair
            // 防御：块按顺序且不重叠（分词已对齐字符边界），万一重叠也不构造反向区间
            let gapStart = min(tokens[previous].range.upperBound, tokens[current].range.lowerBound)
            let gap = document.text[gapStart..<tokens[current].range.lowerBound]
            result +=
                current == previous + 1
                ? String(gap)
                : joiner(gap: gap, before: result.last, after: tokens[current].text.first)
            result += tokens[current].text
        }
    }

    /// 段与段之间的连接
    private static func joiner(gap: Substring, before: Character?, after: Character?) -> String {
        if gap.contains(where: \.isNewline) {
            return "\n"
        }
        guard let before, let after, isCJK(before), isCJK(after) else { return " " }
        return ""
    }

    /// 中日韩文字：汉字（含扩展区与兼容区）、假名、谚文、注音，以及中日韩标点与全角形式
    static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return cjkRanges.contains { $0.contains(scalar.value) }
    }

    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11FF,  // 谚文字母
        0x2E80...0x2FDF,  // 中日韩部首
        0x3000...0x303F,  // 中日韩符号与标点
        0x3040...0x30FF,  // 平假名、片假名
        0x3100...0x31FF,  // 注音、谚文兼容字母、片假名扩展
        0x3400...0x4DBF,  // 扩展 A
        0x4E00...0x9FFF,  // 统一汉字
        0xAC00...0xD7AF,  // 谚文音节
        0xF900...0xFAFF,  // 兼容汉字
        0xFE30...0xFE4F,  // 中日韩兼容形式（竖排标点）
        0xFF00...0xFFEF,  // 半角与全角形式
        0x20000...0x3134F,  // 扩展 B 及以后
    ]
}
