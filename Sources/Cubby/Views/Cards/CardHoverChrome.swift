import CubbyCore
import SwiftUI

/// 悬停快捷操作：收藏 ⌘P / 预览 空格 / 删除 ⌘⌫；图片卡另有「贴到屏幕」
struct CardQuickActions {
    /// 图片网格的工具条没有收藏与预览（设计稿：晾到绳上 / 贴到屏幕 / 删除），为 nil
    let toggleFavorite: (() -> Void)?
    let togglePreview: (() -> Void)?
    let delete: () -> Void
    /// 只有图片卡提供
    let pinToScreen: (() -> Void)?
    /// 这张卡片的预览正在显示（预览按钮显示为按下状态）
    let isPreviewing: Bool
}

/// 悬停叠层：自带悬停状态，鼠标进出只重绘这一层。未选中时叠一层淡淡的高亮；
/// 右上角浮出快捷操作工具条（面板是 key window，可以用 onHover）
struct CardHoverChrome: View {
    let item: ClipItem
    let isSelected: Bool
    let actions: CardQuickActions

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forcedHoverItemID) private var forcedHoverItemID
    @State private var hoverState = false

    /// 截图走查可以指定一张卡片保持悬停状态（正式构建里 forcedHoverItemID 总是 nil）
    private var isHovered: Bool {
        hoverState || forcedHoverItemID == item.id
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.primary.opacity(highlightOpacity))
            .allowsHitTesting(false)
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    CardHoverToolbar(item: item, actions: actions)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .onHover { hoverState = $0 }
            .animation(Motion.animation(.easeOut(duration: Motion.fade), reduceMotion: reduceMotion), value: isHovered)
    }

    private var highlightOpacity: Double {
        guard isHovered, !isSelected else { return 0 }
        return colorScheme == .dark ? 0.06 : 0.04
    }
}

/// 浮动工具条：深色半透明底（浅色外观为白底）+ 26 × 24 的图标按钮
private struct CardHoverToolbar: View {
    let item: ClipItem
    let actions: CardQuickActions

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        HStack(spacing: 1) {
            if let pin = actions.pinToScreen {
                ToolbarButton(
                    symbol: "pin", label: String(localized: "Pin to Screen", comment: "Card hover button"),
                    shortcut: "⇧⌘P", action: pin)
            }
            if let toggleFavorite = actions.toggleFavorite {
                ToolbarButton(
                    symbol: item.isFavorite ? "star.fill" : "star",
                    label: item.isFavorite
                        ? String(localized: "Remove from Favorites", comment: "Card hover button")
                        : String(localized: "Add to Favorites", comment: "Card hover button"),
                    shortcut: "⌘P", action: toggleFavorite)
            }
            if let togglePreview = actions.togglePreview {
                ToolbarButton(
                    symbol: "eye", label: String(localized: "Preview", comment: "Card hover button"),
                    shortcut: String(localized: "Space", comment: "Key name in a tooltip"),
                    isActive: actions.isPreviewing,
                    action: togglePreview)
            }
            ToolbarButton(
                symbol: "trash", label: String(localized: "Delete", comment: "Card hover button"),
                shortcut: "⌘⌫", action: actions.delete)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Radius.segment, style: .continuous)
                .fill(isDark ? Color(red: 0.07, green: 0.075, blue: 0.1).opacity(0.82) : Color.white.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.segment, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: isDark ? .black.opacity(0.35) : Color.black.opacity(0.15), radius: 6, y: 4)
        )
    }
}

private struct ToolbarButton: View {
    let symbol: String
    let label: String
    let shortcut: String
    var isActive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private static let size = CGSize(width: 26, height: 24)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: FontSize.footnote, weight: .medium))
                .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.85 : 0.7))
                .frame(width: Self.size.width, height: Self.size.height)
                .background(
                    RoundedRectangle(cornerRadius: Radius.toolbarButton, style: .continuous)
                        .fill(Color.primary.opacity(isActive || isHovered ? (colorScheme == .dark ? 0.14 : 0.07) : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(verbatim: "\(label) \(shortcut)"))
        .accessibilityLabel(label)
    }
}

extension EnvironmentValues {
    /// 截图走查用：保持悬停状态的卡片（见 PanelViewModel.debugHoveredItemID）
    @Entry var forcedHoverItemID: UUID?
}
