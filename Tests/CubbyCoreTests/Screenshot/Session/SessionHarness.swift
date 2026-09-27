import CoreGraphics
@testable import CubbyCore

/// reducer 测试驱动：按顺序喂事件，记录最后一次与全部 effects
struct SessionHarness {
    let session: ScreenshotSession
    /// 最后一个事件产生的 effects
    let effects: [ScreenshotEffect]
    /// 迄今为止所有事件产生的 effects
    let allEffects: [ScreenshotEffect]
    let topology: ScreenTopology

    /// 标准选区 (200, 150, 560, 370)，与 `screenshot:adjusting` 场景一致
    static let selection = CGRect(x: 200, y: 150, width: 560, height: 370)

    init(
        session: ScreenshotSession,
        effects: [ScreenshotEffect] = [],
        allEffects: [ScreenshotEffect] = [],
        topology: ScreenTopology = TopologyFixture.twoScreens
    ) {
        self.session = session
        self.effects = effects
        self.allEffects = allEffects
        self.topology = topology
    }

    /// 悬停阶段起步，光标在桌面（无窗口）
    static func hovering(
        at cursor: CGPoint = TopologyFixture.desktopPoint,
        topology: ScreenTopology = TopologyFixture.twoScreens,
        styles: ToolStyles = .default
    ) -> SessionHarness {
        SessionHarness(
            session: .initial(styles: styles, cursor: cursor, topology: topology),
            topology: topology
        )
    }

    /// 通过拖拽得到标准选区的 adjusting 会话
    static func adjusting(topology: ScreenTopology = TopologyFixture.twoScreens) -> SessionHarness {
        hovering(topology: topology).drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 760, y: 520))
    }

    /// 标准选区 + 指定工具
    static func annotating(_ tool: ScreenshotTool) -> SessionHarness {
        adjusting().send(.command(.selectTool(tool)))
    }

    func send(_ events: ScreenshotEvent...) -> SessionHarness {
        send(events)
    }

    func send(_ events: [ScreenshotEvent]) -> SessionHarness {
        events.reduce(self) { harness, event in
            let result = ScreenshotReducer.reduce(harness.session, event: event, topology: harness.topology)
            return SessionHarness(
                session: result.session,
                effects: result.effects,
                allEffects: harness.allEffects + result.effects,
                topology: harness.topology
            )
        }
    }

    func click(_ point: CGPoint, count: Int = 1) -> SessionHarness {
        send(.mouseDown(point, clickCount: count), .mouseUp(point))
    }

    /// 按下 → 拖到每个中间点 → 在最后一点松开
    func drag(from start: CGPoint, to points: CGPoint...) -> SessionHarness {
        let moves = points.map { ScreenshotEvent.mouseDragged($0) }
        return send([.mouseDown(start, clickCount: 1)] + moves + [.mouseUp(points.last ?? start)])
    }

    /// 按下并拖动但不松开
    func press(_ start: CGPoint, dragTo points: CGPoint...) -> SessionHarness {
        send([.mouseDown(start, clickCount: 1)] + points.map { ScreenshotEvent.mouseDragged($0) })
    }

    func modifiers(_ modifiers: KeyModifiers) -> SessionHarness {
        send(.modifiersChanged(modifiers))
    }

    /// 在选区内画一个矩形标注（会切换到矩形工具再回到原工具）
    func drawingRectangle(_ rect: CGRect) -> SessionHarness {
        let tool = session.tool
        let drawn = send(.command(.selectTool(.rectangle)))
            .drag(from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
        let restore: [ScreenshotEvent] =
            tool == .rectangle ? [] : [.command(.selectTool(tool == .pointer ? .rectangle : tool))]
        return drawn.send(restore)
    }
}
