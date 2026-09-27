import Foundation

/// 判断行内代码是否是按键或快捷键（`⌘T`、`⇧⌘2`、`esc`、`↩`、`Page Up`），是则画成键帽。
/// 以空格分隔的多个按键（`⌃P ⌃N`、`⇥ / ⇧⇥`）各画一个键帽，分隔符保持普通文字。
enum GuideKeyPattern {
    struct Segment: Equatable {
        let text: String
        let isKey: Bool
    }

    /// 超过这个长度的行内代码不当作按键
    private static let maxLength = 24
    private static let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
    private static let functionPrefix = "fn"
    private static let namedKeys: Set<String> = [
        "esc", "escape", "space", "tab", "return", "enter", "delete", "forward delete", "backspace",
        "home", "end", "page up", "page down", "fn", "caps lock", "command", "shift", "option", "control",
    ]
    /// 界面语言里的按键名：使用说明与界面同一语言，简体中文版把 Space 写作「空格」
    private static let localizedNames: Set<String> = [
        String(localized: "Space", comment: "Key name as written in the user guide, shown in a key cap").lowercased()
    ]
    /// 按键之间的连接符
    private static let separators: Set<String> = ["/", "–", "-", "…", "+", "·"]
    /// 从这个码位起视为中日韩文字：单个汉字不是按键
    private static let cjkStart: UInt32 = 0x2E80

    /// nil 表示不是按键，按普通行内代码显示
    static func segments(of code: String) -> [Segment]? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        if isKey(trimmed) {
            return [Segment(text: trimmed, isKey: true)]
        }
        let tokens = trimmed.split(separator: " ").map(String.init)
        guard tokens.count > 1, tokens.allSatisfy({ isKey($0) || separators.contains($0) }),
            tokens.contains(where: isKey)
        else { return nil }
        return join(tokens)
    }

    static func isKey(_ token: String) -> Bool {
        var rest = Substring(token)
        if rest.lowercased().hasPrefix(functionPrefix), rest.count > functionPrefix.count {
            rest = rest.dropFirst(functionPrefix.count)
        }
        let withoutModifiers = rest.drop { modifiers.contains($0) }
        if withoutModifiers.isEmpty {
            return !rest.isEmpty
        }
        if withoutModifiers.count == 1, let scalar = withoutModifiers.unicodeScalars.first {
            return scalar.value < cjkStart && !scalar.properties.isWhitespace
        }
        let name = withoutModifiers.lowercased()
        return namedKeys.contains(name) || localizedNames.contains(name) || isFunctionKey(name) || isDigitRange(name)
    }

    /// F1…F19
    private static func isFunctionKey(_ name: String) -> Bool {
        guard name.hasPrefix("f"), let number = Int(name.dropFirst()) else { return false }
        return (1...19).contains(number)
    }

    /// `⌘1–9` 之类的数字范围
    private static func isDigitRange(_ name: String) -> Bool {
        let characters = Array(name.filter { !$0.isWhitespace })
        guard characters.count == 3 else { return false }
        return characters[0].isASCII && characters[0].isNumber && characters[2].isASCII && characters[2].isNumber
            && separators.contains(String(characters[1]))
    }

    /// 按键各成一段，分隔符与空格合并为普通文字
    private static func join(_ tokens: [String]) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        for (index, token) in tokens.enumerated() {
            if index > 0 { plain += " " }
            if !separators.contains(token), isKey(token) {
                if !plain.isEmpty { segments.append(Segment(text: plain, isKey: false)) }
                plain = ""
                segments.append(Segment(text: token, isKey: true))
            } else {
                plain += token
            }
        }
        if !plain.isEmpty { segments.append(Segment(text: plain, isKey: false)) }
        return segments
    }
}
