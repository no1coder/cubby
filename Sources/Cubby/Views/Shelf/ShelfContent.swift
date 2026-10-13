import CubbyCore
import SwiftUI

/// 底部横条（docs/UI-UPGRADE-PLAN.md 第 3 节）：顶部一行（搜索 · 分类 · 提示 · 布局 · 设置），
/// 提醒收成一行，卡片横向排列可横向滚动。没有底栏：底栏的提示放在顶部一行的右侧
struct ShelfContent: View {
    @Bindable var viewModel: PanelViewModel
    var isSearchFocused: FocusState<Bool>.Binding
    let items: [ClipItem]

    private static let topRowPadding = EdgeInsets(top: 12, leading: 14, bottom: 4, trailing: 14)

    var body: some View {
        VStack(spacing: 0) {
            topRow
            ForEach(viewModel.visibleWarnings) { warning in
                WarningBanner(
                    warning: warning,
                    actionTitle: viewModel.actionTitle(for: warning),
                    onAction: { viewModel.performAction(for: warning) },
                    onSecondary: warning.secondaryActionTitle == nil
                        ? nil : { viewModel.performSecondaryAction(for: warning) },
                    onDismiss: warning.isDismissible ? { viewModel.dismissWarning(warning) } : nil,
                    isCompact: true
                )
                .padding(.horizontal, Self.topRowPadding.leading)
                .padding(.top, PanelMetrics.compactBannerSpacing)
            }
            if viewModel.isVaultPreparing {
                VaultPreparingPlaceholder()
            } else if items.isEmpty {
                PanelEmptyState(viewModel: viewModel)
            } else {
                ShelfCardRow(items: items, viewModel: viewModel)
            }
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            SearchField(
                text: $viewModel.searchText, isFocused: isSearchFocused,
                searchesImages: viewModel.category == .image && viewModel.settings.indexesImageText
            )
            .frame(width: ShelfMetrics.searchWidth)
            if viewModel.keywords.isEmpty {
                CategoryTabs(selection: viewModel.category, minItemWidth: ShelfMetrics.segmentWidth) {
                    viewModel.selectCategory($0)
                }
                .fixedSize()
            } else if let counts = viewModel.searchHitCounts, counts[.all, default: 0] > 0 {
                SearchCategoryChips(selection: viewModel.category, counts: counts) { viewModel.selectCategory($0) }
                    .fixedSize()
            }
            Spacer(minLength: 12)
            PanelFooter(viewModel: viewModel, count: items.count, isInShelfTopRow: true)
            LayoutButton(layout: viewModel.layout) { viewModel.cycleLayout() }
            HeaderIconButton(
                systemName: "gearshape",
                label: String(localized: "Settings", comment: "Shortcut help"),
                help: Text("Settings (⌘,)")
            ) {
                viewModel.handle(.openSettings)
            }
        }
        .padding(Self.topRowPadding)
    }
}

/// 横向排列的卡片：选中项变化时滚到可见处，并报告选中卡片的位置（详情区水平居中于它）
private struct ShelfCardRow: View {
    let items: [ClipItem]
    let viewModel: PanelViewModel

    /// 上方留出选中卡片上浮与外环光晕的空间，下方留出投影
    private static let padding = EdgeInsets(top: 12, leading: 14, bottom: 16, trailing: 14)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selectedID = viewModel.selectedItem?.id
        let keywords = viewModel.keywords
        // ⌘1–⌘9 的编号跳过被替换进来的条目
        let numbers = viewModel.quickPasteIndices(items)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: ShelfMetrics.cardSpacing) {
                    ForEach(items) { item in
                        card(item, number: numbers[item.id], isSelected: item.id == selectedID, keywords: keywords)
                    }
                }
                .padding(Self.padding)
            }
            .scrollIndicators(.never)
            .modifier(DebugHoverEnvironment(viewModel: viewModel))
            .onChange(of: selectedID) {
                guard let selectedID else { return }
                withAnimation(Motion.animation(.easeOut(duration: Motion.overlayFade), reduceMotion: reduceMotion)) {
                    proxy.scrollTo(selectedID)
                }
            }
            .onChange(of: viewModel.focusToken) {
                if let first = items.first {
                    proxy.scrollTo(first.id, anchor: .leading)
                }
            }
        }
    }

    /// number 为 ⌘N 的序号（从 0 开始，跳过被替换进来的条目），没有键帽时为 nil
    private func card(_ item: ClipItem, number: Int?, isSelected: Bool, keywords: [String]) -> some View {
        ShelfCard(
            item: item, index: number ?? Int.max, isSelected: isSelected, keywords: keywords,
            imageSource: viewModel.imageSource(for: item),
            translation: CardTranslationDecorations.make(for: item, keywords: keywords, viewModel: viewModel),
            isOnClothesline: viewModel.isOnClothesline(item),
            onInlineAction: { viewModel.translation?.inline.performAction() },
            security: viewModel.securityMarker(for: item),
            onShowDetails: { viewModel.showTamperDetails(item) }
        )
        .background { if isSelected { SelectionAnchorReporter(viewModel: viewModel) } }
        .e2eAnchor("list.card.\(item.id)")
        .modifier(CardInteractions(item: item, isSelected: isSelected, viewModel: viewModel))
        // 选中卡片上浮（连同悬停工具条一起）；减弱动态效果时不位移，只靠外环区分
        .offset(y: isSelected && !reduceMotion ? -ShelfCard.lift : 0)
        .animation(
            Motion.animation(.easeOut(duration: Motion.selection), reduceMotion: reduceMotion), value: isSelected
        )
        .id(item.id)
    }
}

/// 报告选中卡片的中心 x（窗口坐标）：选中项变化（新卡片出现）或滚动时更新
private struct SelectionAnchorReporter: View {
    let viewModel: PanelViewModel

    var body: some View {
        GeometryReader { proxy in
            let midX = proxy.frame(in: .global).midX
            Color.clear
                .onAppear { viewModel.shelfSelectionMoved(toX: midX) }
                .onChange(of: midX) { viewModel.shelfSelectionMoved(toX: midX) }
        }
    }
}
