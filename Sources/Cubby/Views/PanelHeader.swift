import SwiftUI
import CubbyCore

/// 顶部：搜索框 + 截图、设置按钮 + 分类标签
struct PanelHeader: View {
    @Bindable var viewModel: PanelViewModel
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                SearchField(text: $viewModel.searchText, isFocused: isSearchFocused)
                HeaderIconButton(
                    systemName: "camera.viewfinder",
                    label: screenshotTitle,
                    help: Text(verbatim: screenshotHelp)
                ) {
                    viewModel.handle(.takeScreenshot)
                }
                HeaderIconButton(
                    systemName: "gearshape",
                    label: String(localized: "Settings", comment: "Shortcut help"),
                    help: Text("Settings (⌘,)")
                ) {
                    viewModel.handle(.openSettings)
                }
            }
            CategoryTabs(selection: viewModel.category) { viewModel.selectCategory($0) }
        }
        .padding(.horizontal, PanelMetrics.inset)
        .padding(.top, PanelMetrics.inset)
        .padding(.bottom, 8)
    }

    private var screenshotTitle: String {
        String(localized: "Take Screenshot", comment: "Status menu item and panel button tooltip")
    }

    /// 「截图 (⇧⌘2)」；截图快捷键已关闭时只显示标题
    private var screenshotHelp: String {
        guard let shortcut = viewModel.settings.screenshotHotKey else { return screenshotTitle }
        return "\(screenshotTitle) (\(shortcut.displayName))"
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: FontSize.body, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: FontSize.callout))
                .focused(isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: FontSize.body))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search (esc)")
                .accessibilityLabel(
                    Text("Clear search", comment: "Accessibility label of the search field's clear button")
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PanelMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    /// VoiceOver 朗读的按钮名称（悬停提示可能带快捷键，不适合作为名称）
    let label: String
    let help: Text
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: FontSize.callout))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: PanelMetrics.controlHeight, height: PanelMetrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}

/// 分类标签，选中态以胶囊背景滑动过渡；字重固定，切换时文字不抖动。
/// 英文等较长的语言在 380pt 面板中可能放不下：用 ViewThatFits 逐级降级（不横向滚动）
private struct CategoryTabs: View {
    let selection: ClipCategory
    let onSelect: (ClipCategory) -> Void

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(TabDensity.allCases, id: \.self) { density in
                tabs(density)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 减弱动态效果时胶囊直接跳到新分类，不做滑动
        .animation(Motion.animation(.snappy(duration: Motion.tabSlide), reduceMotion: reduceMotion), value: selection)
    }

    private func tabs(_ density: TabDensity) -> some View {
        HStack(spacing: density.spacing) {
            ForEach(ClipCategory.allCases, id: \.self) { category in
                CategoryTab(
                    title: category.displayName,
                    iconName: density.showsIcon(for: category) ? CategoryTab.iconName(for: category) : nil,
                    horizontalPadding: density.horizontalPadding,
                    isSelected: category == selection,
                    selectionID: density,
                    namespace: namespace
                ) {
                    onSelect(category)
                }
            }
        }
    }
}

/// 分类栏的降级级别，按顺序尝试，放得下即停
private enum TabDensity: CaseIterable {
    /// 全部文字，标准内边距
    case regular
    /// 全部文字，收紧内边距与间距
    case compact
    /// 「收藏」改为星标图标
    case favoriteIcon
    /// 全部改为图标，悬停显示名称
    case iconsOnly

    var horizontalPadding: CGFloat {
        self == .regular ? 9 : 6
    }

    var spacing: CGFloat {
        self == .regular ? 2 : 0
    }

    func showsIcon(for category: ClipCategory) -> Bool {
        switch self {
        case .regular, .compact: false
        case .favoriteIcon: category == .favorite
        case .iconsOnly: true
        }
    }
}

private struct CategoryTab: View {
    let title: String
    /// 非 nil 时以图标代替文字（名称通过悬停提示与辅助功能标签提供）
    let iconName: String?
    let horizontalPadding: CGFloat
    let isSelected: Bool
    /// ViewThatFits 会同时构建各级候选视图：每级使用独立的 matchedGeometry 标识，避免冲突
    let selectionID: TabDensity
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    static func iconName(for category: ClipCategory) -> String {
        category == .favorite ? "star.fill" : category.symbolName
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: FontSize.footnote, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                            .matchedGeometryEffect(id: selectionID, in: namespace)
                    } else if isHovered {
                        Capsule().fill(Color.primary.opacity(0.05))
                    }
                }
                .contentShape(Capsule())
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
                .frame(minWidth: 14)
        } else {
            Text(title)
        }
    }
}
