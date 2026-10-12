import Foundation

/// 链接条目的网页标题：只取浏览器复制链接时一并放上剪贴板的标题（public.url-name / WebURLsWithTitlesPboardType），
/// Cubby 不联网，不会去抓取网页。这里只有纯函数：规范化标题、比较链接、解析标题列表
public enum LinkTitle {
    /// 标题最多保留的字符数（字形簇），超出时截断并以省略号结尾
    public static let maxLength = 300

    /// 规范化：去掉首尾空白、内部连续空白（含换行与控制字符）折叠为一个空格、限制长度。
    /// 为空或只是链接本身（忽略协议、末尾斜杠、大小写与百分号编码）时返回 nil
    public static func normalized(_ raw: String?, url: String) -> String? {
        guard let raw, let collapsed = collapsed(raw), !isSameURL(collapsed, url) else { return nil }
        return collapsed
    }

    /// 两段文字是否指向同一链接：比较时忽略首尾空白、协议、末尾斜杠、大小写与百分号编码
    public static func isSameURL(_ lhs: String, _ rhs: String) -> Bool {
        let key = comparableKey(lhs)
        return !key.isEmpty && key == comparableKey(rhs)
    }

    /// 解析 WebURLsWithTitlesPboardType（plist：[[链接], [标题]]）：取第一个链接匹配且规范化后可用的标题；
    /// 结构不对时返回 nil
    public static func fromWebURLsWithTitles(_ plist: Any?, url: String) -> String? {
        guard let lists = plist as? [Any], lists.count >= 2,
            let urls = lists[0] as? [String],
            let titles = lists[1] as? [String]
        else { return nil }
        return zip(urls, titles).lazy
            .filter { isSameURL($0.0, url) }
            .compactMap { normalized($0.1, url: url) }
            .first
    }

    /// 从剪贴板上的两种来源中取标题：优先 public.url-name，其次标题列表（只在前者不可用时才读取）
    public static func resolve(urlName: String?, webURLsWithTitles: @autoclosure () -> Any?, url: String) -> String? {
        normalized(urlName, url: url) ?? fromWebURLsWithTitles(webURLsWithTitles(), url: url)
    }

    // MARK: - 内部实现

    /// 折叠空白并限制长度；只扫描到超出上限为止，MB 级输入也不会全量处理。全是空白时返回 nil
    private static func collapsed(_ raw: String) -> String? {
        var result = ""
        var count = 0
        var pendingSpace = false
        for character in raw {
            if isSeparator(character) {
                pendingSpace = count > 0
                continue
            }
            if pendingSpace {
                result.append(" ")
                count += 1
                pendingSpace = false
            }
            result.append(character)
            count += 1
            if count > maxLength { break }
        }
        guard count > 0 else { return nil }
        guard count > maxLength else { return result }
        // 截断处若是空格一并去掉，再补省略号，总长不超过 maxLength
        let head = result.prefix(maxLength - 1)
        return String(head.last == " " ? head.dropLast() : head) + "…"
    }

    /// 空白（含换行、不换行空格、全角空格）与控制字符都视为分隔
    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .control }
    }

    /// 比较用的形式：解码百分号编码、转小写、去掉协议与末尾斜杠
    private static func comparableKey(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = (trimmed.removingPercentEncoding ?? trimmed).lowercased()
        let withoutScheme = droppingScheme(lowered)
        return withoutScheme.hasSuffix("/") ? String(withoutScheme.dropLast()) : withoutScheme
    }

    /// 只去掉开头的「协议://」（协议名以字母开头，由字母、数字、+ - . 组成）；
    /// 句中出现的链接不算，避免「Mirror of https://…」被误认作链接本身
    private static func droppingScheme(_ string: String) -> String {
        guard let separator = string.range(of: "://") else { return string }
        let scheme = string[..<separator.lowerBound]
        guard let first = scheme.first, first.isASCII, first.isLetter,
            scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
        else { return string }
        return String(string[separator.upperBound...])
    }
}
