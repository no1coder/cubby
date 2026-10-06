import AppKit
import CubbyCore

/// 词块配色（docs/TEXT-PICK-DESIGN.md §3）：底色 primary 0.07、悬停 0.13；选中 = 强调色底 + 白字；
/// 标点为次要色；网址 / 邮箱 / 电话未选中时文字为强调色；增强对比度时未选中的块加 primary 0.25 描边。
/// 在 draw 中取值：动态颜色按视图当前外观（浅色 / 深色）解析
@MainActor
struct TextPickChipPalette {
    let increasedContrast: Bool

    static var current: TextPickChipPalette {
        TextPickChipPalette(increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    func fill(isSelected: Bool, isHovered: Bool) -> CGColor {
        if isSelected {
            return NSColor.controlAccentColor.cgColor
        }
        let opacity = isHovered ? TextPickMetrics.chipHoverFill : TextPickMetrics.chipFill
        return NSColor.labelColor.withAlphaComponent(opacity).cgColor
    }

    var stroke: CGColor? {
        increasedContrast ? NSColor.labelColor.withAlphaComponent(TextPickMetrics.contrastStrokeOpacity).cgColor : nil
    }

    func text(_ kind: TextPickToken.Kind, _ isSelected: Bool) -> CGColor {
        if isSelected {
            return NSColor.white.cgColor
        }
        switch kind {
        case .word: return NSColor.labelColor.cgColor
        case .entity: return NSColor.controlAccentColor.cgColor
        // 增强对比度时标点不再用淡色
        case .punctuation: return (increasedContrast ? NSColor.labelColor : NSColor.secondaryLabelColor).cgColor
        }
    }
}

/// 打开动画（§2）：可见的行依次淡入并从 0.92 放大到 1，每行 rowFadeDuration，错开到总时长不超过 0.3 秒
struct OpeningAnimation {
    /// 一行在某一刻的透明度与缩放
    struct Appearance {
        let alpha: CGFloat
        let scale: CGFloat

        static let shown = Appearance(alpha: 1, scale: 1)

        /// 以块中心为原点缩放，并整体降低透明度
        func apply(to context: CGContext, around center: CGPoint) {
            guard alpha < 1 || scale < 1 else { return }
            context.setAlpha(alpha)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)
        }
    }

    let start: CFTimeInterval
    /// 打开时可见的行数（之后的行在可见区域之外，按最后一行的时刻出现）
    let visibleRows: Int

    func appearance(ofRow row: Int, at time: CFTimeInterval) -> Appearance {
        let fade = TextPickMetrics.rowFadeDuration
        let stagger = visibleRows > 1 ? (TextPickMetrics.openingDuration - fade) / Double(visibleRows - 1) : 0
        let delay = Double(min(row, visibleRows - 1)) * stagger
        let progress = min(max((time - start - delay) / fade, 0), 1)
        // ease-out：先快后慢
        let eased = CGFloat(1 - pow(1 - progress, 3))
        let scale = TextPickMetrics.openingScale + (1 - TextPickMetrics.openingScale) * eased
        return Appearance(alpha: eased, scale: scale)
    }
}
