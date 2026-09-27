import Foundation

/// 根据文本内容判断条目类型（链接 / 颜色 / 普通文本）
public enum ContentClassifier {
    private static let linkSchemes: Set<String> = ["http", "https"]

    public static func kind(forText text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ColorText.parse(trimmed) != nil { return .color }
        if isLink(trimmed) { return .link }
        return .text
    }

    static func isLink(_ string: String) -> Bool {
        guard !string.isEmpty,
            !string.contains(where: \.isWhitespace),
            let url = URL(string: string),
            let scheme = url.scheme?.lowercased(),
            let host = url.host, !host.isEmpty
        else { return false }
        return linkSchemes.contains(scheme)
    }
}
