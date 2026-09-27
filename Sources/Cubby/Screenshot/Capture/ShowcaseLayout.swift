#if DEBUG
import AppKit
import CubbyCore

/// README 展示场景（`--scenario screenshot:showcase`）的文案：界面语言为简体中文时用中文，否则英文。
/// 汉字一律写成 Unicode 转义（源码中不出现汉字字面量），上一行注释给出原文
struct ShowcaseCopy: Sendable {
    struct KPI: Sendable {
        let label: String
        let value: String
        let delta: String
    }

    let notesTitle: String
    let heading: String
    let subtitle: String
    let whatsNew: String
    let bullets: [String]
    let feedback: String
    let contactPrefix: String
    /// 虚构的邮箱（example.com 是保留域名），展示马赛克的遮挡效果
    let email: String
    let dashboardTitle: String
    let chartTitle: String
    let chartSubtitle: String
    let kpis: [KPI]
    /// 文字标注
    let callout: String

    static var current: ShowcaseCopy {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    static let english = ShowcaseCopy(
        notesTitle: "Release Notes.md",
        heading: "Cubby 0.2",
        subtitle: "Release notes \u{B7} September 2026",
        whatsNew: "What\u{2019}s new",
        bullets: [
            "Mark up screenshots with \u{21E7}\u{2318}2",
            "Search images by the text in them",
            "Pin any image to the screen",
            "Liquid Glass on macOS 26",
        ],
        feedback: "Feedback",
        contactPrefix: "Questions? Write to ",
        email: "jamie.chen@example.com",
        dashboardTitle: "Downloads \u{2014} Dashboard",
        chartTitle: "Weekly downloads",
        chartSubtitle: "Last 12 weeks",
        kpis: [
            KPI(label: "Downloads", value: "12.4k", delta: "\u{25B2} 18%"),
            KPI(label: "GitHub stars", value: "3,214", delta: "\u{25B2} 9%"),
        ],
        callout: "Ship it!"
    )

    static let chinese = ShowcaseCopy(
        // 发布说明.md
        notesTitle: "\u{53D1}\u{5E03}\u{8BF4}\u{660E}.md",
        heading: "Cubby 0.2",
        // 发布说明 · 2026 年 9 月
        subtitle: "\u{53D1}\u{5E03}\u{8BF4}\u{660E} \u{B7} 2026 \u{5E74} 9 \u{6708}",
        // 新功能
        whatsNew: "\u{65B0}\u{529F}\u{80FD}",
        bullets: [
            // 截图后直接标注：⇧⌘2
            "\u{622A}\u{56FE}\u{540E}\u{76F4}\u{63A5}\u{6807}\u{6CE8}\u{FF1A}\u{21E7}\u{2318}2",
            // 按图中的文字搜索图片
            "\u{6309}\u{56FE}\u{4E2D}\u{7684}\u{6587}\u{5B57}\u{641C}\u{7D22}\u{56FE}\u{7247}",
            // 把任意图片贴到屏幕上
            "\u{628A}\u{4EFB}\u{610F}\u{56FE}\u{7247}\u{8D34}\u{5230}\u{5C4F}\u{5E55}\u{4E0A}",
            // macOS 26 上的 Liquid Glass
            "macOS 26 \u{4E0A}\u{7684} Liquid Glass",
        ],
        // 反馈
        feedback: "\u{53CD}\u{9988}",
        // 有问题？请写信到
        contactPrefix: "\u{6709}\u{95EE}\u{9898}\u{FF1F}\u{8BF7}\u{5199}\u{4FE1}\u{5230} ",
        email: "jamie.chen@example.com",
        // 下载量 — 仪表盘
        dashboardTitle: "\u{4E0B}\u{8F7D}\u{91CF} \u{2014} \u{4EEA}\u{8868}\u{76D8}",
        // 每周下载量
        chartTitle: "\u{6BCF}\u{5468}\u{4E0B}\u{8F7D}\u{91CF}",
        // 近 12 周
        chartSubtitle: "\u{8FD1} 12 \u{5468}",
        kpis: [
            // 下载量
            KPI(label: "\u{4E0B}\u{8F7D}\u{91CF}", value: "12.4k", delta: "\u{25B2} 18%"),
            // GitHub 星标
            KPI(label: "GitHub \u{661F}\u{6807}", value: "3,214", delta: "\u{25B2} 9%"),
        ],
        // 就是这里！
        callout: "\u{5C31}\u{662F}\u{8FD9}\u{91CC}\u{FF01}"
    )
}

/// 展示场景的几何（全局点，左上原点）：一块 880 × 640 的「场景」放在第一块屏幕中央，
/// 里面是前面的发布说明窗口、后面的下载量仪表盘和一个预置选区。画面与预置标注共用这里的坐标
struct ShowcaseLayout {
    static let sceneSize = CGSize(width: 880, height: 640)
    static let notesID: UInt32 = 9201
    static let dashboardID: UInt32 = 9202
    static let titleBarHeight: CGFloat = 28
    /// 近 12 周下载量（千次）
    static let chartValues: [CGFloat] = [3.2, 3.9, 3.5, 4.6, 5.1, 4.8, 6.2, 7.0, 6.6, 8.4, 9.9, 12.4]
    static let chartMaximum: CGFloat = 14

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
    var dashboard: CGRect { rect(336, 92, 440, 372) }

    /// 窗口列表（前 → 后）；进程号是假的，不能与 Cubby 自身相同，否则悬停识别会排除它们
    var candidates: [WindowCandidate] {
        [(Self.notesID, notes), (Self.dashboardID, dashboard)].map { id, frame in
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

    // MARK: - 仪表盘

    /// 内容左边距（相对窗口；左边一段被发布说明窗口挡住）
    private static let mainInset: CGFloat = 148

    var dashboardContentX: CGFloat { dashboard.minX + Self.mainInset }

    func kpiTile(_ index: Int) -> CGRect {
        CGRect(
            x: dashboardContentX + CGFloat(index) * 138, y: dashboard.minY + 92, width: 128, height: 60)
    }

    /// 柱状图绘图区
    var chartPlot: CGRect {
        CGRect(x: dashboardContentX, y: dashboard.minY + 180, width: 266, height: 156)
    }

    func barRect(_ index: Int) -> CGRect {
        let plot = chartPlot
        let slot = plot.width / CGFloat(Self.chartValues.count)
        let width = (slot * 0.58).rounded()
        let height = plot.height * Self.chartValues[index] / Self.chartMaximum
        let x = plot.minX + slot * CGFloat(index) + (slot - width) / 2
        return CGRect(x: x.rounded(), y: plot.maxY - height, width: width, height: height)
    }

    /// 文字标注的左上角：图表左上方的空白处
    var calloutOrigin: CGPoint {
        CGPoint(x: chartPlot.minX + 4, y: chartPlot.minY + 30)
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
