import CubbyCore
import SwiftUI

/// 图片条目的翻译卡正文（原型 stageHTML）：原图 + 逐块淡入的译文层；「对照」为卷帘（左原文、右译文，
/// 2pt 白线 + 28pt 拖柄，拖动或点过后 ← / → 微调）；悬停某块 400 ms 显示其原文气泡；按住 ⌥ 看原文
struct TranslationImageBody: View {
    let card: TranslationCard
    let imageURL: URL?
    let ref: ImageRef
    let controller: TranslationCardController

    @State private var pointScale: CGFloat = 1
    @State private var hovered: Int?
    @State private var bubble: Int?

    private static let knobSize: CGFloat = 28
    private static let bubbleMaxWidth: CGFloat = 330
    /// 块上方至少有这么多空间才把气泡放在上方
    private static let bubbleRoomAbove: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in
            let size = fittedSize(in: geometry.size)
            stage(size: size)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(PreviewMetrics.imageInset)
        .task(id: imageURL) {
            // 只读文件头，但仍放到后台：不在主线程做文件读取
            let url = imageURL
            pointScale = await Task.detached(priority: .userInitiated) { ImagePointScale.read(url) }.value
        }
        .task(id: hovered) {
            bubble = nil
            guard let hovered else { return }
            try? await Task.sleep(for: controller.environment.timings.bubbleDelay)
            guard !Task.isCancelled else { return }
            bubble = hovered
        }
    }

    // MARK: - 舞台

    private func stage(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            AsyncThumbnail(url: imageURL, maxPixelSize: 1600)
            translatedImage
            TranslationOverlayView(
                model: overlayModel,
                onHover: { hovered = $0 },
                onWipe: { controller.setWipe($0, focusDivider: true) }
            )
            if card.phase == .waiting || card.phase == .streaming {
                // 识别与翻译进行中：整图一道淡淡的扫光（块的位置到达前未知，不能像原型那样逐块占位）
                ShimmerSweep(tint: Color.accentColor.opacity(0.14))
            }
            if showsDivider {
                divider(size: size)
            }
            if card.isPeeking {
                chip(TranslationCopy.imagePeekChip)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .overlay { bubbleOverlay(size: size) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .animation(.easeOut(duration: Motion.fade), value: card.isPeeking)
        .e2eAnchor("card.stage")
    }

    /// 缓存命中时没有块版面（缓存只存译后成图）：直接叠译后图片，同样受卷帘与按住 ⌥ 控制
    @ViewBuilder
    private var translatedImage: some View {
        if card.content.imageBlocks.isEmpty, let url = card.result?.imageURL {
            AsyncThumbnail(url: url, maxPixelSize: 1600)
                .mask {
                    GeometryReader { geometry in
                        let x = geometry.size.width * (overlayModel.wipe ?? 0)
                        Rectangle().frame(width: max(geometry.size.width - x, 0)).offset(x: x)
                    }
                }
                .opacity(overlayModel.hidesTranslation ? 0 : 1)
        }
    }

    private var overlayModel: TranslationOverlayView.Model {
        TranslationOverlayView.Model(
            blocks: card.content.imageBlocks,
            imagePointSize: CGSize(width: CGFloat(ref.width) / pointScale, height: CGFloat(ref.height) / pointScale),
            wipe: showsDivider ? card.wipe : nil,
            hidesTranslation: card.isPeeking || card.mode == .original,
            highlighted: bubble)
    }

    private var showsDivider: Bool {
        card.mode == .sideBySide && card.phase == .done && !card.isPeeking
    }

    // MARK: - 卷帘

    private func divider(size: CGSize) -> some View {
        let x = size.width * card.wipe
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: size.height)
                .shadow(color: .black.opacity(0.45), radius: 3)
                .offset(x: x - 1)
            chip(TranslationCopy.originalChip)
                .fixedSize()
                .frame(width: max(x - 8, 0), alignment: .trailing)
                .padding(.top, 8)
            chip(TranslationCopy.translationChip)
                .fixedSize()
                .offset(x: x + 8, y: 8)
            knob
                .offset(x: x - Self.knobSize / 2, y: size.height / 2 - Self.knobSize / 2)
        }
        .allowsHitTesting(false)
        .e2eAnchor("card.divider")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TranslationCopy.dividerLabel)
        .accessibilityValue(Text(card.wipe, format: .percent.precision(.fractionLength(0))))
    }

    private var knob: some View {
        HStack(spacing: -2) {
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right")
        }
        .font(.system(size: FontSize.caption2, weight: .bold))
        .foregroundStyle(Color(white: 0.2))
        .frame(width: Self.knobSize, height: Self.knobSize)
        .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.4), radius: 2.5, y: 1))
        .overlay {
            if card.isDividerFocused {
                Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-3)
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: FontSize.caption2, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .allowsHitTesting(false)
    }

    // MARK: - 原文气泡

    /// 原文气泡：放在块的上方（上方放不下时放下方），左右按块在哪一半对齐，不超出舞台。
    /// 用 overlay + offset 定位，不影响舞台布局
    @ViewBuilder
    private func bubbleOverlay(size: CGSize) -> some View {
        if let bubble, let item = card.content.imageBlocks.first(where: { $0.block.blockID == bubble }) {
            let factor = size.width / max(CGFloat(ref.width) / pointScale, 1)
            let rect = CGRect(
                x: item.block.eraseFrame.minX * factor, y: item.block.eraseFrame.minY * factor,
                width: item.block.eraseFrame.width * factor, height: item.block.eraseFrame.height * factor)
            let above = rect.minY > Self.bubbleRoomAbove
            let leading = rect.midX < size.width / 2
            let alignment: Alignment =
                switch (above, leading) {
                case (true, true): .bottomLeading
                case (true, false): .bottomTrailing
                case (false, true): .topLeading
                case (false, false): .topTrailing
                }
            bubbleView(item)
                .frame(maxWidth: min(Self.bubbleMaxWidth, size.width - 8), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(
                    x: leading ? max(rect.minX, 4) : min(rect.maxX - size.width, -4),
                    y: above ? rect.minY - 6 - size.height : rect.maxY + 6
                )
                .frame(width: size.width, height: size.height, alignment: alignment)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func bubbleView(_ item: TranslatedImageBlock) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TranslationCopy.bubbleTitle)
                .font(.system(size: FontSize.caption2, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(item.original)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.12).opacity(0.94)))
        .e2eAnchor("card.bubble")
    }

    // MARK: - 尺寸

    /// 按宽高比放进可用区域，不放大到超过原始像素（与预览一致）
    private func fittedSize(in available: CGSize) -> CGSize {
        guard ref.width > 0, ref.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let maxWidth = min(available.width, CGFloat(ref.width))
        let maxHeight = min(available.height, CGFloat(ref.height))
        let ratio = CGFloat(ref.width) / CGFloat(ref.height)
        let width = min(maxWidth, maxHeight * ratio)
        return CGSize(width: width, height: width / ratio)
    }
}
