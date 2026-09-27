import SwiftUI
import CubbyCore

/// 卡片列表：选中项变化时自动滚动到可见区域
struct CardList: View {
    /// 列表上下边缘的渐隐高度
    private static let edgeFade: CGFloat = 8

    let items: [ClipItem]
    let viewModel: PanelViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selectedID = viewModel.selectedItem?.id
        let keywords = viewModel.keywords
        ScrollViewReader { proxy in
            ScrollView {
                // 每张卡片带 edgeFade 高度的上下留白作为滚动对齐区域，再用负间距抵消，
                // 视觉间距仍为 cardSpacing；这样滚动到选中项时卡片边框永远不会落入渐隐区
                LazyVStack(spacing: PanelMetrics.cardSpacing - Self.edgeFade * 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        card(item, index: index, isSelected: item.id == selectedID, keywords: keywords)
                    }
                }
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.bottom, 4)
            }
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
                    proxy.scrollTo(selectedID)
                }
            }
            .onChange(of: viewModel.focusToken) {
                if let first = items.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    /// 一张卡片及其手势、右键菜单、拖拽与读屏操作
    private func card(_ item: ClipItem, index: Int, isSelected: Bool, keywords: [String]) -> some View {
        ClipCardView(
            item: item,
            index: index,
            isSelected: isSelected,
            keywords: keywords,
            imageURL: viewModel.imageURL(for: item),
            translation: CardTranslationDecorations.make(for: item, keywords: keywords, viewModel: viewModel),
            onInlineAction: { viewModel.translation?.inline.performAction() }
        )
        .onTapGesture { viewModel.select(item) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { viewModel.paste(item) })
        .contextMenu { CardContextMenu(item: item, viewModel: viewModel) }
        .onDrag { DragProvider.provider(for: item, imageURL: viewModel.imageURL(for: item)) }
        .modifier(CardAccessibilityActions(item: item, viewModel: viewModel))
        .padding(.vertical, Self.edgeFade)
        .id(item.id)
    }
}

/// 卡片右键菜单。键位只用于展示（SwiftUI 在菜单右侧渲染），实际按键仍由 PanelKeyboard 处理；
/// 与面板内的快捷键、帮助浮层保持一致
private struct CardContextMenu: View {
    let item: ClipItem
    let viewModel: PanelViewModel

    var body: some View {
        let filesMissing = item.kind == .file && FileAvailability.allMissing(item.filePaths)
        Button("Paste") { viewModel.paste(item) }
            .keyboardShortcut(.return, modifiers: [])
        if item.formatsName != nil {
            Button(viewModel.settings.pasteFormat.alternate.pasteMenuTitle) {
                viewModel.paste(item, mode: .alternate)
            }
            .keyboardShortcut(.return, modifiers: .shift)
        }
        Button("Copy Only") { viewModel.paste(item, mode: .copyOnly) }
            .keyboardShortcut(.return, modifiers: .command)
        Divider()
        Button("Preview") {
            viewModel.select(item)
            viewModel.setPreviewVisible(true)
        }
        .keyboardShortcut(.space, modifiers: [])
        if item.kind == .link || item.kind == .file || item.kind == .image {
            Button("Open") { viewModel.open(item) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(filesMissing)
        }
        if item.kind == .image {
            Button("Pin to Screen") { viewModel.pin(item) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        if item.kind == .file {
            Button("Show in Finder") { ItemOpener.revealInFinder(item.filePaths) }
                .disabled(filesMissing)
        }
        TranslationMenuItems(item: item, viewModel: viewModel)
        favoriteButton
            .keyboardShortcut("p", modifiers: .command)
        Divider()
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
                if item.kind == .image {
                    Button("Pin to Screen") { viewModel.pin(item) }
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
            let supported = translation.translator.eligibility(of: item) == .eligible
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
            Divider()
        }
    }
}
