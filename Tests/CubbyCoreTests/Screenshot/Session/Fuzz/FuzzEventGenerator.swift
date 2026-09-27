import CoreGraphics
@testable import CubbyCore

/// 生成器眼中的物理输入状态：保证绝大多数序列在真实硬件上可能出现
/// （左键按下 / 松开交替、按住时只有拖动、修饰键逐个变化）
struct FuzzInputState {
    var buttonDown: Bool
    var modifiers: KeyModifiers = []
    /// 已计划、尚未发出的组合动作（单击、双击、空格单击）
    var queue: [ScreenshotEvent] = []

    init(session: ScreenshotSession) {
        buttonDown = session.press != nil
        modifiers = session.modifiers
    }

    mutating func record(_ event: ScreenshotEvent) {
        switch event {
        case .mouseDown: buttonDown = true
        case .mouseUp: buttonDown = false
        case .modifiersChanged(let modifiers): self.modifiers = modifiers
        default: break
        }
    }
}

/// 按阶段加权生成事件：覆盖全部 `ScreenshotEvent`、全部 `ScreenshotCommand` 与全部 `ScreenshotOutcome`
enum FuzzEventGenerator {
    /// 无视物理状态的「杂乱事件」比例（孤立的松开 / 拖动、按住时的点击等）
    private static let chaosRate: CGFloat = 0.03

    private enum Action {
        case move
        case press
        case click
        case doubleClick
        case spaceTap
        case modifiers
        case command
        case scroll
        case rightClick
        case style
        case textChanged
        case textCommitted
        case toolbar
        /// 组合：单击箭头中点选中它，再按住一端拖动（重新指向）
        case arrowEndDrag
        /// 截图翻译：用户操作与流水线回报
        case translation
    }

    /// 文本池：空白、换行、表情、组合字符、从右到左文字、汉字（转义）、超长文本。
    /// 每次现建而不是 static let，理由同 FuzzPoints 的候选表
    static var texts: [String] {
        [
            "", " ", "\n", " \t\n ", "a", "Hi", "Hello world", "trailing   ", "line1\nline2\n\n", "\u{4F60}\u{597D}",
            "\u{1F600}\u{1F44D}", "e\u{0301}", "\u{05E9}\u{05DC}\u{05D5}\u{05DD}",
            String(repeating: "wide ", count: 60),
            "tab\tsep", "\u{00A0}", "\u{3000}", "x\u{200B}",
        ]
    }

    static func next(
        _ rng: inout FuzzRandom,
        session: ScreenshotSession,
        input: inout FuzzInputState,
        topology: ScreenTopology
    ) -> ScreenshotEvent {
        let event: ScreenshotEvent
        if !input.queue.isEmpty {
            event = input.queue.removeFirst()
        } else if rng.chance(chaosRate) {
            event = chaos(&rng, session: session, topology: topology)
        } else if input.buttonDown {
            event = whilePressed(&rng, session: session, input: input, topology: topology)
        } else {
            event = whileReleased(&rng, session: session, input: &input, topology: topology)
        }
        input.record(event)
        return event
    }

    // MARK: - 左键按住

    private static func whilePressed(
        _ rng: inout FuzzRandom,
        session: ScreenshotSession,
        input: FuzzInputState,
        topology: ScreenTopology
    ) -> ScreenshotEvent {
        switch rng.int(below: 100) {
        case 0..<60:
            return .mouseDragged(FuzzPoints.dragStep(&rng, from: session.cursor, session: session, topology: topology))
        case 60..<78:
            let point =
                rng.chance(0.7)
                ? session.cursor : FuzzPoints.dragStep(&rng, from: session.cursor, session: session, topology: topology)
            return .mouseUp(point)
        case 78..<86:
            let key: KeyModifiers = rng.weighted([(5, .shift), (3, .option), (4, .space), (1, .command)])
            return .modifiersChanged(input.modifiers.symmetricDifference(key))
        case 86..<88:
            return .command(.escape)
        case 88..<90:
            return .rightMouseDown(session.cursor)
        case 90..<92:
            return .scrolled(deltaY: scrollDelta(&rng))
        case 92..<98:
            return .command(
                rng.pick([
                    .undo, .redo, .deleteAnnotation, .selectAll, .confirm, .cycleHover(forward: true),
                    .nudge(.left, large: false), .selectTool(tool(&rng)), .selectColor(.green),
                    .adjustWeight(heavier: false),
                ]))
        default:
            return .textChanged(rng.pick(texts))
        }
    }

    // MARK: - 左键松开

    private static func whileReleased(
        _ rng: inout FuzzRandom,
        session: ScreenshotSession,
        input: inout FuzzInputState,
        topology: ScreenTopology
    ) -> ScreenshotEvent {
        let action = rng.weighted(actionWeights(session.phase))
        let point = FuzzPoints.interesting(&rng, session: session, topology: topology)
        switch action {
        case .move:
            let target =
                rng.chance(0.4)
                ? FuzzPoints.dragStep(&rng, from: session.cursor, session: session, topology: topology) : point
            return .mouseMoved(target)
        case .press:
            return .mouseDown(point, clickCount: rng.chance(0.05) ? 2 : 1)
        case .click:
            let release = CGPoint(x: point.x + rng.value(in: -1.5, 1.5), y: point.y + rng.value(in: -1.5, 1.5))
            input.queue = [.mouseUp(release)]
            return .mouseDown(point, clickCount: 1)
        case .doubleClick:
            input.queue = [.mouseUp(point), .mouseDown(point, clickCount: 2), .mouseUp(point)]
            return .mouseDown(point, clickCount: 1)
        case .spaceTap:
            let held = input.modifiers.subtracting(.space)
            input.queue = [.modifiersChanged(held)]
            return .modifiersChanged(held.union(.space))
        case .modifiers:
            return .modifiersChanged(toggledModifiers(&rng, input.modifiers))
        case .command:
            return .command(command(&rng, phase: session.phase, topology: topology))
        case .scroll:
            return .scrolled(deltaY: scrollDelta(&rng))
        case .rightClick:
            return .rightMouseDown(point)
        case .style:
            return .styleChanged(style(&rng))
        case .textChanged:
            return .textChanged(rng.pick(texts))
        case .textCommitted:
            return .textCommitted(rng.chance(0.2) ? nil : rng.pick(texts))
        case .toolbar:
            return .toolbarAction(outcome(&rng, topology: topology))
        case .arrowEndDrag:
            return arrowEndDrag(&rng, session: session, input: &input, topology: topology)
        case .translation:
            return FuzzTranslation.event(&rng, session: session)
        }
    }

    /// 选中文档里的某支箭头并拖它的一端；没有箭头时退化为一次普通移动
    private static func arrowEndDrag(
        _ rng: inout FuzzRandom,
        session: ScreenshotSession,
        input: inout FuzzInputState,
        topology: ScreenTopology
    ) -> ScreenshotEvent {
        let arrows = session.document.annotations.compactMap { annotation -> (CGPoint, CGPoint)? in
            guard case .arrow(let from, let to) = annotation.shape else { return nil }
            return (from, to)
        }
        guard !arrows.isEmpty else { return .mouseMoved(session.cursor) }
        let (from, to) = rng.pick(arrows)
        let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let end = rng.chance(0.5) ? from : to
        let first = FuzzPoints.dragStep(&rng, from: end, session: session, topology: topology)
        let second = FuzzPoints.dragStep(&rng, from: first, session: session, topology: topology)
        input.queue = [
            .mouseUp(middle), .mouseDown(end, clickCount: 1), .mouseDragged(first), .mouseDragged(second),
            .mouseUp(second),
        ]
        return .mouseDown(middle, clickCount: 1)
    }

    /// 各阶段的动作权重：让序列能走到画标注、编辑文字、拖标注、拉手柄、逐层切换、窗口模式等深层状态
    private static func actionWeights(_ phase: ScreenshotPhase) -> [(Int, Action)] {
        // 依次为 hovering / selecting / adjusting / annotating / editingText
        let table: [(Action, [Int])] = [
            (.move, [22, 10, 8, 8, 4]),
            (.press, [16, 10, 22, 30, 6]),
            (.click, [10, 5, 7, 11, 4]),
            (.doubleClick, [1, 1, 1, 1, 1]),
            (.spaceTap, [10, 2, 1, 1, 1]),
            (.modifiers, [5, 5, 5, 6, 3]),
            (.command, [16, 20, 44, 36, 22]),
            (.scroll, [9, 2, 1, 1, 1]),
            (.rightClick, [1, 2, 2, 2, 2]),
            (.style, [1, 1, 5, 6, 5]),
            (.textChanged, [1, 1, 1, 1, 30]),
            (.textCommitted, [1, 1, 1, 1, 8]),
            (.toolbar, [2, 2, 2, 2, 3]),
            (.arrowEndDrag, [0, 0, 3, 2, 0]),
            (.translation, [3, 1, 14, 10, 3]),
        ]
        let column: Int
        switch phase {
        case .hovering: column = 0
        case .selecting: column = 1
        case .adjusting: column = 2
        case .annotating: column = 3
        case .editingText: column = 4
        }
        return table.map { ($0.1[column], $0.0) }
    }

    // MARK: - 命令、样式、出口

    private static func command(
        _ rng: inout FuzzRandom,
        phase: ScreenshotPhase,
        topology: ScreenTopology
    ) -> ScreenshotCommand {
        let finishing: ScreenshotCommand = rng.pick([.confirm, .save, .pin, .extractText])
        let nudge = ScreenshotCommand.nudge(rng.pick([.up, .down, .left, .right]), large: rng.chance(0.3))
        let rows: [(ScreenshotCommand, [Int])] = [
            // 依次为 hovering / selecting / adjusting / annotating / editingText
            (.cycleHover(forward: rng.chance(0.6)), [30, 2, 1, 1, 1]),
            (.selectColor(rng.pick(AnnotationColor.allCases)), [1, 1, 6, 6, 2]),
            (.adjustWeight(heavier: rng.chance(0.5)), [1, 1, 5, 5, 2]),
            (.selectTool(tool(&rng)), [4, 4, 30, 28, 10]),
            (nudge, [2, 2, 15, 10, 3]),
            (.undo, [3, 2, 10, 12, 6]),
            (.redo, [2, 2, 7, 8, 3]),
            (.deleteAnnotation, [1, 1, 7, 6, 3]),
            (.selectAll, [6, 4, 4, 3, 3]),
            (.escape, [3, 20, 3, 3, 25]),
            (.commitText, [1, 1, 1, 1, 20]),
            (.copyColor, [1, 1, 1, 1, 1]),
            (.translate, [1, 1, 3, 3, 2]),
            (finishing, [2, 2, 2, 2, 2]),
        ]
        let column: Int
        switch phase {
        case .hovering: column = 0
        case .selecting: column = 1
        case .adjusting: column = 2
        case .annotating: column = 3
        case .editingText: column = 4
        }
        return rng.weighted(rows.map { ($0.1[column], $0.0) })
    }

    static func tool(_ rng: inout FuzzRandom) -> ScreenshotTool {
        rng.weighted([
            (10, .pointer), (12, .rectangle), (8, .ellipse), (10, .arrow), (12, .pen), (6, .highlighter),
            (6, .mosaic), (18, .text), (14, .number),
        ])
    }

    static func style(_ rng: inout FuzzRandom) -> AnnotationStyle {
        AnnotationStyle(color: rng.pick(AnnotationColor.allCases), weight: rng.pick(StrokeWeight.allCases))
    }

    static func outcome(_ rng: inout FuzzRandom, topology: ScreenTopology) -> ScreenshotOutcome {
        let windowID = topology.windows.isEmpty ? 999 : rng.pick(topology.windows).id
        return rng.weighted([
            (2, .copy), (1, .save), (1, .pin), (1, .extractText),
            (3, .copyColor(rng.pick(["#FF8800", "255, 136, 0", ""]))),
            (3, .captureWindow(windowID: windowID, includeShadow: rng.chance(0.5))),
            (1, .cancel),
        ])
    }

    static func scrollDelta(_ rng: inout FuzzRandom) -> CGFloat {
        if rng.chance(0.2) {
            return rng.value(in: -60, 60)
        }
        return rng.pick([0, 1, -1, 0.5, -0.5, 10, -10, 39.5, -39.5, 40, -40, 40.5, -40.5, 120, -120, 1000, -1000])
    }

    private static func toggledModifiers(_ rng: inout FuzzRandom, _ current: KeyModifiers) -> KeyModifiers {
        switch rng.int(below: 20) {
        case 0: return []
        case 1: return KeyModifiers(rawValue: UInt8(rng.int(below: 16)))
        default:
            let key: KeyModifiers = rng.weighted([(6, .shift), (4, .option), (2, .command), (8, .space)])
            return current.symmetricDifference(key)
        }
    }

    // MARK: - 杂乱事件

    /// 不受物理状态约束的任意事件：孤立的松开 / 拖动、按住时再按下、远处坐标、异常的点击次数
    private static func chaos(
        _ rng: inout FuzzRandom,
        session: ScreenshotSession,
        topology: ScreenTopology
    ) -> ScreenshotEvent {
        let point = FuzzPoints.interesting(&rng, session: session, topology: topology)
        switch rng.int(below: 12) {
        case 0: return .mouseMoved(point)
        case 1: return .mouseDown(point, clickCount: rng.pick([0, 1, 2, 3, 7]))
        case 2: return .mouseDragged(point)
        case 3: return .mouseUp(point)
        case 4: return .rightMouseDown(point)
        case 5: return .modifiersChanged(KeyModifiers(rawValue: UInt8(rng.int(below: 16))))
        case 6:
            let phase: ScreenshotPhase = rng.pick([.hovering, .adjusting, .editingText])
            return .command(command(&rng, phase: phase, topology: topology))
        case 7: return .styleChanged(style(&rng))
        case 8: return .textChanged(rng.pick(texts))
        case 9: return .textCommitted(rng.chance(0.3) ? nil : rng.pick(texts))
        case 10: return .toolbarAction(outcome(&rng, topology: topology))
        default: return .scrolled(deltaY: scrollDelta(&rng))
        }
    }
}
