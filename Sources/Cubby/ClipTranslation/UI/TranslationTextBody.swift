import CubbyCore
import SwiftUI

/// 文本条目的翻译卡正文：译文 / 对照 / 原文三种视图（原型 tcBodyHTML）。
/// 译文逐段到达并逐字显现；对照视图悬停一段时原文与译文一起高亮；显示过程中跟随最新一段滚动，用户滚动后不再跟随
struct TranslationTextBody: View {
    let card: TranslationCard
    /// 还没收到分段时用于「原文」视图的原文
    let fallbackText: String

    @State private var hoveredPair: Int?
    @State private var pairFrames: [Int: CGRect] = [:]
    @State private var followsStream = true

    private static let caretID = "caret"
    private nonisolated static let pairsSpace = "pairs"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.top, TranslationCardMetrics.bodyTop)
                    .padding(.horizontal, TranslationCardMetrics.bodyHorizontal)
                    .padding(.bottom, TranslationCardMetrics.bodyBottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(StopsFollowingOnScroll(follows: $followsStream))
            .onChange(of: card.content.arrivedCount) {
                guard followsStream, card.phase == .streaming else { return }
                proxy.scrollTo(Self.caretID, anchor: .bottom)
            }
            .onChange(of: runIdentity) { followsStream = true }
        }
        // 译文里的链接不在预览面板里直接打开（避免误触；需要时复制后使用）
        .environment(\.openURL, OpenURLAction { _ in .discarded })
    }

    /// 一轮翻译的标识（条目 + 轮次）：换条目或重新翻译时重建段落视图，新到的段重新做显现
    private var runIdentity: String {
        "\(card.itemID.uuidString)-\(card.runID)"
    }

    @ViewBuilder
    private var content: some View {
        switch card.isPeeking ? .original : card.mode {
        case .original: originalBlocks
        case .translation: translationBlocks
        case .sideBySide: pairs
        }
    }

    // MARK: - 原文

    @ViewBuilder
    private var originalBlocks: some View {
        if card.content.segments.isEmpty {
            SegmentText(text: AttributedString(fallbackText), style: .paragraph)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(card.content.segments, id: \.index) { segment in
                    let style = SegmentStyle(segment.original)
                    SegmentText(text: segment.original, style: style)
                        .padding(.bottom, style.spacingAfter)
                }
            }
        }
    }

    // MARK: - 译文

    @ViewBuilder
    private var translationBlocks: some View {
        if card.content.arrivedCount == 0 && card.phase != .done {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<skeletonCount, id: \.self) { index in
                    SkeletonLine(widthFraction: SkeletonLine.fractions[index % SkeletonLine.fractions.count])
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(card.content.segments, id: \.index) { segment in
                    if let text = card.content.translation(at: segment.index) {
                        let style = SegmentStyle(segment.original)
                        SegmentText(text: text, style: style, animates: animates(segment))
                            .padding(.bottom, style.spacingAfter)
                    }
                }
                if card.phase == .streaming {
                    StreamingCaret().id(Self.caretID)
                }
            }
            .id(runIdentity)
        }
    }

    private var skeletonCount: Int {
        min(6, 2 + max(card.content.segments.count, fallbackParagraphs))
    }

    private var fallbackParagraphs: Int {
        fallbackText.components(separatedBy: "\n\n").count
    }

    /// 缓存命中或一次到齐（没有经过流式）时不做显现
    private func animates(_ segment: ClipTranslationSegment) -> Bool {
        segment.isTranslatable && card.plan?.isCached != true
    }

    // MARK: - 对照

    private var pairs: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(card.content.segments, id: \.index) { segment in
                pair(segment)
                    .e2eAnchor("card.pair.\(segment.index)")
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.pairsSpace))
                    } action: { frame in
                        pairFrames[segment.index] = frame
                    }
            }
            if card.content.segments.isEmpty {
                ForEach(0..<skeletonCount, id: \.self) { index in
                    SkeletonLine(widthFraction: SkeletonLine.fractions[index % SkeletonLine.fractions.count])
                }
            }
        }
        .coordinateSpace(.named(Self.pairsSpace))
        .background(PointerTracker { location in hoveredPair = pairIndex(at: location) })
        .id(runIdentity)
    }

    private func pair(_ segment: ClipTranslationSegment) -> some View {
        let style = SegmentStyle(segment.original)
        let isHovered = hoveredPair == segment.index
        return VStack(alignment: .leading, spacing: 3) {
            SegmentText(text: segment.original, style: style, isSecondary: true)
            if let text = card.content.translation(at: segment.index) {
                SegmentText(text: text, style: style, headingSize: FontSize.callout, animates: animates(segment))
            } else {
                SkeletonLine(widthFraction: 0.78)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.accentColor.opacity(isHovered ? 0.12 : 0))
        )
        .overlay(alignment: .leading) {
            if isHovered {
                Rectangle().fill(Color.accentColor).frame(width: 2).padding(.vertical, 2)
            }
        }
        .padding(.horizontal, -8)
        .animation(.easeOut(duration: Motion.fade), value: isHovered)
    }

    private func pairIndex(at location: CGPoint?) -> Int? {
        guard let location else { return nil }
        return pairFrames.first { $0.value.insetBy(dx: -8, dy: -2).contains(location) }?.key
    }
}

/// 用户自己滚动后不再跟随最新一段（macOS 15 起可读滚动阶段）
private struct StopsFollowingOnScroll: ViewModifier {
    @Binding var follows: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { follows = false }
            }
        } else {
            content
        }
    }
}
