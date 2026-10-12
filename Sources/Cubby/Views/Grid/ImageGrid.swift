import CubbyCore
import SwiftUI

/// 「图片」分类的两列网格（docs/UI-UPGRADE-PLAN.md 第 4 节）：浮动面板与侧栏里只要分类是「图片」就这样显示。
/// ↑ / ↓ 移动一整行，← / → 移动一格（搜索框为空时），翻页移动 5 行
struct ImageGrid: View {
    let items: [ClipItem]
    let viewModel: PanelViewModel

    /// 每个格子上下留出选中外环与光晕的空间（再用负间距抵消）：滚动到选中项时外环不会被视口裁掉
    private static let ringRoom: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selectedID = viewModel.selectedItem?.id
        let keywords = viewModel.keywords
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: PanelMetrics.cardSpacing), count: viewModel.selectionColumns)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: PanelMetrics.cardSpacing - Self.ringRoom * 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        cell(item, index: index, isSelected: item.id == selectedID, keywords: keywords)
                    }
                }
                .padding(.horizontal, PanelMetrics.inset)
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
                if let first = items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private func cell(_ item: ClipItem, index: Int, isSelected: Bool, keywords: [String]) -> some View {
        ImageGridCell(
            item: item, index: index, isSelected: isSelected, imageURL: viewModel.imageURL(for: item),
            translation: CardTranslationDecorations.make(for: item, keywords: keywords, viewModel: viewModel),
            isOnClothesline: viewModel.isOnClothesline(item),
            onInlineAction: { viewModel.translation?.inline.performAction() }
        )
        .e2eAnchor("list.card.\(item.id)")
        .modifier(CardInteractions(item: item, isSelected: isSelected, viewModel: viewModel, isGridCell: true))
        .padding(.vertical, Self.ringRoom)
        .id(item.id)
    }
}

/// 网格的一格：图片铺满，底部渐变上叠「来源 · 时间」与 ⌘N；选中带外环光晕
struct ImageGridCell: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let imageURL: URL?
    var translation: CardTranslationDecoration?
    var isOnClothesline = false
    var onInlineAction: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// 底部说明区的渐变高度
    private static let captionHeight: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.gridCell, style: .continuous)
        let palette = CardPalette.imageCell(colorScheme, increasedContrast: contrast == .increased)
        thumbnail
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.gridCellHeight)
            .overlay(alignment: .bottom) { caption(palette) }
            .overlay(alignment: .topLeading) { badges }
            .overlay(alignment: .topTrailing) { if isOnClothesline { ClotheslineBadge() } }
            .overlay { if translation?.inline?.isRunning == true { InlineRunningOverlay() } }
            .clipShape(shape)
            .cardSurface(palette, isSelected: isSelected, cornerRadius: Radius.gridCell)
            .contentShape(shape)
            .animation(.easeOut(duration: Motion.selection), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(
                Text("Press Return to paste, or Space to preview.", comment: "VoiceOver hint for a clipboard card"))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let peek = translation?.peek {
            PeekContent(peek: peek, item: item, imageURL: imageURL)
                .e2eAnchor("list.peek.\(item.id)")
        } else if case .image(let ref) = item.payload {
            let isTall = ImageThumbnail.isTall(width: ref.width, height: ref.height)
            Color.primary.opacity(0.05)
                .overlay(alignment: isTall ? .top : .center) {
                    AsyncThumbnail(
                        url: imageURL, maxPixelSize: ImageThumbnail.pixelSize(width: ref.width, height: ref.height),
                        contentMode: .fill)
                }
        }
    }

    /// 底部：渐变 + 说明（⌥↩ 进行中为进度，失败为原因与操作）
    private func caption(_ palette: CardPalette) -> some View {
        HStack(spacing: 6) {
            if let job = translation?.inline, job.isRunning {
                InlineProgressRow(job: job)
                    .e2eAnchor("list.inline.\(item.id)")
            } else if let job = translation?.inline, case .failed(let issue) = job.phase {
                InlineIssueRow(issue: issue, plan: job.plan, action: translation?.inlineAction, perform: onInlineAction)
                    .e2eAnchor("list.inlineIssue.\(item.id)")
            } else {
                Text(verbatim: details)
                    .font(.system(size: FontSize.caption, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if index < 9 {
                QuickPasteKeyCap(number: index + 1, isSelected: isSelected, palette: palette)
            }
        }
        .padding(.horizontal, PanelMetrics.cardImageInset + 2)
        .padding(.bottom, PanelMetrics.cardImageInset)
        .frame(maxWidth: .infinity, minHeight: Self.captionHeight, alignment: .bottom)
        .background(captionBackground)
    }

    /// 白字叠在任意图片上：文字所在的下半段至少黑 0.6；增强对比度时为实色遮罩
    @ViewBuilder
    private var captionBackground: some View {
        if contrast == .increased {
            Color.black.opacity(0.8)
        } else {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0), .init(color: .black.opacity(0.6), location: 0.45),
                    .init(color: .black.opacity(0.72), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }

    /// 左上角：缓存译文的「译」角标与收藏星标
    @ViewBuilder
    private var badges: some View {
        let languages = translation?.cachedLanguages ?? []
        if !languages.isEmpty || item.isFavorite {
            HStack(spacing: 4) {
                if !languages.isEmpty {
                    TranslationChip(languages: languages)
                        .e2eAnchor("list.chip.\(item.id)")
                }
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: FontSize.caption2))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .accessibilityHidden(true)
                }
            }
            .padding(PanelMetrics.cardImageInset + 2)
        }
    }

    private var details: String {
        [item.source?.name ?? TextStats.unknownSource, TimeFormatting.relative(item.createdAt)]
            .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        [item.source?.name ?? TextStats.unknownSource, item.title, TimeFormatting.relative(item.createdAt)]
            .joined(separator: " · ")
    }
}
