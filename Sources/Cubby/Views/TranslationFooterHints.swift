import SwiftUI
import CubbyCore

/// 翻译卡打开时底栏的按键提示（原型 renderFooter）：「↩ 粘贴译文到 <App>」「⌘C 复制译文」「⌘S 存为新条目」
/// 「⇧↩ 纯文本」「esc 关闭」。放不下时按原型优先级依次隐藏：数量 → esc → ⇧↩ → ⌘S → ⌘C
struct TranslationFooterHints: View {
    /// 从完整到紧凑的几档
    enum Level: Int, CaseIterable {
        case full
        case withoutCount
        case withoutEscape
        case withoutPlainText
        case withoutSave
        case minimal

        var showsCount: Bool { self == .full }
        var showsEscape: Bool { rawValue < Level.withoutEscape.rawValue }
        var showsPlainText: Bool { rawValue < Level.withoutPlainText.rawValue }
        var showsSave: Bool { rawValue < Level.withoutSave.rawValue }
        var showsCopy: Bool { rawValue < Level.minimal.rawValue }
    }

    /// 直接粘贴的目标应用；nil 表示 ↩ 只复制
    let target: PasteTarget?
    let level: Level

    private static let appIconSize: CGFloat = 13
    private static let targetMaxWidth: CGFloat = 120

    var body: some View {
        HStack(spacing: 10) {
            primaryHint
            if level.showsCopy {
                KeyHint(keys: "⌘C", label: Self.copyLabel).layoutPriority(1)
            }
            if level.showsSave {
                KeyHint(keys: "⌘S", label: Self.saveLabel).layoutPriority(1)
            }
            if level.showsPlainText {
                KeyHint(keys: "⇧↩", label: Self.plainTextLabel).layoutPriority(1)
            }
            if level.showsEscape {
                KeyHint(keys: "esc", label: Self.closeLabel).layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private var primaryHint: some View {
        if let target {
            HStack(spacing: 4) {
                KeyCap(text: "↩", prominent: true)
                Text(
                    "Paste translation to \(appIcon(target)) \(appName(target))",
                    comment: "Footer hint for ↩ while the translation card is open. %1$@ = app icon, %2$@ = app name"
                )
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.targetMaxWidth, alignment: .leading)
                .fixedSize()
            }
            .accessibilityElement(children: .combine)
        } else {
            KeyHint(keys: "↩", label: Self.copyLabel)
        }
    }

    private func appIcon(_ target: PasteTarget) -> Text {
        Text(Image(nsImage: ImageCache.shared.appIcon(bundleID: target.bundleID, pointSize: Self.appIconSize)))
            .baselineOffset(-2.5)
    }

    private func appName(_ target: PasteTarget) -> Text {
        Text(verbatim: target.name)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
    }

    static var translatePasteLabel: String {
        String(
            localized: "footer.translateAndPaste", defaultValue: "Translate",
            comment: "Footer hint for ⌥↩: translate, then paste. Keep it short.")
    }

    static var copyLabel: String {
        String(
            localized: "footer.copyTranslation", defaultValue: "Copy",
            comment: "Footer hint for ⌘C while the translation card is open. Keep it short.")
    }

    static var saveLabel: String {
        String(
            localized: "footer.saveTranslation", defaultValue: "Save",
            comment: "Footer hint for ⌘S while the translation card is open: save as a new item. Keep it short.")
    }

    static var plainTextLabel: String {
        String(
            localized: "footer.translationPlainText", defaultValue: "Plain text",
            comment: "Footer hint for ⇧↩ while the translation card is open. Keep it short.")
    }

    static var closeLabel: String {
        String(
            localized: "footer.closeTranslation", defaultValue: "Close",
            comment: "Footer hint for esc while the translation card is open. Keep it short.")
    }
}

/// 「按住 [⌥] 预览译文」
struct HoldOptionHint: View {
    var body: some View {
        HStack(spacing: 4) {
            Text(
                String(
                    localized: "footer.holdBefore", defaultValue: "Hold",
                    comment: "Footer hint “Hold [⌥] to preview”, before the key cap"))
            KeyCap(text: "⌥")
            Text(
                String(
                    localized: "footer.holdAfter", defaultValue: "preview",
                    comment: "Footer hint “Hold [⌥] to preview the translation”, after the key cap. Keep it short."))
        }
        .font(.system(size: FontSize.caption))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
