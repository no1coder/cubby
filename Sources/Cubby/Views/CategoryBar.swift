import CubbyCore
import SwiftUI

/// 搜索框与分类底槽的凹陷底色 + 内描边
struct FieldBackground: View {
    enum Style {
        /// 搜索框：深色白 0.08，浅色黑 0.05
        case field
        /// 分类分段控件的底槽：深色更深一级（黑 0.22），浅色黑 0.06
        case track
    }

    let cornerRadius: CGFloat
    var style = Style.field

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark
        shape
            .fill(fill(isDark: isDark))
            .overlay(shape.strokeBorder(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5))
    }

    private func fill(isDark: Bool) -> Color {
        switch (style, isDark) {
        case (.field, true): Color.white.opacity(0.08)
        case (.field, false): Color.black.opacity(0.05)
        case (.track, true): Color.black.opacity(0.22)
        case (.track, false): Color.black.opacity(0.06)
        }
    }
}

/// 分类分段控件：深色底槽 + 选中项浮起的胶囊（滑动过渡，字重不变、文字不抖动）。
/// 文字项按文字宽度再平分剩余空间（文字绝不截断），「收藏」固定为星标；
/// 放不下时（较长的语言、放大的字号）退为全部图标，悬停显示名称
struct CategoryTabs: View {
    let selection: ClipCategory
    let onSelect: (ClipCategory) -> Void

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let itemHeight: CGFloat = 28
    private static let favoriteWidth: CGFloat = 34
    private static let trackPadding: CGFloat = 3

    var body: some View {
        ViewThatFits(in: .horizontal) {
            track(iconsOnly: false)
            track(iconsOnly: true)
        }
        // 减弱动态效果时胶囊直接跳到新分类，不做滑动
        .animation(Motion.animation(.snappy(duration: Motion.tabSlide), reduceMotion: reduceMotion), value: selection)
    }

    private func track(iconsOnly: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(ClipCategory.allCases, id: \.self) { category in
                let showsIcon = iconsOnly || category == .favorite
                SegmentItem(
                    title: category.displayName,
                    iconName: showsIcon ? (category == .favorite ? "star.fill" : category.symbolName) : nil,
                    isSelected: category == selection,
                    selectionID: iconsOnly,
                    namespace: namespace
                ) {
                    onSelect(category)
                }
                .frame(height: Self.itemHeight)
                .frame(maxWidth: category == .favorite && !iconsOnly ? Self.favoriteWidth : .infinity)
            }
        }
        .padding(Self.trackPadding)
        .background(FieldBackground(cornerRadius: Radius.field, style: .track))
    }
}

private struct SegmentItem: View {
    let title: String
    /// 非 nil 时以图标代替文字（名称通过悬停提示与辅助功能标签提供）
    let iconName: String?
    let isSelected: Bool
    /// ViewThatFits 会同时构建各级候选视图：每级使用独立的 matchedGeometry 标识，避免冲突
    let selectionID: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: FontSize.footnote, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                    isSelected ? Color.primary : Color.primary.opacity(contrast == .increased ? 0.85 : 0.62)
                )
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        selectedPill
                            .matchedGeometryEffect(id: selectionID, in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: Radius.segment, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(iconName == nil ? "" : title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var label: some View {
        if let iconName {
            Image(systemName: iconName)
                .font(.system(size: FontSize.footnote))
        } else {
            // 固定理想宽度：放不下时由 ViewThatFits 换成图标，而不是截断成「Ima…」
            Text(title)
                .fixedSize()
        }
    }

    /// 浮起的胶囊：深色为白 0.18 + 顶边高光，浅色为白底 + 细投影
    private var selectedPill: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.segment, style: .continuous)
        let isDark = colorScheme == .dark
        return
            shape
            .fill(isDark ? Color.white.opacity(0.18) : Color.white)
            .shadow(color: .black.opacity(isDark ? 0.3 : 0.12), radius: 1.5, y: 1)
    }
}

/// 搜索时的分类：只列出有命中的分类与当前分类，名称后跟命中数（Search 画板）
struct SearchCategoryChips: View {
    let selection: ClipCategory
    let counts: [ClipCategory: Int]
    let onSelect: (ClipCategory) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visible, id: \.self) { category in
                SearchChip(
                    title: category.displayName, count: counts[category, default: 0],
                    isSelected: category == selection
                ) {
                    onSelect(category)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.height)
    }

    private static let height: CGFloat = 24

    /// 没有命中的分类隐藏；当前分类即使为 0 也保留，用户知道自己在哪个分类里搜
    private var visible: [ClipCategory] {
        ClipCategory.allCases.filter { counts[$0, default: 0] > 0 || $0 == selection }
    }
}

private struct SearchChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    var body: some View {
        // 玻璃上的 11pt 文字至少 primary 0.75（DESIGN.md「对比度底线」）；选中项靠字重与底色区分
        let secondary = Color.primary.opacity(contrast == .increased ? 0.9 : 0.75)
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(secondary)
            }
            .font(.system(size: FontSize.caption, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.primary : secondary)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(
                Capsule().fill(Color.primary.opacity(isSelected ? 0.12 : (isHovered ? 0.05 : 0)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
