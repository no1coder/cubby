import CubbyCore
import Foundation

/// 拆词的界面文案（docs/TEXT-PICK-DESIGN.md P1、§3）：中文「拆词」，英文「Pick Words」
enum TextPickCopy {
    /// 卡片标题、右键菜单项、读屏操作
    static var title: String {
        String(localized: "Pick Words", comment: "Title of the pick-words card, context menu item and VoiceOver action")
    }

    /// 不支持的条目：底栏提示与卡片状态页（P4）
    static var noText: String {
        String(
            localized: "This item has no text to pick",
            comment: "Shown when an item (link, color, file, image without text) has no words to pick")
    }

    // MARK: - 头部

    /// 副标题「42 个词 · 点选或拖过来选取」；超过 20,000 个字符时后半句换成「只显示前 20,000 个字符」（P6）
    static func subtitle(words: Int, isTruncated: Bool) -> String {
        guard isTruncated else {
            return String(
                localized: "\(words) words · Click or drag to pick",
                comment: "Pick-words card subtitle: number of words and how to pick them")
        }
        let limit = TextPickDocument.characterLimit.formatted()
        return String(
            localized: "\(words) words · Showing the first \(limit) characters",
            comment: "Pick-words card subtitle when the text is too long. %1$lld = words, %2$@ = 20,000")
    }

    static var selectAll: String {
        String(localized: "Select All", comment: "Pick-words card: button that selects every word")
    }

    // MARK: - 结果条与底栏

    /// 结果条里包住结果的引号（中文为「」）
    static func quoted(_ text: String) -> String {
        String(localized: "“\(text)”", comment: "Pick-words result strip: the picked text in quotation marks")
    }

    static func characterCount(_ count: Int) -> String {
        String(localized: "\(count) characters", comment: "Length of a text item")
    }

    /// 「已选 5 个词 · 23 个字符」
    static func selectionSummary(words: Int, characters: Int) -> String {
        String(
            localized: "\(words) words · \(characters) characters selected",
            comment: "Pick-words card footer. %1$lld = picked words, %2$lld = characters of the result")
    }

    static var copyButton: String {
        String(localized: "pick.copy", defaultValue: "Copy", comment: "Pick-words card: copy the picked words")
    }

    static var pasteButton: String {
        String(localized: "pick.paste", defaultValue: "Paste", comment: "Pick-words card: paste the picked words")
    }

    static var copyTooltip: String {
        String(localized: "Copy the picked words (⌘C)", comment: "Tooltip of the Copy button in the pick-words card")
    }

    static func pasteTooltip(app: String?) -> String {
        guard let app else {
            return String(
                localized: "Paste the picked words (↩)", comment: "Tooltip of the Paste button in the pick-words card")
        }
        return String(
            localized: "Paste the picked words into \(app) (↩)",
            comment: "Tooltip of the Paste button in the pick-words card. %@ = target app")
    }

    /// 复制后的底栏轻提示（P9）
    static func copied(characters: Int) -> String {
        String(
            localized: "Copied \(characters) characters", comment: "Footer toast after copying the picked words")
    }

    static var copyFailed: String {
        String(localized: "Couldn't copy", comment: "Error when copying an item")
    }

    // MARK: - 读屏

    static var canvasLabel: String {
        String(localized: "Words", comment: "VoiceOver label of the word chips area in the pick-words card")
    }

    static var selectedValue: String {
        String(localized: "Selected", comment: "VoiceOver value of a picked word chip")
    }

    static var tokenHelp: String {
        String(localized: "Press to pick or unpick this word", comment: "VoiceOver hint of a word chip")
    }
}
