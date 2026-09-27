#if DEBUG
import AppKit
import CubbyCore

/// 「打破常规」的交互脚本：箭头智能吸附、选区边缘磁吸、箭头端点手柄、⇧ 画笔直线、键盘选色 / 调粗细
extension E2EScenarios {
    /// 标准选区上最后一个标注（箭头）的两端
    private static func lastArrow(_ context: E2EContext) throws -> (from: CGPoint, to: CGPoint)? {
        guard case .arrow(let from, let to) = try context.lastAnnotation().shape else { return nil }
        return (from, to)
    }

    /// 画面上正在显示的辅助线 / 端点手柄（主屏）
    private static func canvas(_ context: E2EContext) -> OverlayCanvasView? {
        context.world.overlay?.debugScreenViews.first?.canvas
    }

    static var arrowMagnet: E2EScenario {
        E2EScenario(
            name: "arrow-magnet",
            summary: "an almost-horizontal arrow snaps to 0 degrees and shows a guide line until the mouse is released",
            steps: selectCanvas + [
                .letter("a"),
                .mouseDown(.at(1100, 300)),
                .mouseDrag(.at(1200, 302)),
                .mouseDrag(.at(1300, 304)),
                .expect("the live arrow snapped to horizontal") { context in
                    guard case .drawing(let annotation) = try context.requireSession().drag,
                        case .arrow(let from, let to) = annotation.shape
                    else { return false }
                    return from.y == to.y
                },
                .expect("the session exposes the snap guide") { try $0.requireSession().arrowSnapGuide != nil },
                .expect("the guide line is drawn on the canvas") { canvas($0)?.debugSnapGuideVisible == true },
                .mouseUp(.at(1300, 304)),
                .expect("the guide disappears after the mouse is released") { context in
                    try context.requireSession().arrowSnapGuide == nil
                        && canvas(context)?.debugSnapGuideVisible == false
                },
                .expectEqual("the committed arrow is horizontal", true) { context in
                    try lastArrow(context).map { $0.from.y == $0.to.y }
                },
                // 明显倾斜（约 11°）的箭头不吸附
                .drag([.at(1100, 450), .at(1300, 490)]),
                .expectEqual("a clearly slanted arrow is left alone", false) { context in
                    try lastArrow(context).map { $0.from.y == $0.to.y }
                },
                .key(.escape), .key(.escape),
                .expectIdle,
            ]
        )
    }

    /// Editor 窗口 (340, 200, 460 × 300) 的右边在 x = 800；从 (803, 450) 拖出的选区左边吸到 800，按住 ⌘ 时不吸
    static var selectionMagnet: E2EScenario {
        E2EScenario(
            name: "selection-magnet",
            summary: "selection edges snap to window edges within 6 pt; holding command turns snapping off",
            steps: [
                .start(at: desktop),
                .drag([.at(803, 450), .at(903, 600)]),
                .expectPhase(.adjusting),
                .expectSelection("the left edge snapped to the Editor window's right edge") {
                    $0.globalRect(CGRect(x: 800, y: 450, width: 103, height: 150))
                },
                // 缩放手柄：右下角拖到离 Preview 右边（x = 980）3 pt 处
                .drag([.handle(.bottomRight), .at(977, 640)]),
                .expectSelection("the dragged right edge snapped to the Preview window's right edge") {
                    $0.globalRect(CGRect(x: 800, y: 450, width: 180, height: 190))
                },
                .rightClick(.at(1500, 500)),
                .expectPhase(.hovering),
                .hold(.command),
                .drag([.at(803, 450), .at(903, 600)]),
                .releaseModifiers,
                .expectSelection("holding command keeps the exact drag") {
                    $0.globalRect(CGRect(x: 803, y: 450, width: 100, height: 150))
                },
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var arrowEndpoints: E2EScenario {
        E2EScenario(
            name: "arrow-endpoints",
            summary: "a selected arrow shows two end handles; dragging one re-points it as a single undo step",
            steps: selectCanvas + [
                .letter("a"),
                .drag([.at(1200, 300), .at(1400, 420)]),
                .letter("v"),
                .click(.at(1300, 360)),
                .expectEqual("clicking the arrow selects it", 2) {
                    try $0.requireSession().selectedArrowEndpoints.count
                },
                .expect("both end handles are drawn") { context in
                    let centers = canvas(context)?.debugArrowEndpointCenters ?? []
                    let wanted = [context.global(CGPoint(x: 1200, y: 300)), context.global(CGPoint(x: 1400, y: 420))]
                    return centers.count == 2
                        && zip(centers, wanted).allSatisfy { abs($0.x - $1.x) <= 1 && abs($0.y - $1.y) <= 1 }
                },
                .remember("document before") { context in
                    context.numbers["undo"] = try context.requireSession().document.annotations.count
                },
                .drag([.at(1400, 420), .at(1450, 500), .at(1500, 560)]),
                .expectEqual("dragging the head re-points the arrow", { $0.global(CGPoint(x: 1500, y: 560)) }) {
                    try lastArrow($0)?.to
                },
                .expectEqual("the tail stays put", { $0.global(CGPoint(x: 1200, y: 300)) }) { try lastArrow($0)?.from },
                .command("z"),
                .expectEqual("one undo restores the original head", { $0.global(CGPoint(x: 1400, y: 420)) }) {
                    try lastArrow($0)?.to
                },
                .key(.escape), .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var shiftLine: E2EScenario {
        E2EScenario(
            name: "shift-line",
            summary: "shift + pen / highlighter keeps only the first and last points (a straight line)",
            steps: selectCanvas + [
                .letter("p"),
                .hold(.shift),
                .drag([.at(1100, 300), .at(1150, 340), .at(1200, 260), .at(1300, 320)]),
                .releaseModifiers,
                .expectEqual("shift + pen stores two points", 2) { context in
                    guard case .pen(let points) = try context.lastAnnotation().shape else { return nil }
                    return points.count
                },
                .letter("h"),
                .hold(.shift),
                .drag([.at(1100, 450), .at(1180, 500), .at(1300, 450)]),
                .releaseModifiers,
                .expectEqual("shift + highlighter stores two points", 2) { context in
                    guard case .highlighter(let points) = try context.lastAnnotation().shape else { return nil }
                    return points.count
                },
                .letter("p"),
                .drag([.at(1400, 300), .at(1450, 340), .at(1500, 260), .at(1600, 320)]),
                .expect("without shift the pen keeps every point") { context in
                    guard case .pen(let points) = try context.lastAnnotation().shape else { return false }
                    return points.count > 2
                },
                .key(.escape), .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var styleKeys: E2EScenario {
        E2EScenario(
            name: "style-keys",
            summary: "digits 1-8 pick colors and [ ] change the weight; while editing text they are typed",
            steps: selectCanvas + [
                .letter("r"),
                .letter("5"),
                .letter("]"),
                .expectEqual("5 and ] set the rectangle style", AnnotationStyle(color: .blue, weight: .heavy)) {
                    try $0.requireSession().styles.style(for: .rectangle)
                },
                .drag([.at(1100, 200), .at(1250, 300)]),
                .expectEqual("the new rectangle uses it", AnnotationStyle(color: .blue, weight: .heavy)) {
                    try $0.lastAnnotation().style
                },
                // 选中标注时改的是这条标注
                .letter("v"),
                .click(.at(1100, 250)),
                .letter("1"),
                .letter("["),
                .expectEqual("keys restyle the selected rectangle", AnnotationStyle(color: .red, weight: .regular)) {
                    try $0.lastAnnotation().style
                },
                // 编辑文字时数字照常输入
                .letter("t"),
                .click(.at(1400, 500)),
                .expectPhase(.editingText),
                .type("5]"),
                .key(.escape),
                .expectEqual("digits and brackets are typed while editing", "5]") { context in
                    guard case .text(let text, _, _) = try context.lastAnnotation().shape else { return nil }
                    return text
                },
                .expectEqual("the text style did not change", ToolStyles.default.style(for: .text)) {
                    try $0.requireSession().styles.style(for: .text)
                },
                .key(.escape), .key(.escape),
                .expectIdle,
            ]
        )
    }
}
#endif
