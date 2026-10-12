import Foundation
import CubbyCore

/// 警示卡（TamperAlert 设计稿）的文案：有输入监控时说明「这期间你没有再复制」，没有时不这样断言
struct TamperAlertCopy {
    let incident: TamperIncident

    private var tamper: AddressGuard.Tamper { incident.tamper }

    static var title: String {
        String(localized: "The address in your clipboard was replaced", comment: "Title of the replacement warning")
    }

    /// 第一句：「你复制以太坊地址 0.4 秒后，剪贴板被换成了另一个以太坊地址。」
    var whatHappened: String {
        let elapsed = Self.elapsed(tamper.elapsed)
        let noun = SecurityCopy.name(tamper.original.value.kind, midSentence: true)
        return String(
            localized: "\(elapsed) after you copied this \(noun), the clipboard was replaced with another one.",
            comment: "Replacement warning. First %@ = elapsed time like “0.4 seconds”, second %@ = “Ethereum address”")
    }

    /// 第二句：前台应用没变；有输入监控时再加上「这期间你没有再复制」
    var why: String {
        let app =
            incident.appName ?? String(localized: "the same app", comment: "Replacement warning: unknown app name")
        if tamper.checkedKeystrokes {
            return String(
                localized:
                    "You haven't copied anything since, and \(app) stayed in front the whole time, so a background program most likely did it.",
                comment: "Replacement warning when Input Monitoring confirmed no ⌘C / ⌘X. %@ = frontmost app")
        }
        return String(
            localized: "\(app) stayed in front the whole time, so a background program may have done it.",
            comment: "Replacement warning without Input Monitoring. %@ = frontmost app")
    }

    static var checkFirst: String {
        String(localized: "Check before you paste.", comment: "Bold end of the replacement warning")
    }

    // MARK: - 对照两行

    static var youCopied: String {
        String(localized: "You copied", comment: "Replacement warning: label of the value you copied")
    }

    static var nowInClipboard: String {
        String(localized: "Now in your clipboard", comment: "Replacement warning: label of the replacing value")
    }

    /// 「Safari · 16:52:07」
    var originalMeta: String {
        let source = tamper.original.source?.name ?? TextStats.unknownSource
        return [source, Self.timeFormatter.string(from: tamper.original.date)].joined(separator: " · ")
    }

    /// 「以太坊 · 校验通过」
    var originalCheck: String {
        SecurityCopy.checkLine(tamper.original.value.kind, short: true)
    }

    /// 「来源未知（后台程序） · 16:52:07.4」
    var replacementMeta: String {
        let source = String(
            localized: "Unknown source (background program)", comment: "Replacement warning: source of the new value")
        return [source, Self.preciseTimeFormatter.string(from: tamper.date)].joined(separator: " · ")
    }

    /// 「开头结尾相同，中间 32 位不同」或「12 位不同」
    var difference: String {
        let original = tamper.original.value.value
        let replaced = tamper.replacement.value
        let count = AddressComparison.differingCount(original: original, replaced: replaced)
        if AddressComparison.sharesEnds(original: original, replaced: replaced) {
            return String(
                localized: "Same start and end, \(count) characters in the middle differ",
                comment: "Replacement warning: the new value only differs in the middle. %lld = characters")
        }
        return String(
            localized: "\(count) characters differ", comment: "Replacement warning: number of different characters")
    }

    static var footnote: String {
        String(
            localized:
                "Attackers often create addresses that start and end like yours to fool a quick check, so Cubby compares every character.",
            comment: "Footnote of the replacement warning")
    }

    // MARK: - 按钮

    static var viewLog: String {
        String(localized: "View Security Log", comment: "Link on the replacement warning: open Settings › Security")
    }

    static var changedMyself: String {
        String(localized: "I Changed It Myself", comment: "Button on the replacement warning")
    }

    static var restore: String {
        String(localized: "Restore What I Copied", comment: "Primary button on the replacement warning")
    }

    // MARK: - 时间

    /// 「0.4 秒」：一位小数
    static func elapsed(_ interval: TimeInterval) -> String {
        Duration.milliseconds(Int64((max(interval, 0) * 1000).rounded()))
            .formatted(
                .units(allowed: [.seconds], width: .wide, fractionalPart: .show(length: 1))
                    .locale(TimeFormatting.locale))
    }

    private static let timeFormatter = formatter("jmmss")
    /// 精确到 0.1 秒（被替换的时间）
    private static let preciseTimeFormatter = formatter("jmmssS")

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = TimeFormatting.locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
