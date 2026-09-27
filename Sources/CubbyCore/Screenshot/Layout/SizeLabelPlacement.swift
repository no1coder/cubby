import CoreGraphics

/// 尺寸标签相对选区的位置
public enum SizeLabelSide: Equatable, Sendable {
    /// 选区左上角外侧、上方
    case aboveOutside
    /// 选区左下角外侧、下方
    case belowOutside
    /// 选区内侧左上
    case inside
}

/// 尺寸标签摆放结果（全局点坐标）
public struct SizeLabelLayout: Equatable, Sendable {
    public let frame: CGRect
    public let side: SizeLabelSide

    public init(frame: CGRect, side: SizeLabelSide) {
        self.frame = frame
        self.side = side
    }
}

/// 尺寸标签摆放与文本（§2.5）：上方外侧 → 下方外侧 → 内侧左上，水平方向夹紧在屏幕内
public enum SizeLabelPlacement {
    /// 标签与选区的默认间距：8 pt 给角手柄（悬停放大到 10 pt）留出余量（评审 P2-1）
    public static let defaultGap: CGFloat = 8

    public static func layout(labelSize: CGSize, selection: CGRect, screen: CGRect, gap: CGFloat = defaultGap)
        -> SizeLabelLayout
    {
        let size = CGSize(width: min(labelSize.width, screen.width), height: min(labelSize.height, screen.height))
        let box = selection.standardized

        let side: SizeLabelSide
        let origin: CGPoint
        if box.minY - gap - size.height >= screen.minY {
            side = .aboveOutside
            origin = CGPoint(x: box.minX, y: box.minY - gap - size.height)
        } else if box.maxY + gap + size.height <= screen.maxY {
            side = .belowOutside
            origin = CGPoint(x: box.minX, y: box.maxY + gap)
        } else {
            side = .inside
            origin = CGPoint(x: box.minX + gap, y: box.minY + gap)
        }
        let frame = SelectionGeometry.clamped(CGRect(origin: origin, size: size), to: screen)
        return SizeLabelLayout(frame: frame, side: side)
    }

    /// "1280 × 720"：像素尺寸与导出一致（点 × scale 后 integral，同 `CaptureScreen.pixelRect`）。
    /// reducer 已把选区吸附到像素网格，此时结果就是「点 × scale」
    public static func text(for selection: CGRect, scale: CGFloat) -> String {
        let box = selection.standardized
        let pixels = CGRect(
            x: box.minX * scale, y: box.minY * scale, width: box.width * scale, height: box.height * scale
        )
        .integral
        return "\(Int(pixels.width)) × \(Int(pixels.height))"
    }
}
