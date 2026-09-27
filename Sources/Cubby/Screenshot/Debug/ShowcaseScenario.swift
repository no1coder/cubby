#if DEBUG
import AppKit
import CubbyCore

/// README 截图的展示场景：`Cubby --scenario screenshot:showcase`（仅调试构建）。
///
/// 冻结帧是 ShowcaseFrameSource 合成的桌面；预置会话由公开的 ScreenshotReducer 逐个事件回放得到
/// （拖出选区 → 荧光笔 → 马赛克 → 矩形 → 序号 1–3 → 文字 → 箭头），最后停在箭头工具上，
/// 工具栏与样式条都可见。样式固定为默认值，不读写用户的标注样式设置
extension ScreenshotCoordinator {
    func startShowcase() {
        let source = ShowcaseFrameSource(screens: ScreenTopologyProvider.screens(), copy: .current)
        begin(frameSource: source, windowSource: source) { [logger] capture in
            let session = ShowcaseSession.make(topology: capture.topology, copy: source.copy)
            if session == nil {
                logger.error("Showcase scenario needs a screen")
            }
            return session
        }
    }
}

/// 展示场景的预置会话
enum ShowcaseSession {
    /// 序号标注的个数
    private static let numberCount = 3

    static func make(topology: ScreenTopology, copy: ShowcaseCopy) -> ScreenshotSession? {
        guard let screen = topology.screens.first else { return nil }
        let layout = ShowcaseLayout(screen: screen)
        let selection = layout.selection
        let start = CGPoint(x: selection.minX, y: selection.minY)
        let initial = ScreenshotSession.initial(styles: .default, cursor: start, topology: topology)
        let events =
            select(selection)
            + highlight(layout, copy: copy)
            + mosaic(layout, copy: copy)
            + rectangle(layout)
            + numbers(layout, copy: copy)
            + callout(layout, copy: copy)
            + arrow(layout, copy: copy)
        return events.reduce(initial) { ScreenshotReducer.reduce($0, event: $1, topology: topology).session }
    }

    // MARK: - 事件序列

    /// 从左上角拖到右下角
    private static func select(_ rect: CGRect) -> [ScreenshotEvent] {
        stroke([
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ])
    }

    /// 荧光笔划过第二条要点
    private static func highlight(_ layout: ShowcaseLayout, copy: ShowcaseCopy) -> [ScreenshotEvent] {
        let line = layout.bulletLine(1, copy: copy)
        return tool(.highlighter) + stroke(points(from: line.minX - 2, to: line.maxX + 2, y: line.midY))
    }

    /// 马赛克盖住虚构的邮箱
    private static func mosaic(_ layout: ShowcaseLayout, copy: ShowcaseCopy) -> [ScreenshotEvent] {
        // 圆头笔刷两端会向外多盖半个笔刷：起点收进来，免得盖到前面的文字；
        // 略低于行中线，把 j、g 这类下伸部分也盖住
        let email = layout.emailLine(copy: copy)
        return tool(.mosaic) + stroke(points(from: email.minX + 8, to: email.maxX - 8, y: email.midY + 1.5))
    }

    /// 橙色矩形框住「下载量」指标卡
    private static func rectangle(_ layout: ShowcaseLayout) -> [ScreenshotEvent] {
        let tile = layout.kpiTile(0).insetBy(dx: -5, dy: -5)
        return tool(.rectangle) + [.command(.selectColor(.orange))]
            + stroke([
                CGPoint(x: tile.minX, y: tile.minY), CGPoint(x: tile.midX, y: tile.midY),
                CGPoint(x: tile.maxX, y: tile.maxY),
            ])
    }

    /// 前三条要点左侧的序号 1–3
    private static func numbers(_ layout: ShowcaseLayout, copy: ShowcaseCopy) -> [ScreenshotEvent] {
        tool(.number)
            + (0..<numberCount).flatMap { index -> [ScreenshotEvent] in
                let center = layout.numberCenter(index, copy: copy)
                return [.mouseDown(center, clickCount: 1), .mouseUp(center)]
            }
    }

    /// 大号文字标注：按下打开编辑器，再直接提交文字
    private static func callout(_ layout: ShowcaseLayout, copy: ShowcaseCopy) -> [ScreenshotEvent] {
        let origin = layout.calloutOrigin
        return tool(.text) + [
            .command(.adjustWeight(heavier: true)),
            .mouseDown(origin, clickCount: 1),
            .textChanged(copy.callout),
            .textCommitted(copy.callout),
        ]
    }

    /// 箭头从文字右侧指向最后一周（最高）的柱子；画完仍停在箭头工具上
    private static func arrow(_ layout: ShowcaseLayout, copy: ShowcaseCopy) -> [ScreenshotEvent] {
        // 与 callout 中加粗一档后的字号一致（regular → heavy）
        let fontSize = ScreenshotTool.text.fontSize(for: .heavy)
        let textSize = TextLayout.size(of: copy.callout, fontSize: fontSize, maxWidth: .infinity)
        let origin = layout.calloutOrigin
        let tail = CGPoint(x: origin.x + textSize.width + 8, y: origin.y + textSize.height * 0.55)
        let bar = layout.barRect(ShowcaseLayout.chartValues.count - 1)
        let head = CGPoint(x: bar.minX - 5, y: bar.minY + 3)
        let middle = CGPoint(x: (tail.x + head.x) / 2, y: (tail.y + head.y) / 2)
        return tool(.arrow) + stroke([tail, middle, head])
    }

    // MARK: - 辅助

    private static func tool(_ tool: ScreenshotTool) -> [ScreenshotEvent] {
        [.command(.selectTool(tool))]
    }

    /// 按下 → 依次拖过其余各点 → 在最后一点松开
    private static func stroke(_ points: [CGPoint]) -> [ScreenshotEvent] {
        guard let first = points.first, let last = points.last else { return [] }
        return [.mouseDown(first, clickCount: 1)] + points.dropFirst().map { .mouseDragged($0) } + [.mouseUp(last)]
    }

    /// 水平线段上的 5 个点
    private static func points(from startX: CGFloat, to endX: CGFloat, y: CGFloat) -> [CGPoint] {
        (0...4).map { step in CGPoint(x: startX + (endX - startX) * CGFloat(step) / 4, y: y) }
    }
}
#endif
