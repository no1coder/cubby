import AppKit
import CubbyCore

/// 放大镜的一次读数：像素网格 + 点坐标 + 颜色文本
struct MagnifierReading: Equatable {
    let grid: PixelGrid
    /// 相对当前屏幕左上角的点坐标
    let point: CGPoint
    /// 第二行：`#RRGGBB` 或 `rgb(255, 136, 0)`；帧外为空
    let colorText: String
}

/// 放大镜（§2.4）：15 × 15 最近邻像素网格 + 中心描框 + 十字辅助线，下方两行等宽读数
///
/// 每个源像素画成 7 pt 方格（Retina 上 = 14 设备像素）；格子按点定义，
/// 不同缩放的屏幕上视觉大小一致。容器 `black 0.9`、圆角 8、1 pt `white 0.2` 描边、无阴影。
final class MagnifierView: OverlayPassthroughView {
    private var reading: MagnifierReading?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Radius.control
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(OverlayTokens.magnifierBackgroundAlpha).cgColor
        // 外圈 1 pt 深色发丝线：放大镜压在白色内容上时也有清晰边界；内圈白线在 draw 里画
        layer?.borderColor = NSColor.black.withAlphaComponent(OverlayTokens.magnifierOuterBorderAlpha).cgColor
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 读数不变时不重绘（光标在同一像素内移动）
    func show(_ reading: MagnifierReading, frame: CGRect) {
        if self.frame != frame {
            self.frame = frame
        }
        if self.reading != reading {
            self.reading = reading
            needsDisplay = true
        }
        isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let reading, let context = NSGraphicsContext.current?.cgContext else { return }
        drawGrid(reading.grid, in: context)
        drawGridLines(in: context)
        drawCrosshair(in: context)
        drawCenterFrame(in: context)
        drawInfo(reading)
        drawInnerBorder(in: context)
    }

    /// 1 pt `white 0.2` 描边（§2.4），紧贴外圈深色线内侧
    private func drawInnerBorder(in context: CGContext) {
        let inset = OverlayTokens.magnifierInnerBorderInset
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: Radius.control - inset,
            cornerHeight: Radius.control - inset,
            transform: nil
        )
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.white.withAlphaComponent(OverlayTokens.magnifierBorderAlpha).cgColor)
        context.addPath(path)
        context.strokePath()
    }

    // MARK: - 网格

    private var cell: CGFloat { OverlayTokens.magnifierCellSize }
    private var side: CGFloat { OverlayTokens.magnifierGridSide }
    private var radius: Int { OverlayTokens.magnifierRadius }

    /// 每格一个纯色方块（最近邻：不做任何插值）；帧外的格子留黑
    private func drawGrid(_ grid: PixelGrid, in context: CGContext) {
        for row in -radius...radius {
            for column in -radius...radius {
                guard let color = grid.color(dx: column, dy: row) else { continue }
                context.setFillColor(OverlayColors.cgColor(color))
                context.fill(cellRect(column: column, row: row))
            }
        }
    }

    private func cellRect(column: Int, row: Int) -> CGRect {
        CGRect(
            x: CGFloat(column + radius) * cell,
            y: CGFloat(row + radius) * cell,
            width: cell,
            height: cell
        )
    }

    /// 1 px `white 0.12` 网格线（按设备像素宽度，Retina 上仍是一根发丝线）
    private func drawGridLines(in context: CGContext) {
        let hairline = 1 / max(window?.backingScaleFactor ?? 2, 1)
        context.setFillColor(NSColor.white.withAlphaComponent(OverlayTokens.magnifierGridLineAlpha).cgColor)
        for index in 1..<(radius * 2 + 1) {
            let offset = CGFloat(index) * cell
            context.fill(CGRect(x: offset, y: 0, width: hairline, height: side))
            context.fill(CGRect(x: 0, y: offset, width: side, height: hairline))
        }
    }

    /// 从网格边缘指向中心格的十字辅助线（`accent 0.5`，1 pt，停在中心格外）
    private func drawCrosshair(in context: CGContext) {
        let center = cellRect(column: 0, row: 0)
        let color = OverlayColors.accent.withAlphaComponent(OverlayTokens.magnifierCrosshairAlpha)
        context.setFillColor(color.cgColor)
        let midX = center.midX - 0.5
        let midY = center.midY - 0.5
        context.fill(CGRect(x: midX, y: 0, width: 1, height: center.minY))
        context.fill(CGRect(x: midX, y: center.maxY, width: 1, height: side - center.maxY))
        context.fill(CGRect(x: 0, y: midY, width: center.minX, height: 1))
        context.fill(CGRect(x: center.maxX, y: midY, width: side - center.maxX, height: 1))
    }

    /// 中心像素：外描 1 pt 强调色 + 内描 1 pt 白
    private func drawCenterFrame(in context: CGContext) {
        let center = cellRect(column: 0, row: 0)
        context.setLineWidth(1)
        context.setStrokeColor(OverlayColors.accent.cgColor)
        context.stroke(center.insetBy(dx: -0.5, dy: -0.5))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(center.insetBy(dx: 0.5, dy: 0.5))
    }

    // MARK: - 读数

    /// 两行等宽读数，行高按 11 pt 固定；某一行放不下（`rgb(255, 255, 255)` 约 105 pt）时该行退到 10 pt
    private func drawInfo(_ reading: MagnifierReading) {
        let coordinates = "(\(Int(reading.point.x.rounded(.down))), \(Int(reading.point.y.rounded(.down))))"
        let lines = [coordinates, reading.colorText].filter { !$0.isEmpty }
        let base = Self.infoFont(size: FontSize.caption)
        let lineHeight = ceil(base.ascender - base.descender + base.leading)
        let top = side + (OverlayTokens.magnifierInfoHeight - lineHeight * CGFloat(lines.count)) / 2
        let available = bounds.width - OverlayTokens.magnifierInfoPadding * 2
        for (index, line) in lines.enumerated() {
            var attributes = Self.infoAttributes(size: FontSize.caption)
            if (line as NSString).size(withAttributes: attributes).width > available {
                attributes = Self.infoAttributes(size: FontSize.caption2)
            }
            let size = (line as NSString).size(withAttributes: attributes)
            let origin = CGPoint(
                x: ((bounds.width - size.width) / 2).rounded(),
                y: top + CGFloat(index) * lineHeight + (lineHeight - size.height) / 2
            )
            (line as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    private static func infoFont(size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    private static func infoAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: infoFont(size: size), .foregroundColor: NSColor.white]
    }
}
