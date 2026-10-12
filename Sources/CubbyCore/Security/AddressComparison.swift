import Foundation

/// 两个同类型敏感值的逐位比对（警示卡把不同的区段标红）与分组显示
public enum AddressComparison {
    /// 首尾各比较的字符数
    private static let endLength = 4
    private static let groupLength = 4
    private static let hexPrefix = "0x"
    /// 缩写保留的开头与结尾字符数
    private static let abbreviationHead = 6
    private static let abbreviationTail = 4
    /// 超过这个长度才缩写
    private static let abbreviationThreshold = 12

    /// replaced 中与 original 不同的字符区段（字符偏移，半开区间，按顺序、互不重叠）。长度不同时多出的部分也算不同
    public static func differingRanges(original: String, replaced: String) -> [Range<Int>] {
        let lhs = Array(original)
        let rhs = Array(replaced)
        var ranges: [Range<Int>] = []
        var start: Int?
        for index in rhs.indices {
            let differs = index >= lhs.count || lhs[index] != rhs[index]
            if differs, start == nil {
                start = index
            } else if !differs, let begin = start {
                ranges.append(begin..<index)
                start = nil
            }
        }
        if let begin = start {
            ranges.append(begin..<rhs.count)
        }
        return ranges
    }

    /// 不同的字符数（警示卡「中间 32 位不同」）
    public static func differingCount(original: String, replaced: String) -> Int {
        differingRanges(original: original, replaced: replaced).reduce(0) { $0 + $1.count }
    }

    /// 开头与结尾都相同（攻击者常用的「首尾相同」地址）：首尾各至少 4 个字符相同且整串不同
    public static func sharesEnds(original: String, replaced: String) -> Bool {
        let lhs = Array(original)
        let rhs = Array(replaced)
        let minimum = endLength * 2
        guard lhs != rhs, lhs.count >= minimum, rhs.count >= minimum else { return false }
        return lhs.prefix(endLength) == rhs.prefix(endLength) && lhs.suffix(endLength) == rhs.suffix(endLength)
    }

    /// 等宽分组显示：4 个字符一组；以太坊等 0x 开头的把 0x 并入第一组（0x7a3F 9c21 …）
    public static func groups(_ value: String) -> [String] {
        var characters = Array(value)
        var result: [String] = []
        if value.hasPrefix(hexPrefix) {
            let firstLength = hexPrefix.count + groupLength
            result.append(String(characters.prefix(firstLength)))
            characters = Array(characters.dropFirst(firstLength))
        }
        for start in stride(from: 0, to: characters.count, by: groupLength) {
            result.append(String(characters[start..<min(start + groupLength, characters.count)]))
        }
        return result
    }

    /// 缩写：前 6 个字符 + … + 后 4 个字符（0x7a3F…92E1）；不长于 12 个字符时原样返回
    public static func abbreviated(_ value: String) -> String {
        guard value.count > abbreviationThreshold else { return value }
        return String(value.prefix(abbreviationHead)) + "\u{2026}" + String(value.suffix(abbreviationTail))
    }
}
