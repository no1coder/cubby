import CubbyCore
import SwiftUI

/// 样式条的显示状态：展示哪个工具的档位 / 颜色，以及当前样式
struct ScreenshotStyleBarModel: Equatable {
    var tool: ScreenshotTool
    var style: AnnotationStyle
}

/// 样式条（§2.6）：粗细 / 字号三档｜8 色（马赛克无颜色）
struct ScreenshotStyleBar: View {
    let model: ScreenshotStyleBarModel
    let onChange: (AnnotationStyle) -> Void

    /// 选中档位的底块在三档之间滑动
    @Namespace private var selectedWeight

    var body: some View {
        HStack(spacing: OverlayTokens.toolbarSpacing) {
            ForEach(Array(StrokeWeight.allCases.enumerated()), id: \.element) { index, weight in
                WeightButton(
                    tool: model.tool,
                    weight: weight,
                    tier: index,
                    isSelected: model.style.weight == weight,
                    namespace: selectedWeight
                ) { onChange(model.style.withWeight(weight)) }
            }
            if model.tool.usesColor {
                ToolbarSeparator()
                ForEach(Array(AnnotationColor.allCases.enumerated()), id: \.element) { index, color in
                    ColorSwatchButton(color: color, digit: index + 1, isSelected: model.style.color == color) {
                        onChange(model.style.withColor(color))
                    }
                }
            }
        }
        .padding(OverlayTokens.toolbarPadding)
        .fixedSize()
        .animation(OverlayMotion.slideAnimation, value: model.style.weight)
    }
}

/// 一档粗细：圆点 5 / 8 / 11 pt（文字工具为三种字号的 A）；选中时强调色底 + 强调色图形
///
/// 圆点显式填充：玻璃里的 `Shape` 若只靠 `foregroundStyle(.primary)` 取色，会被当作次级活力层渲染成灰
private struct WeightButton: View {
    let tool: ScreenshotTool
    let weight: StrokeWeight
    let tier: Int
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: OverlayTokens.toolbarButtonSize, height: OverlayTokens.toolbarButtonSize)
                .background { background }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(
            String(
                localized: "\(tool.weightDisplayName(weight)) ([ ])",
                comment: "Screenshot style bar weight tooltip: weight name; the [ and ] keys change the weight"
            )
        )
        .accessibilityLabel(Text(tool.weightDisplayName(weight)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 未选中：深色玻璃上白、浅色玻璃上近黑
    private var glyphColor: Color {
        if isSelected { return .accentColor }
        return colorScheme == .dark ? .white : Color.black.opacity(OverlayTokens.lightGlyphOpacity)
    }

    @ViewBuilder private var glyph: some View {
        if tool == .text {
            Text(verbatim: "A")
                .font(.system(size: OverlayTokens.weightLetterSizes[tier], weight: .semibold))
                .foregroundStyle(glyphColor)
        } else {
            let diameter = OverlayTokens.weightDotDiameters[tier]
            Circle()
                .fill(glyphColor)
                .frame(width: diameter, height: diameter)
        }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        if isSelected {
            shape.fill(Color.accentColor.opacity(OverlayTokens.activeFillOpacity))
                .matchedGeometryEffect(id: "weight", in: namespace)
        } else if isHovered {
            shape.fill(Color.primary.opacity(OverlayTokens.buttonHoverOpacity))
        }
    }
}

/// 16 pt 色块：1 pt `white 0.6` 描边（白色另加 `black 0.2`）；选中时外加 2 pt 环
///
/// 选中环用前景色（深色下白、浅色下近黑）而不是强调色：蓝色色块配强调色环时两者同色，环就看不见了
private struct ColorSwatchButton: View {
    let color: AnnotationColor
    /// 选这个颜色的数字键（1–8）
    let digit: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(OverlayColors.swiftUIColor(color))
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(OverlayTokens.swatchBorderOpacity), lineWidth: 1)
                    )
                    .overlay {
                        if color == .white {
                            Circle().strokeBorder(
                                Color.black.opacity(OverlayTokens.whiteSwatchBorderOpacity), lineWidth: 1)
                        }
                    }
                    .frame(width: OverlayTokens.swatchDiameter, height: OverlayTokens.swatchDiameter)
                if isSelected {
                    Circle()
                        .strokeBorder(ringColor, lineWidth: OverlayTokens.swatchRingWidth)
                        .frame(width: ringDiameter, height: ringDiameter)
                }
            }
            .scaleEffect(isHovered && !isSelected ? OverlayTokens.swatchHoverScale : 1)
            .animation(
                OverlayMotion.isReduced ? nil : .easeOut(duration: OverlayTokens.swatchHoverDuration), value: isHovered
            )
            .frame(width: OverlayTokens.toolbarButtonSize, height: OverlayTokens.toolbarButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(
            String(
                localized: "\(color.displayName) (\(digit))",
                comment: "Screenshot style bar color tooltip: color name and the number key that selects it"
            )
        )
        .accessibilityLabel(Text(color.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var ringColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(OverlayTokens.lightSwatchRingOpacity)
    }

    /// 环与色块之间留 1 pt 缝
    private var ringDiameter: CGFloat {
        OverlayTokens.swatchDiameter + (OverlayTokens.swatchRingWidth + OverlayTokens.swatchRingGap) * 2
    }
}
