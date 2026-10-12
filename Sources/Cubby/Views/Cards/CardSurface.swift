import SwiftUI

/// 卡片外观：底色、0.5pt 描边、选中态（2pt 强调色外环 + 外侧 4pt 的 22% 光晕 + 底色略提亮）与投影。
/// 外环与光晕画在卡片边界之外，列表为每张卡片留了上下 edgeFade、左右 inset 的空间
struct CardSurface: ViewModifier {
    let palette: CardPalette
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// 外环宽度与光晕宽度（光晕从外环外缘再向外扩展）
    private static let ringWidth: CGFloat = 2
    private static let glowWidth: CGFloat = 4

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .background(shape.fill(isSelected ? palette.selectedBackground ?? palette.background : palette.background))
            .overlay(shape.strokeBorder(palette.stroke, lineWidth: 0.5))
            .overlay { if isSelected { selectionRing } }
            .shadow(color: shadowColor, radius: isSelected ? 12 : 1, y: isSelected ? 10 : 1)
    }

    @ViewBuilder
    private var selectionRing: some View {
        let ring = Self.ringWidth
        let glow = Self.glowWidth
        RoundedRectangle(cornerRadius: Radius.card + ring / 2, style: .continuous)
            .stroke(Color.accentColor, lineWidth: ring)
            .padding(-ring / 2)
        RoundedRectangle(cornerRadius: Radius.card + ring + glow / 2, style: .continuous)
            .stroke(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: glow)
            .padding(-(ring + glow / 2))
        // 彩色 / 代码卡再加一圈白色内环，保证在任何底色上可辨
        if palette.isCustom {
            RoundedRectangle(cornerRadius: Radius.card - 2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .padding(2)
        }
    }

    /// 深色玻璃上普通卡不加投影（只有选中时浮起）；浅色下所有卡片都有一层很淡的投影
    private var shadowColor: Color {
        let isDark = colorScheme == .dark
        if isSelected {
            return isDark ? Color.black.opacity(0.25) : Color(red: 0.12, green: 0.16, blue: 0.35).opacity(0.12)
        }
        return isDark ? .clear : Color(red: 0.12, green: 0.16, blue: 0.35).opacity(0.06)
    }
}

extension View {
    func cardSurface(_ palette: CardPalette, isSelected: Bool) -> some View {
        modifier(CardSurface(palette: palette, isSelected: isSelected))
    }
}
