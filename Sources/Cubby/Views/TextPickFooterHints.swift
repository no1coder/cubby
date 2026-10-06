import CubbyCore
import SwiftUI

/// 拆词卡打开时主面板底栏的按键提示（docs/TEXT-PICK-DESIGN.md §3）：「↩ 粘贴所选到 <App>」「⌘C 复制」「⌘A 全选」
/// 「esc 关闭」。放不下时依次隐藏 esc → ⌘A → ⌘C
struct TextPickFooterHints: View {
    /// 从完整到紧凑的几档
    enum Level: Int, CaseIterable {
        case full
        case withoutEscape
        case withoutSelectAll
        case minimal

        var showsEscape: Bool { self == .full }
        var showsSelectAll: Bool { rawValue < Level.withoutSelectAll.rawValue }
        var showsCopy: Bool { rawValue < Level.minimal.rawValue }
    }

    /// 直接粘贴的目标应用；nil 表示 ↩ 只复制
    let target: PasteTarget?
    let level: Level

    private static let appIconSize: CGFloat = 13
    private static let targetMaxWidth: CGFloat = 120
    /// 与底栏其他内联图标一致的基线偏移
    private static let iconBaselineOffset: CGFloat = -2.5

    var body: some View {
        HStack(spacing: 10) {
            primaryHint
            if level.showsCopy {
                KeyHint(keys: "⌘C", label: Self.copyLabel).layoutPriority(1)
            }
            if level.showsSelectAll {
                KeyHint(keys: "⌘A", label: Self.selectAllLabel).layoutPriority(1)
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
                    "Paste selection to \(appIcon(target)) \(appName(target))",
                    comment: "Footer hint for ↩ while the pick-words card is open. %1$@ = app icon, %2$@ = app name"
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
            .baselineOffset(Self.iconBaselineOffset)
    }

    private func appName(_ target: PasteTarget) -> Text {
        Text(verbatim: target.name)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
    }

    static var copyLabel: String {
        String(
            localized: "footer.copyPicked", defaultValue: "Copy",
            comment: "Footer hint for ⌘C while the pick-words card is open. Keep it short.")
    }

    static var selectAllLabel: String {
        String(
            localized: "footer.selectAllWords", defaultValue: "Select all",
            comment: "Footer hint for ⌘A while the pick-words card is open. Keep it short.")
    }

    static var closeLabel: String {
        String(
            localized: "footer.closePick", defaultValue: "Close",
            comment: "Footer hint for esc while the pick-words card is open. Keep it short.")
    }
}
