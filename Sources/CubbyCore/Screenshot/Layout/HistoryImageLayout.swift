import CoreGraphics

/// 晾衣绳放大编辑（docs/UI-UPGRADE-PLAN.md §5 `ClotheslineEdit`）：历史图片在屏幕上的位置与缩放
///
/// 缩放 = 显示的点数 / 图片像素数（与屏幕倍率无关：1600 px 宽的图显示为 992 pt 宽即 62%）。
/// 默认「适合」：不超过屏幕宽 80%、高 70%，并且不压到顶部的晾衣绳与底部的工具栏、提示；最多放大到 2×。
/// 所有矩形都是全局点并对齐到屏幕像素网格（锁定的选区不再由 reducer 吸附）。
public struct HistoryImageLayout: Equatable, Sendable {
    /// 顶部留给晾衣绳（绳子仍在上方可见）与图片上方的标题行
    public static let topReserve: CGFloat = 170
    /// 底部留给工具栏、样式条与快捷键提示
    public static let bottomReserve: CGFloat = 180
    /// 左右至少留出的边距（放大到最大时）
    public static let sideMargin: CGFloat = 40
    /// 手动放大超过「适合」时：顶部只留标题行、底部只留工具栏（图片可以盖住晾衣绳与提示）
    public static let zoomedTopReserve: CGFloat = 60
    public static let zoomedBottomReserve: CGFloat = 100
    /// 「适合」时占屏幕宽 / 高的上限
    public static let fitWidthFraction: CGFloat = 0.8
    public static let fitHeightFraction: CGFloat = 0.7
    /// 放大上限：一个图片像素最多显示为 2 pt
    public static let maximumZoom: CGFloat = 2
    /// 缩小下限
    public static let minimumZoom: CGFloat = 0.1
    /// − / + 逐档切换的缩放档位
    public static let zoomSteps: [CGFloat] = [0.1, 0.125, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2]

    /// 图片（即锁定的选区）在屏幕上的位置
    public let imageRect: CGRect
    /// 当前缩放
    public let zoom: CGFloat
    /// 允许的缩放范围（放得下的最大值不超过 2×；最小值不大于「适合」）
    public let zoomRange: ClosedRange<CGFloat>
    /// 图片像素尺寸
    public let imagePixelSize: CGSize

    /// 显示用的百分比（四舍五入）
    public var zoomPercent: Int {
        Int((zoom * 100).rounded())
    }

    public var canZoomIn: Bool {
        zoom < zoomRange.upperBound - Self.epsilon
    }

    public var canZoomOut: Bool {
        zoom > zoomRange.lowerBound + Self.epsilon
    }

    /// 导出用的原生倍率：图片像素 / 选区点数（按宽度计算，导出时高度按同一倍率）
    public var nativeScale: CGFloat {
        imagePixelSize.width / imageRect.width
    }

    /// 导出用的矩形：与 imageRect 同原点、同宽，高度按原生倍率换算，导出恰好是原图的像素尺寸
    public var nativeRect: CGRect {
        CGRect(
            x: imageRect.minX, y: imageRect.minY, width: imageRect.width,
            height: imagePixelSize.height / nativeScale)
    }

    private static let epsilon: CGFloat = 0.0005

    /// zoom 为 nil 时取「适合」；图片或屏幕尺寸无效时为 nil
    public static func layout(imagePixelSize: CGSize, screen: CaptureScreen, zoom: CGFloat? = nil)
        -> HistoryImageLayout?
    {
        let pixels = imagePixelSize
        let frame = screen.frame
        guard pixels.width >= 1, pixels.height >= 1, screen.scale > 0, frame.width > 0, frame.height > 0,
            pixels.width.isFinite, pixels.height.isFinite
        else { return nil }
        let band = verticalBand(in: frame)
        let fitBox = CGSize(
            width: frame.width * fitWidthFraction,
            height: min(frame.height * fitHeightFraction, band.height))
        let zoomedBand = zoomedBand(in: frame, fitBand: band)
        let maxBox = CGSize(width: frame.width - sideMargin * 2, height: zoomedBand.height)
        let fit = min(fitting(pixels, in: fitBox), maximumZoom)
        let upper = max(min(fitting(pixels, in: maxBox), maximumZoom), fit)
        let lower = min(minimumZoom, fit)
        let applied = min(max(zoom ?? fit, lower), upper)
        let rect = placed(pixels, zoom: applied, band: band, limit: zoomedBand, screen: screen)
        return HistoryImageLayout(
            imageRect: rect, zoom: applied, zoomRange: lower...upper, imagePixelSize: pixels)
    }

    /// − / + 一档：下一个比当前大（小）的档位，夹在允许范围内；已到头时不变
    public func steppedZoom(_ direction: Int) -> CGFloat {
        guard direction != 0 else { return zoom }
        let next =
            direction > 0
            ? Self.zoomSteps.first { $0 > zoom + Self.epsilon } ?? zoomRange.upperBound
            : Self.zoomSteps.last { $0 < zoom - Self.epsilon } ?? zoomRange.lowerBound
        return min(max(next, zoomRange.lowerBound), zoomRange.upperBound)
    }

    // MARK: - 内部

    /// 图片可占的竖直范围：顶部留给晾衣绳与标题，底部留给工具栏与提示；屏幕太矮时退回整屏中间一半
    private static func verticalBand(in frame: CGRect) -> CGRect {
        let top = frame.minY + topReserve
        let bottom = frame.maxY - bottomReserve
        guard bottom - top >= frame.height * 0.25 else {
            return frame.insetBy(dx: 0, dy: frame.height * 0.25)
        }
        return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
    }

    /// 放大时图片可占的竖直范围（不小于「适合」的范围）
    private static func zoomedBand(in frame: CGRect, fitBand: CGRect) -> CGRect {
        let top = min(frame.minY + zoomedTopReserve, fitBand.minY)
        let bottom = max(frame.maxY - zoomedBottomReserve, fitBand.maxY)
        return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
    }

    private static func fitting(_ pixels: CGSize, in box: CGSize) -> CGFloat {
        max(min(box.width / pixels.width, box.height / pixels.height), 0)
    }

    /// 水平居中、在「适合」的竖直范围内居中（放大后超出时夹回 limit 内），尺寸与原点对齐到屏幕像素（至少 1 个像素）
    private static func placed(
        _ pixels: CGSize, zoom: CGFloat, band: CGRect, limit: CGRect, screen: CaptureScreen
    ) -> CGRect {
        let scale = screen.scale
        let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
        let width = max(snap(pixels.width * zoom), 1 / scale)
        let height = max(snap(pixels.height * zoom), 1 / scale)
        let originX = screen.frame.minX + snap(screen.frame.midX - screen.frame.minX - width / 2)
        let centered = band.midY - height / 2
        let clamped = min(max(centered, limit.minY), max(limit.maxY - height, limit.minY))
        let originY = screen.frame.minY + snap(clamped - screen.frame.minY)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}
