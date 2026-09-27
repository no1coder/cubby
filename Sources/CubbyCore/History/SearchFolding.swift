import Foundation

/// 搜索用的字符串折叠：忽略大小写与变音符（与 localizedStandardContains 相同的选项），
/// 结果保存为连续 UTF-8，查找只需字节级子串匹配（memmem），比逐次 ICU 比较快一个数量级。
///
/// 折叠 + 字节匹配与 localizedStandardContains 在绝大多数字符上结果相同。已知不同的（逐字符穷举验证）：
/// - 各书写系统的数字、全角数字、上下标、带圈数字：ICU 按数值与 ASCII 数字等价；
/// - 大小写映射会展开成多个字符的 ß、ẞ、ŉ、İ、连字等：折叠后可被部分匹配；
/// - 部分较新书写系统（BMP 以外）的大小写；
/// - 查询中单独出现的非拉丁组合符号（如天城文的鼻化符）。
/// 含前三类字符的条目、含任意一类的查询改走逐条 localizedStandardContains，保证结果完全一致。
enum SearchFolding {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// 折叠后的 UTF-8 字节（查询关键词、整句用）
    static func foldedBytes(_ text: some StringProtocol, locale: Locale) -> [UInt8] {
        Array(text.folding(options: options, locale: locale).utf8)
    }

    /// 条目文字是否含折叠语义不一致的字符（纯 ASCII 快速返回）
    static func requiresExactMatch(_ text: some StringProtocol) -> Bool {
        guard !text.utf8.allSatisfy({ $0 < 0x80 }) else { return false }
        return text.unicodeScalars.contains(where: isExactOnly)
    }

    /// 查询关键词能否走索引：不含上述字符与非拉丁组合符号，也不以组合符号开头（单独的附加符号）
    static func isIndexable(keyword: String) -> Bool {
        guard let first = keyword.unicodeScalars.first, !isMark(first) else { return false }
        return !keyword.unicodeScalars.contains { isExactOnly($0) || isNonLatinMark($0) }
    }

    /// 该字符在折叠 + 字节匹配下可能与 localizedStandardContains 结果不同
    static func isExactOnly(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        // ASCII 与常用中日韩字符（汉字、假名、韩文音节）已逐字验证一致，免去属性查询
        if value < 0x80 || (0x3040...0x30FF).contains(value) || (0x3400...0x9FFF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
        {
            return false
        }
        let properties = scalar.properties
        if properties.numericType != nil { return true }
        guard properties.changesWhenCaseMapped else { return false }
        if value > 0xFFFF { return true }
        return expandsWhenCaseMapped(properties)
    }

    /// 大小写映射展开为多个字符（ß → SS、ŉ → ʼN、İ → i̇、ﬁ → FI），或小写形式会展开（ẞ → ß → SS）
    private static func expandsWhenCaseMapped(_ properties: Unicode.Scalar.Properties) -> Bool {
        let lower = properties.lowercaseMapping.unicodeScalars
        if properties.uppercaseMapping.unicodeScalars.count > 1 || lower.count > 1 { return true }
        guard let single = lower.first else { return false }
        return single.properties.uppercaseMapping.unicodeScalars.count > 1
    }

    /// 非拉丁组合符号；拉丁组合附加符号（U+0300–U+036F）跟在字母后时已验证一致
    private static func isNonLatinMark(_ scalar: Unicode.Scalar) -> Bool {
        isMark(scalar) && !(0x300...0x36F).contains(scalar.value)
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }
}

/// 一段折叠后的文字（连续 UTF-8 字节）
struct FoldedText: Sendable, Equatable {
    let bytes: [UInt8]
    /// 折叠后前 leadingWindow 个字符所占的字节数：匹配起点小于它即为「靠前」
    let leadingLimit: Int

    init(_ text: some StringProtocol, locale: Locale) {
        let folded = text.folding(options: SearchFolding.options, locale: locale)
        let end =
            folded.index(folded.startIndex, offsetBy: ClipSearchRanking.leadingWindow, limitedBy: folded.endIndex)
            ?? folded.endIndex
        leadingLimit = folded.utf8.distance(from: folded.startIndex, to: end)
        bytes = Array(folded.utf8)
    }

    /// 从 offset 起第一次出现 needle 的字节位置
    func firstMatch(of needle: [UInt8], from offset: Int) -> Int? {
        guard !needle.isEmpty, bytes.count - offset >= needle.count else { return nil }
        return bytes.withUnsafeBufferPointer { haystack in
            needle.withUnsafeBufferPointer { pin in
                guard let base = haystack.baseAddress, let pinBase = pin.baseAddress,
                    let found = memmem(base + offset, haystack.count - offset, pinBase, pin.count)
                else { return nil }
                return base.distance(to: found.assumingMemoryBound(to: UInt8.self))
            }
        }
    }
}
