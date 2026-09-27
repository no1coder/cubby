import CubbyCore
import SwiftUI

/// 翻译卡（⌘T）：与空格预览共用预览面板窗口（K1），宽 440，头 56 / 工具条 40 / 底栏 36（A10）
struct TranslationCardView: View {
    let viewModel: PanelViewModel
    let translation: ClipTranslationController
    /// 布局键变化（切换视图、进入状态页、跟随到新条目）时通知窗口调整高度
    let onLayoutChange: () -> Void

    var body: some View {
        let controller = translation.card
        if let card = controller.card, let item = viewModel.store.item(id: card.itemID) {
            VStack(spacing: 0) {
                TranslationCardHeader(card: card, item: item, controller: controller) {
                    viewModel.onOpenSettings?()
                }
                Hairline()
                TranslationCardToolbar(card: card, controller: controller)
                content(card: card, item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Hairline()
                TranslationCardFooter(
                    card: card, item: item, controller: controller, flash: controller.flash,
                    targetName: viewModel.target?.name, isRecordingPaused: viewModel.settings.isPaused)
            }
            .animation(.easeOut(duration: Motion.fade), value: controller.flash)
            .onChange(of: TranslationCardLayout.key(for: card)) { onLayoutChange() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(TranslationCopy.cardTitle))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(card: TranslationCard, item: ClipItem) -> some View {
        if let state = TranslationCardLayout.stateView(for: card, controller: translation.card) {
            // 不放进 ScrollView：滚动视图内部的容器视图不接受 first mouse，非 key 窗口里第一次点击可能被吞（R1）
            state
        } else if case .image(let ref) = item.payload {
            TranslationImageBody(
                card: card, imageURL: viewModel.imageURL(for: item), ref: ref, controller: translation.card)
        } else {
            TranslationTextBody(card: card, fallbackText: item.text ?? "")
        }
    }
}

/// 0.5pt 分割线
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }
}

/// 翻译卡高度：按「最终内容」估算，流式过程中不跳动；上限为主面板高度（A10）
@MainActor
enum TranslationCardLayout {
    /// 同一键下高度不变：切换视图、进入状态页或跟随到新条目时才重新计算
    struct Key: Hashable {
        let itemID: UUID
        let mode: TranslationViewMode
        let showsState: Bool
        let isReversed: Bool
    }

    static func key(for card: TranslationCard) -> Key {
        Key(itemID: card.itemID, mode: card.mode, showsState: showsState(card), isReversed: card.isReversed)
    }

    /// 状态页：不支持总是显示；其他问题在「原文」视图下让位于原文（原型 tcBodyHTML）
    static func showsState(_ card: TranslationCard) -> Bool {
        switch card.phase {
        case .unsupported: true
        case .failed, .needsSecretConfirmation, .alreadyTarget, .cancelled: card.mode != .original
        default: false
        }
    }

    static func stateView(for card: TranslationCard, controller: TranslationCardController) -> TranslationStateView? {
        showsState(card) ? TranslationStateView.make(for: card, controller: controller) : nil
    }

    /// 超过该长度的文本必然超过主面板高度，无需测量
    private static let longTextBytes = 1_500

    /// 正文的理想高度（不含头部、工具条与底栏）
    static func bodyHeight(
        for card: TranslationCard, item: ClipItem, controller: TranslationCardController
    ) -> CGFloat {
        if let state = stateView(for: card, controller: controller) {
            return measure(state)
        }
        if (item.text?.utf8.count ?? 0) > longTextBytes {
            return .greatestFiniteMagnitude
        }
        return measure(TranslationTextMeasure(card: card, fallbackText: item.text ?? ""))
    }

    private static func measure(_ view: some View) -> CGFloat {
        let probe = NSHostingView(
            rootView: view.frame(width: PreviewMetrics.width).fixedSize(horizontal: false, vertical: true))
        return probe.fittingSize.height
    }
}

/// 测量用的正文：译文未到时用原文代替（译文与原文长度相近），对照视图按原文 + 译文两份估算
private struct TranslationTextMeasure: View {
    let card: TranslationCard
    let fallbackText: String

    var body: some View {
        VStack(alignment: .leading, spacing: card.mode == .sideBySide ? 4 : 0) {
            ForEach(Array(proxies.enumerated()), id: \.offset) { _, proxy in
                block(proxy)
            }
        }
        .padding(.top, TranslationCardMetrics.bodyTop)
        .padding(.horizontal, TranslationCardMetrics.bodyHorizontal)
        .padding(.bottom, TranslationCardMetrics.bodyBottom)
    }

    @ViewBuilder
    private func block(_ proxy: (original: AttributedString, shown: AttributedString)) -> some View {
        let style = SegmentStyle(proxy.original)
        if card.mode == .sideBySide {
            VStack(alignment: .leading, spacing: 3) {
                SegmentText(text: proxy.original, style: style, isSecondary: true)
                SegmentText(text: proxy.shown, style: style, headingSize: FontSize.callout)
            }
            .padding(.vertical, 6)
        } else {
            SegmentText(text: proxy.shown, style: style)
                .padding(.bottom, style.spacingAfter)
        }
    }

    /// 每段的（原文, 显示内容）：原文视图显示原文；译文已完成（缓存命中）时用真实译文
    private var proxies: [(original: AttributedString, shown: AttributedString)] {
        let segments = card.content.segments
        guard !segments.isEmpty else {
            return fallbackText.components(separatedBy: "\n\n").map { (AttributedString($0), AttributedString($0)) }
        }
        return segments.map { segment in
            let shown =
                card.mode == .original
                ? segment.original : card.content.translation(at: segment.index) ?? segment.original
            return (segment.original, shown)
        }
    }
}
