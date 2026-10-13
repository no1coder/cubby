import SwiftUI
import CubbyCore

/// 卡片列表：选中项变化时自动滚动到可见区域
struct CardList: View {
    /// 列表上下边缘的渐隐高度
    private static let edgeFade: CGFloat = 8
    /// 第一个分组标题的滚动标识：回到顶部时滚到它，而不是第一张卡片（否则标题被滚出视野）
    private static let topAnchor = "list.top"

    let items: [ClipItem]
    let viewModel: PanelViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selectedID = viewModel.selectedItem?.id
        let keywords = viewModel.keywords
        // ⌘1–⌘9 的编号跳过被替换进来的条目
        let numbers = viewModel.quickPasteIndices(items)
        ScrollViewReader { proxy in
            ScrollView {
                // 每张卡片带 edgeFade 高度的上下留白作为滚动对齐区域，再用负间距抵消，
                // 视觉间距仍为 cardSpacing；这样滚动到选中项时卡片边框永远不会落入渐隐区
                LazyVStack(alignment: .leading, spacing: PanelMetrics.cardSpacing - Self.edgeFade * 2) {
                    if keywords.isEmpty {
                        groupedCards(selectedID: selectedID, numbers: numbers)
                    } else {
                        // 搜索结果按相关度排序，不按日期分组
                        ForEach(items) { item in
                            card(item, number: numbers[item.id], isSelected: item.id == selectedID, keywords: keywords)
                        }
                    }
                }
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.bottom, 4)
            }
            .modifier(DebugHoverEnvironment(viewModel: viewModel))
            // 不显示滚动条：卡片列表一目了然，且「始终显示滚动条」时滚动条会挤占卡片宽度
            .scrollIndicators(.never)
            // 上下边缘渐隐：滚动中的圆角卡片柔和淡出，而不是被列表边缘生硬地横切
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.edgeFade)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.edgeFade)
                }
            }
            .onChange(of: selectedID) {
                guard let selectedID else { return }
                withAnimation(Motion.animation(.easeOut(duration: Motion.overlayFade), reduceMotion: reduceMotion)) {
                    if selectedID == items.first?.id, keywords.isEmpty {
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    } else {
                        proxy.scrollTo(selectedID)
                    }
                }
            }
            .onChange(of: viewModel.focusToken) {
                if keywords.isEmpty, !items.isEmpty {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                } else if let first = items.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    /// 按「今天 / 昨天 / 更早」分节；⌘N 的序号仍按整个列表计数
    @ViewBuilder
    private func groupedCards(selectedID: UUID?, numbers: [UUID: Int]) -> some View {
        let sections = ClipDayGroup.sections(items, now: Date())
        ForEach(sections) { section in
            // 第一个标题避开顶部渐隐区；其后的标题与上一节最后一张卡片拉开距离
            DayGroupHeader(group: section.group, topPadding: section.index == 0 ? Self.edgeFade : 12)
                .id(section.index == 0 ? Self.topAnchor : "list.section.\(section.index)")
            ForEach(section.items) { item in
                card(item, number: numbers[item.id], isSelected: item.id == selectedID, keywords: [])
            }
        }
    }

    /// 一张卡片及其交互（见 CardInteractions）。number 为 ⌘N 的序号（从 0 开始），没有键帽时为 nil
    private func card(_ item: ClipItem, number: Int?, isSelected: Bool, keywords: [String]) -> some View {
        ClipCardView(
            item: item,
            index: number ?? Int.max,
            isSelected: isSelected,
            keywords: keywords,
            imageSource: viewModel.imageSource(for: item),
            translation: CardTranslationDecorations.make(for: item, keywords: keywords, viewModel: viewModel),
            isOnClothesline: viewModel.isOnClothesline(item),
            onInlineAction: { viewModel.translation?.inline.performAction() },
            security: viewModel.securityMarker(for: item),
            onShowDetails: { viewModel.showTamperDetails(item) }
        )
        .e2eAnchor("list.card.\(item.id)")
        .modifier(CardInteractions(item: item, isSelected: isSelected, viewModel: viewModel))
        .padding(.vertical, Self.edgeFade)
        .id(item.id)
    }
}

/// 卡片的交互（列表与横条共用）：单击选中、双击粘贴、长按拆词（0.45 秒、移动不超过 4pt，
/// docs/TEXT-PICK-DESIGN.md §2）、右键菜单、拖出、悬停工具条与读屏操作
struct CardInteractions: ViewModifier {
    let item: ClipItem
    let isSelected: Bool
    let viewModel: PanelViewModel
    /// 图片网格的格子：悬停工具条只有贴到屏幕与删除（设计稿）
    var isGridCell = false

    func body(content: Content) -> some View {
        content
            .onTapGesture { viewModel.select(item) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { viewModel.paste(item) })
            // 长按挂在单击 / 双击之外：内层手势优先，挂在里面会吞掉单击选中
            .modifier(CardLongPress { viewModel.openTextPick(for: item) })
            .contextMenu { CardContextMenu(item: item, viewModel: viewModel) }
            // 被替换进来的条目不能拖出（等同复制）
            .modifier(CardDrag(item: item, viewModel: viewModel))
            // 悬停工具条叠在所有手势之上：按钮上的单击 / 双击 / 长按 / 拖动不会传给卡片（否则双击收藏会顺带粘贴）
            .modifier(CardHoverChrome(item: item, isSelected: isSelected, actions: quickActions))
            .modifier(CardAccessibilityActions(item: item, viewModel: viewModel))
    }

    /// 悬停工具条：预览按钮在这张卡片的预览已打开时再按一次关闭
    private var quickActions: CardQuickActions {
        let isPreviewing = isSelected && viewModel.isPreviewVisible
        return CardQuickActions(
            toggleFavorite: isGridCell ? nil : { viewModel.toggleFavorite(item) },
            togglePreview: isGridCell
                ? nil
                : {
                    if isPreviewing {
                        viewModel.setPreviewVisible(false)
                    } else {
                        viewModel.select(item)
                        viewModel.setPreviewVisible(true)
                    }
                },
            delete: { viewModel.delete(item) },
            pinToScreen: item.kind == .image ? { viewModel.pin(item) } : nil,
            toggleClothesline: item.kind == .image && viewModel.offersClothesline
                ? { viewModel.toggleClothesline(item) } : nil,
            isOnClothesline: viewModel.isOnClothesline(item),
            isPreviewing: isPreviewing
        )
    }
}

/// 拖出卡片：被替换进来的条目不提供拖出
private struct CardDrag: ViewModifier {
    let item: ClipItem
    let viewModel: PanelViewModel

    func body(content: Content) -> some View {
        if viewModel.isBlocked(item) {
            content
        } else {
            content.onDrag { DragProvider.provider(for: item) { viewModel.exportImage(item) } }
        }
    }
}

/// 分组标题「今天 / 昨天 / 更早」：11pt semibold。玻璃上的 11pt 文字不用 .secondary（对比度不足），
/// 用 primary 0.75（增强对比度时 0.9）
private struct DayGroupHeader: View {
    let group: ClipDayGroup
    /// 列表间距为负（见 CardList.body），上下留白就是与相邻卡片的可见间距
    let topPadding: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(group.displayName)
            .font(.system(size: FontSize.caption, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(Color.primary.opacity(contrast == .increased ? 0.9 : 0.75))
            .padding(.horizontal, 4)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 卡片右键菜单。键位只用于展示（SwiftUI 在菜单右侧渲染），实际按键仍由 PanelKeyboard 处理；
/// 与面板内的快捷键、帮助浮层保持一致
private struct CardContextMenu: View {
    let item: ClipItem
    let viewModel: PanelViewModel

    var body: some View {
        let filesMissing = item.kind == .file && FileAvailability.allMissing(item.filePaths)
        // 被替换进来的条目：粘贴、复制、拆词与翻译后粘贴置灰（按键与双击另由视图模型拦下）
        let isBlocked = viewModel.isBlocked(item)
        Button("Paste") { viewModel.paste(item) }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(isBlocked)
        if item.formatsName != nil {
            Button(viewModel.settings.pasteFormat.alternate.pasteMenuTitle) {
                viewModel.paste(item, mode: .alternate)
            }
            .keyboardShortcut(.return, modifiers: .shift)
            .disabled(isBlocked)
        }
        Button("Copy Only") { viewModel.paste(item, mode: .copyOnly) }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isBlocked)
        Divider()
        Button("Preview") {
            viewModel.select(item)
            viewModel.setPreviewVisible(true)
        }
        .keyboardShortcut(.space, modifiers: [])
        if item.kind == .image {
            Button("Pin to Screen") { viewModel.pin(item) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            if viewModel.offersClothesline {
                Button(ClotheslineCopy.toggleTitle(isHanging: viewModel.isOnClothesline(item))) {
                    viewModel.toggleClothesline(item)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
        Button(TextPickCopy.title) { viewModel.openTextPick(for: item) }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(isBlocked || TextPickSource(item: item).text == nil)
        if item.kind == .link || item.kind == .file || item.kind == .image {
            Button("Open") { viewModel.open(item) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(filesMissing)
        }
        if item.kind == .file {
            Button("Show in Finder") { ItemOpener.revealInFinder(item.filePaths) }
                .disabled(filesMissing)
        }
        TranslationMenuItems(item: item, viewModel: viewModel)
        Divider()
        favoriteButton
            .keyboardShortcut("p", modifiers: .command)
        Button("Delete", role: .destructive) { viewModel.delete(item) }
            .keyboardShortcut(.delete, modifiers: .command)
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if item.isFavorite {
            Button("Unfavorite") { viewModel.toggleFavorite(item) }
        } else {
            Button("Favorite") { viewModel.toggleFavorite(item) }
        }
    }
}

/// VoiceOver 的卡片操作：默认动作（VO-空格）粘贴，其余操作在「操作」转子里
private struct CardAccessibilityActions: ViewModifier {
    let item: ClipItem
    let viewModel: PanelViewModel

    func body(content: Content) -> some View {
        content
            .accessibilityAction { viewModel.paste(item) }
            .accessibilityActions {
                if item.isFavorite {
                    Button("Unfavorite") { viewModel.toggleFavorite(item) }
                } else {
                    Button("Favorite") { viewModel.toggleFavorite(item) }
                }
                Button("Preview") {
                    viewModel.select(item)
                    viewModel.setPreviewVisible(true)
                }
                if TextPickSource(item: item).text != nil {
                    Button(TextPickCopy.title) { viewModel.openTextPick(for: item) }
                }
                if item.kind == .image {
                    Button("Pin to Screen") { viewModel.pin(item) }
                    if viewModel.offersClothesline {
                        Button(ClotheslineCopy.toggleTitle(isHanging: viewModel.isOnClothesline(item))) {
                            viewModel.toggleClothesline(item)
                        }
                    }
                }
                if viewModel.translation != nil {
                    Button(TranslationMenuItems.translateTitle) { viewModel.openTranslation(for: item) }
                    Button(TranslationMenuItems.translatePasteTitle) { viewModel.translateAndPaste(item) }
                }
                Button("Delete") { viewModel.delete(item) }
            }
    }
}

private extension PasteFormat {
    /// 右键菜单中「以该格式粘贴」的完整标题
    var pasteMenuTitle: String {
        switch self {
        case .original: String(localized: "Paste with Original Formatting", comment: "Context menu item")
        case .plainText: String(localized: "Paste as Plain Text", comment: "Context menu item")
        }
    }
}

/// 右键菜单的翻译项：「翻译 ⌘T」「翻译后粘贴 ⌥↩」、有缓存时「复制译文」；不支持的类型置灰
private struct TranslationMenuItems: View {
    let item: ClipItem
    let viewModel: PanelViewModel

    static var translateTitle: String {
        String(localized: "Translate", comment: "Context menu item and title of the translation card")
    }

    static var translatePasteTitle: String {
        String(localized: "Translate and Paste", comment: "Context menu item")
    }

    var body: some View {
        if let translation = viewModel.translation {
            let supported = translation.translator.eligibility(of: item) == .eligible && !viewModel.isBlocked(item)
            Divider()
            Button(Self.translateTitle) { viewModel.openTranslation(for: item) }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!supported)
            Button(Self.translatePasteTitle) { viewModel.translateAndPaste(item) }
                .keyboardShortcut(.return, modifiers: .option)
                .disabled(!supported)
            if item.translations?.entries.isEmpty == false {
                Button(TranslationCopy.copyMenuItem) { viewModel.copyCachedTranslation(item) }
            }
        }
    }
}

/// 调试构建把「保持悬停」的卡片传给各张卡片；正式构建不做任何事
struct DebugHoverEnvironment: ViewModifier {
    let viewModel: PanelViewModel

    func body(content: Content) -> some View {
        #if DEBUG
        content.environment(\.forcedHoverItemID, viewModel.debugHoveredItemID)
        #else
        content
        #endif
    }
}
