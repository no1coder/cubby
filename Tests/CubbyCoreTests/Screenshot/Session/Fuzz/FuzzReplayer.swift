import CoreGraphics
@testable import CubbyCore

/// 一条序列的起点：初始会话（光标位置）或某个调试场景的预置会话
enum FuzzStart: Equatable, Sendable {
    case initial(cursor: CGPoint)
    case scenario(String)

    /// 可作为起点的调试场景（覆盖 selecting、annotating、editingText、窗口模式等深层状态）
    static let scenarioNames: [String] =
        ScreenshotDebugScenario.names + ScreenshotTool.allCases.map { "annotating:\($0.rawValue)" }

    /// 截图翻译一律可用（不可用时翻译事件全是空操作，由单元测试覆盖）
    func session(in topology: ScreenTopology) -> ScreenshotSession {
        let styles = Self.isolatedDefaultStyles()
        let session: ScreenshotSession
        switch self {
        case .initial(let cursor):
            session = ScreenshotSession.initial(styles: styles, cursor: cursor, topology: topology)
        case .scenario(let name):
            session =
                ScreenshotDebugScenario.session(named: name, topology: topology, styles: styles)
                ?? ScreenshotSession.initial(styles: styles, cursor: .zero, topology: topology)
        }
        return session.settingTranslationAvailable(true)
    }

    /// 与 `ToolStyles.default` 相等、但字典存储独立的副本（理由同 `FuzzTopologies.isolated`）
    private static func isolatedDefaultStyles() -> ToolStyles {
        let defaults = ToolStyles.default
        return defaults.setting(defaults.style(for: .pointer), for: .pointer)
    }
}

/// 一条可复现的事件序列
struct FuzzTrace: Sendable {
    let topologyIndex: Int
    let start: FuzzStart
    let events: [ScreenshotEvent]

    var topology: ScreenTopology {
        FuzzTopologies.isolated(topologyIndex)
    }

    func with(events: [ScreenshotEvent]) -> FuzzTrace {
        FuzzTrace(topologyIndex: topologyIndex, start: start, events: events)
    }
}

/// 逐个送入事件并检查不变量；出现 `.finish` 后该会话视为结束，不再给它送事件，而是从同一起点开始新会话
struct FuzzReplayer {
    let topology: ScreenTopology
    let start: FuzzStart
    private(set) var session: ScreenshotSession
    /// 最近一次 `.modifiersChanged` 发来的修饰键
    private var modifiers: KeyModifiers
    /// 物理上的左键状态：用于统计「不可能出现的」事件（孤立的松开 / 拖动等）
    private var buttonDown: Bool
    private(set) var nonPhysicalEvents = 0
    private(set) var finishedSessions = 0
    /// 当前会话已处理的事件数
    private var sessionSteps = 0
    /// 要检查的不变量（默认全部）
    let invariants: [ReducerInvariant]

    init(topology: ScreenTopology, start: FuzzStart, invariants: [ReducerInvariant] = ReducerInvariant.allCases) {
        self.topology = topology
        self.start = start
        self.invariants = invariants
        let session = start.session(in: topology)
        self.session = session
        modifiers = session.modifiers
        buttonDown = session.press != nil
    }

    /// 送入一个事件；返回这一步的上下文与第一个违反的不变量
    mutating func apply(_ event: ScreenshotEvent) -> (step: FuzzStep, violation: InvariantViolation?) {
        trackPhysical(event)
        let previous = session
        let result = ScreenshotReducer.reduce(previous, event: event, topology: topology)
        if case .modifiersChanged(let sent) = event {
            modifiers = sent
        }
        let step = FuzzStep(
            previous: previous,
            event: event,
            session: result.session,
            effects: result.effects,
            topology: topology,
            expectedModifiers: modifiers,
            isFirstStep: sessionSteps == 0
        )
        sessionSteps += 1
        let violation = ReducerInvariant.firstViolation(in: step, checking: invariants)
        if step.finished {
            restart()
        } else {
            session = result.session
        }
        return (step, violation)
    }

    /// 会话结束：从同一起点开始新会话，物理状态一并复位
    mutating func restart() {
        finishedSessions += 1
        sessionSteps = 0
        session = start.session(in: topology)
        modifiers = session.modifiers
        buttonDown = session.press != nil
    }

    private mutating func trackPhysical(_ event: ScreenshotEvent) {
        switch event {
        case .mouseDown:
            nonPhysicalEvents += buttonDown ? 1 : 0
            buttonDown = true
        case .mouseUp:
            nonPhysicalEvents += buttonDown ? 0 : 1
            buttonDown = false
        case .mouseDragged:
            nonPhysicalEvents += buttonDown ? 0 : 1
        case .mouseMoved:
            nonPhysicalEvents += buttonDown ? 1 : 0
        default:
            break
        }
    }

    /// 重放整条序列：返回第一个违反及其所在下标
    static func firstViolation(in trace: FuzzTrace) -> (index: Int, violation: InvariantViolation, nonPhysical: Int)? {
        var replayer = FuzzReplayer(topology: trace.topology, start: trace.start)
        for (index, event) in trace.events.enumerated() {
            if let violation = replayer.apply(event).violation {
                return (index, violation, replayer.nonPhysicalEvents)
            }
        }
        return nil
    }
}
