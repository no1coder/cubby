import SwiftUI
import CubbyCore

/// 面板根视图（背景由 PanelChrome 提供）
struct PanelView: View {
    @Bindable var viewModel: PanelViewModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let items = viewModel.items
        ZStack {
            VStack(spacing: 0) {
                PanelHeader(viewModel: viewModel, isSearchFocused: $isSearchFocused)
                ForEach(viewModel.visibleWarnings) { warning in
                    WarningBanner(
                        warning: warning,
                        actionTitle: viewModel.actionTitle(for: warning),
                        onAction: { viewModel.performAction(for: warning) },
                        onSecondary: warning.secondaryActionTitle == nil
                            ? nil : { viewModel.performSecondaryAction(for: warning) },
                        onDismiss: warning.isDismissible ? { viewModel.dismissWarning(warning) } : nil
                    )
                }
                Group {
                    if items.isEmpty {
                        EmptyStateView(
                            searchText: viewModel.searchText,
                            category: viewModel.category,
                            hotKey: viewModel.settings.hotKey,
                            searchesTranslations: viewModel.translation != nil
                        )
                    } else {
                        CardList(items: items, viewModel: viewModel)
                    }
                }
                .frame(maxHeight: .infinity)
                PanelFooter(viewModel: viewModel, count: items.count)
            }
            // 帮助浮层覆盖整个面板（含搜索栏与底栏），遮罩按面板圆角裁切
            if viewModel.isShowingHelp {
                helpOverlay
            }
        }
        .animation(
            Motion.animation(.easeOut(duration: Motion.overlayFade), reduceMotion: reduceMotion),
            value: viewModel.isShowingHelp
        )
        .animation(
            Motion.animation(.snappy(duration: Motion.layoutChange), reduceMotion: reduceMotion),
            value: viewModel.visibleWarnings
        )
        .onAppear { isSearchFocused = true }
        // 翻译卡跟随选中项；⌥↩ 与按住 ⌥ 预览只属于原条目（选中项变化时取消）
        .onChange(of: viewModel.selectedItem?.id) { viewModel.selectionDidChange() }
        // 停在图片上等它识别出文字：拆词卡从状态页换成词块（同一条目、文字变化）
        .onChange(of: viewModel.selectedItem?.recognizedText) { viewModel.textPickSelectionChanged() }
        .onChange(of: viewModel.focusToken) {
            // 先取消再聚焦，保证面板再次出现时焦点一定回到搜索框
            isSearchFocused = false
            Task { @MainActor in isSearchFocused = true }
        }
    }

    /// 与底栏「↩」提示同一判断：没有可粘贴的目标时 ↩ / ⇧↩ 都只复制。
    /// 翻译卡或拆词卡打开时帮助多出两行，不再显示「完整使用说明…」链接，免得超出面板高度
    private var helpOverlay: some View {
        let translation = helpTranslation
        let cardOpen = translation == .cardOpen || viewModel.isTextPickOpen
        return HelpOverlay(
            alternateFormat: viewModel.settings.pasteFormat.alternate,
            pastesDirectly: viewModel.canPasteDirectly && viewModel.target != nil,
            translation: translation,
            textPickOpen: viewModel.isTextPickOpen,
            onOpenUserGuide: cardOpen ? nil : { viewModel.openUserGuide() }
        ) { viewModel.toggleHelp() }
        .transition(.opacity)
    }

    private var helpTranslation: ShortcutHelpView.Translation {
        guard viewModel.translation != nil else { return .unavailable }
        return viewModel.isTranslationCardOpen ? .cardOpen : .available
    }
}
