import AppKit
import CubbyCore
import SwiftUI

/// 晾衣绳放大编辑（docs/UI-UPGRADE-PLAN.md §5 `ClotheslineEdit`）的上下文：协调器构建，覆盖层持有
struct HistoryEditContext {
    /// 原图本身作为一帧：屏幕 frame = 导出矩形、scale = 原生倍率，导出即原图的像素尺寸
    let nativeFrame: FrozenFrame
    /// 原图 PNG 的 DPI 倍率（DPI / 72，没有记录时为 1）：导出的 PNG 沿用它
    let pngScale: CGFloat
    /// 图片在屏幕上的位置与缩放
    let layout: HistoryImageLayout
    /// 标题行：来源应用图标与名称、「W × H · 晾上 HH:mm」
    let icon: NSImage?
    let title: String
    let detail: String
    /// − / +：方向 -1 / +1（由协调器以新的缩放重建覆盖层）
    let onZoom: @MainActor (Int) -> Void
}

/// 标题行每次渲染的状态（值类型，变化时才刷新 SwiftUI）
struct HistoryEditHeaderModel: Equatable {
    let title: String
    let detail: String
    let zoomPercent: Int
    /// 有标注或译文后不能再缩放（缩放会重建覆盖层）
    let canZoomIn: Bool
    let canZoomOut: Bool
}

/// 图片上方的标题行：来源 · 尺寸 · 晾上时间（左），缩放与关闭（右）
struct HistoryEditHeader: View {
    let model: HistoryEditHeaderModel
    let icon: NSImage?
    let onZoom: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: HistoryEditTokens.headerSpacing) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: HistoryEditTokens.iconSize, height: HistoryEditTokens.iconSize)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: FontSize.body, weight: .semibold))
                    .foregroundStyle(.white)
                Text(model.detail)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(.white.opacity(HistoryEditTokens.secondaryTextOpacity))
                    .monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: HistoryEditTokens.headerSpacing)
            zoomControl
            HistoryEditRoundButton(
                symbol: "xmark",
                tooltip: String(localized: "Put Back (Esc)", comment: "Clothesline image editor close button tooltip"),
                label: String(
                    localized: "Put Back", comment: "Clothesline image editor close button accessibility label"),
                action: onClose)
        }
        .environment(\.colorScheme, .dark)
    }

    private var zoomControl: some View {
        HStack(spacing: 0) {
            HistoryEditZoomButton(
                symbol: "minus",
                label: String(localized: "Zoom Out", comment: "Clothesline image editor zoom button"),
                isEnabled: model.canZoomOut
            ) { onZoom(-1) }
            Text(verbatim: "\(model.zoomPercent)%")
                .font(.system(size: FontSize.caption, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(HistoryEditTokens.primaryTextOpacity))
                .frame(minWidth: HistoryEditTokens.zoomLabelWidth)
            HistoryEditZoomButton(
                symbol: "plus",
                label: String(localized: "Zoom In", comment: "Clothesline image editor zoom button"),
                isEnabled: model.canZoomIn
            ) { onZoom(1) }
        }
        .padding(.horizontal, 2)
        .frame(height: HistoryEditTokens.controlHeight)
        .background(HistoryEditTokens.controlShape.fill(.white.opacity(HistoryEditTokens.controlFillOpacity)))
        .overlay(
            HistoryEditTokens.controlShape.strokeBorder(.white.opacity(HistoryEditTokens.controlBorderOpacity))
        )
    }
}

/// 缩放 − / +：缩放会重建覆盖层，有标注后禁用（tooltip 说明原因）
private struct HistoryEditZoomButton: View {
    let symbol: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: FontSize.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : HistoryEditTokens.disabledOpacity))
                .frame(width: HistoryEditTokens.zoomButtonWidth, height: HistoryEditTokens.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(
            isEnabled
                ? label
                : String(
                    localized: "Zoom isn't available after annotating",
                    comment: "Clothesline image editor: tooltip of the disabled zoom buttons")
        )
        .accessibilityLabel(Text(label))
    }
}

/// 28 pt 圆形按钮（关闭）
private struct HistoryEditRoundButton: View {
    let symbol: String
    let tooltip: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: FontSize.footnote, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: HistoryEditTokens.controlHeight, height: HistoryEditTokens.controlHeight)
                .background(
                    Circle().fill(
                        .white.opacity(
                            isHovered ? HistoryEditTokens.controlHoverOpacity : HistoryEditTokens.controlFillOpacity))
                )
                .overlay(Circle().strokeBorder(.white.opacity(HistoryEditTokens.controlBorderOpacity)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(Text(label))
    }
}

/// 工具栏下方的快捷键提示：⌘C 复制标注后的图 · ↩ 完成，原图保留在历史 · esc 放回绳上
struct HistoryEditHint: View {
    var body: some View {
        HStack(spacing: HistoryEditTokens.hintGroupSpacing) {
            item(
                key: "⌘C",
                String(localized: "Copy annotated image", comment: "Clothesline image editor hint after the ⌘C key cap")
            )
            item(
                key: "↩",
                String(
                    localized: "Done, the original stays in history",
                    comment: "Clothesline image editor hint after the Return key cap"))
            item(
                key: "esc",
                String(localized: "Put back", comment: "Clothesline image editor hint after the esc key cap"))
        }
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }

    private func item(key: String, _ text: String) -> some View {
        HStack(spacing: HistoryEditTokens.hintKeySpacing) {
            Text(verbatim: key)
                .font(.system(size: FontSize.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(HistoryEditTokens.primaryTextOpacity))
                .padding(.horizontal, 6)
                .frame(minWidth: HistoryEditTokens.keyCapHeight, minHeight: HistoryEditTokens.keyCapHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(HistoryEditTokens.keyCapFillOpacity)))
            Text(text)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.white.opacity(HistoryEditTokens.secondaryTextOpacity))
        }
    }
}

/// 放大编辑的尺寸与不透明度（覆盖层底色总是压暗的深色，文字一律用白色）
enum HistoryEditTokens {
    static let headerHeight: CGFloat = 36
    /// 标题行底边与图片顶边的间距
    static let headerGap: CGFloat = 12
    static let headerSpacing: CGFloat = 10
    static let iconSize: CGFloat = 24
    static let controlHeight: CGFloat = 28
    static let zoomButtonWidth: CGFloat = 26
    static let zoomLabelWidth: CGFloat = 40
    static let controlShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    static let controlFillOpacity: Double = 0.1
    static let controlHoverOpacity: Double = 0.18
    static let controlBorderOpacity: Double = 0.15
    static let primaryTextOpacity: Double = 0.9
    static let secondaryTextOpacity: Double = 0.6
    static let disabledOpacity: Double = 0.3
    static let keyCapHeight: CGFloat = 20
    static let keyCapFillOpacity: Double = 0.14
    static let hintKeySpacing: CGFloat = 6
    static let hintGroupSpacing: CGFloat = 16
    /// 工具栏与图片之间的间距（比截图的 8 pt 宽松，与设计稿一致）
    static let toolbarGap: CGFloat = 24
    /// 提示行与屏幕底边的距离；工具栏 / 样式条更低时排在它们下方
    static let hintBottomInset: CGFloat = 44
    static let hintGap: CGFloat = 16
    /// 工具栏「复制」按钮的底色（悬停时加深）
    static let textButtonFillOpacity: Double = 0.1
    static let textButtonHoverOpacity: Double = 0.16
}
