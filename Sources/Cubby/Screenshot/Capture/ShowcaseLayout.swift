#if DEBUG
import AppKit
import CubbyCore

/// 展示场景的几何（全局点，左上原点）：一块 880 × 640 的「场景」放在第一块屏幕中央，
/// 里面是前面的发布说明窗口、后面的天气窗口和一个预置选区。画面与预置标注共用这里的坐标
struct ShowcaseLayout {
    static let sceneSize = CGSize(width: 880, height: 640)
    static let notesID: UInt32 = 9201
    static let weatherID: UInt32 = 9202
    static let titleBarHeight: CGFloat = 28
    /// 虚构的七天最高气温（°C），最后一天最高
    static let forecastHighs: [CGFloat] = [19, 21, 20, 22, 24, 26, 29]
    /// 柱状图纵轴的下限与上限（°C）：柱高只表示相对高低
    static let chartFloor: CGFloat = 12
    static let chartCeiling: CGFloat = 30

    /// 正文字号与行距
    static let bodySize: CGFloat = 14
    static let bulletSpacing: CGFloat = 30

    /// 场景左上角：屏幕中央；屏幕比场景小时贴屏幕左上角
    let origin: CGPoint

    init(screen: CaptureScreen) {
        let frame = screen.frame
        origin = CGPoint(
            x: frame.minX + max(0, (frame.width - Self.sceneSize.width) / 2).rounded(),
            y: frame.minY + max(0, (frame.height - Self.sceneSize.height) / 2).rounded())
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: origin.x + x, y: origin.y + y, width: width, height: height)
    }

    // MARK: - 选区与窗口

    var selection: CGRect { rect(52, 64, 748, 456) }
    var notes: CGRect { rect(88, 126, 360, 372) }
    var weather: CGRect { rect(336, 92, 440, 372) }

    /// 窗口列表（前 → 后）；进程号是假的，不能与 Cubby 自身相同，否则悬停识别会排除它们
    var candidates: [WindowCandidate] {
        [(Self.notesID, notes), (Self.weatherID, weather)].map { id, frame in
            WindowCandidate(id: id, frame: frame, layer: 0, ownerPID: pid_t(Int32(id)), alpha: 1)
        }
    }

    // MARK: - 发布说明窗口

    /// 正文左边距、项目符号文字的起点
    var notesTextX: CGFloat { notes.minX + 28 }
    var bulletTextX: CGFloat { notes.minX + 62 }

    /// 第 index 条要点的行框（宽度为文字宽度）
    func bulletLine(_ index: Int, copy: ShowcaseCopy) -> CGRect {
        let top = notes.minY + 160 + CGFloat(index) * Self.bulletSpacing
        let width = ShowcaseText.width(copy.bullets[index], size: Self.bodySize, weight: .regular)
        return CGRect(x: bulletTextX, y: top, width: width, height: ShowcaseText.lineHeight(size: Self.bodySize))
    }

    /// 序号标注的圆心：要点左侧
    func numberCenter(_ index: Int, copy: ShowcaseCopy) -> CGPoint {
        let line = bulletLine(index, copy: copy)
        return CGPoint(x: notes.minX + 26, y: line.midY)
    }

    var contactTop: CGFloat { notes.minY + 322 }

    /// 邮箱文字的行框
    func emailLine(copy: ShowcaseCopy) -> CGRect {
        let prefix = ShowcaseText.width(copy.contactPrefix, size: Self.bodySize, weight: .regular)
        let width = ShowcaseText.width(copy.email, size: Self.bodySize, weight: .regular)
        return CGRect(
            x: notesTextX + prefix, y: contactTop, width: width,
            height: ShowcaseText.lineHeight(size: Self.bodySize))
    }

    // MARK: - 天气窗口

    /// 内容左边距（相对窗口；左边一段被发布说明窗口挡住）
    private static let mainInset: CGFloat = 148

    var weatherContentX: CGFloat { weather.minX + Self.mainInset }

    /// 第 index 块指标卡
    func tile(_ index: Int) -> CGRect {
        CGRect(x: weatherContentX + CGFloat(index) * 138, y: weather.minY + 92, width: 128, height: 60)
    }

    /// 七天预报柱状图的绘图区
    var chartPlot: CGRect {
        CGRect(x: weatherContentX, y: weather.minY + 180, width: 266, height: 156)
    }

    var lastBarIndex: Int { Self.forecastHighs.count - 1 }

    func barRect(_ index: Int) -> CGRect {
        let plot = chartPlot
        let slot = plot.width / CGFloat(Self.forecastHighs.count)
        let width = (slot * 0.5).rounded()
        let share = (Self.forecastHighs[index] - Self.chartFloor) / (Self.chartCeiling - Self.chartFloor)
        let height = plot.height * share
        let x = plot.minX + slot * CGFloat(index) + (slot - width) / 2
        return CGRect(x: x.rounded(), y: plot.maxY - height, width: width, height: height)
    }

    /// 文字标注的左上角：图表左上方的空白处（前几天的柱子较矮）
    var calloutOrigin: CGPoint {
        CGPoint(x: chartPlot.minX + 4, y: chartPlot.minY + 14)
    }
}

/// 展示画面用的单行文字（CoreText）：在左上原点、y 向下的上下文里按行框左上角绘制
enum ShowcaseText {
    static func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func lineHeight(size: CGFloat) -> CGFloat {
        let font = font(size: size, weight: .regular)
        return (font.ascender - font.descender).rounded(.up)
    }

    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, size: size, weight: weight, color: nil), nil, nil, nil))
    }

    /// topLeft：行框左上角；trailing 为 true 时 topLeft.x 是右端
    static func draw(
        _ text: String,
        at topLeft: CGPoint,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: CGColor,
        trailing: Bool = false,
        in context: CGContext
    ) {
        let line = line(text, size: size, weight: weight, color: color)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let baseline = topLeft.y + font(size: size, weight: weight).ascender
        context.saveGState()
        // 上下文是 y 向下的：文字矩阵再翻转一次，字形才是正的
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: trailing ? topLeft.x - width : topLeft.x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func line(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor?) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(size: size, weight: weight)]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
#endif
