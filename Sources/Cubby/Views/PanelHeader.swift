import SwiftUI
import CubbyCore

/// 顶部：搜索框 + 截图、设置按钮 + 分类（平时为分段控件；搜索时为带命中数的分类胶囊）
struct PanelHeader: View {
    @Bindable var viewModel: PanelViewModel
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 10) {
            // 搜索框可以收缩：长占位文字或大字号下不能把右侧按钮挤出面板
            HStack(spacing: 4) {
                SearchField(text: $viewModel.searchText, isFocused: isSearchFocused)
                    .layoutPriority(-1)
                LayoutButton(layout: viewModel.layout) { viewModel.cycleLayout() }
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
            if viewModel.keywords.isEmpty {
                CategoryTabs(selection: viewModel.category) { viewModel.selectCategory($0) }
            } else if let counts = viewModel.searchHitCounts, counts[.all, default: 0] > 0 {
                SearchCategoryChips(selection: viewModel.category, counts: counts) {
                    viewModel.selectCategory($0)
                }
            }
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

struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: FontSize.title, weight: .medium))
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
        .padding(.horizontal, 12)
        .frame(height: PanelMetrics.controlHeight)
        .background(FieldBackground(cornerRadius: Radius.field))
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
    }
}

struct HeaderIconButton: View {
    let systemName: String
    /// VoiceOver 朗读的按钮名称（悬停提示可能带快捷键，不适合作为名称）
    let label: String
    let help: Text
    /// 按下状态（如停靠时的布局按钮）：强调色淡底 + 强调色图标
    var isActive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: FontSize.title))
                .foregroundStyle(isActive ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
                .frame(width: PanelMetrics.iconButtonSize, height: PanelMetrics.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous)
                        .fill(fill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var fill: Color {
        if isActive { return Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14) }
        return Color.primary.opacity(isHovered ? 0.08 : 0)
    }
}
