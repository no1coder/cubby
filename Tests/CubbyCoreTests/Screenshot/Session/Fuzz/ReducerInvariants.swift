import CoreGraphics
@testable import CubbyCore

/// 一次 reduce 的输入与输出，供不变量检查
struct FuzzStep {
    let previous: ScreenshotSession
    let event: ScreenshotEvent
    let session: ScreenshotSession
    let effects: [ScreenshotEffect]
    let topology: ScreenTopology
    /// 最近一次 `.modifiersChanged` 发来的修饰键（会话开始时为空）
    let expectedModifiers: KeyModifiers
    /// 文档是否需要重新检查：本步改了文档，或这是会话的第一步（起点文档也要查一次）。
    /// 文档没变时只依赖文档的不变量结果与上一步相同，跳过它们以节省时间（Array 的 == 对同一存储是 O(1)）
    let documentChanged: Bool

    init(
        previous: ScreenshotSession,
        event: ScreenshotEvent,
        session: ScreenshotSession,
        effects: [ScreenshotEffect],
        topology: ScreenTopology,
        expectedModifiers: KeyModifiers,
        isFirstStep: Bool
    ) {
        self.previous = previous
        self.event = event
        self.session = session
        self.effects = effects
        self.topology = topology
        self.expectedModifiers = expectedModifiers
        documentChanged = isFirstStep || previous.document != session.document
    }

    var finished: Bool {
        effects.contains { if case .finish = $0 { true } else { false } }
    }
}

/// 违反的不变量与说明
struct InvariantViolation: Equatable, Sendable {
    let invariant: ReducerInvariant
    let detail: String
}

/// 每一步之后都要成立的性质（依据设计文档 §2 / §3.2 / §3.3.10 / §9 归纳）
///
/// 顺序即检查顺序：先查会让后续检查失真的问题（非有限值、非纯函数）。
enum ReducerInvariant: String, CaseIterable, Sendable {
    /// 光标、选区、标注、正在画的标注、文字编辑器的坐标都是有限值
    case finiteGeometry
    /// reduce 是纯函数：同样的输入两次调用结果完全相同
    case purity
    /// 一次 reduce 最多一个 `.finish`，且它是最后一个 effect
    case finishOnce
    /// 出口需要的前提：复制 / 保存 / 贴图 / OCR 有选区且文字已提交；取色时放大镜可见；窗口截取在窗口模式下
    case finishContext
    /// Esc 与右键的语义（§2.3 / §2.11 / §9.1 二次确认）
    case escapeAndRightClick
    /// 选区在 screenID 那块屏幕内、≥ minSize（selecting 除外）、对齐到该屏像素网格
    case selectionGeometry
    /// selection 与 screenID 同时为 nil 或同时非 nil
    case selectionScreenPairing
    /// phase 与 tool / selection / drag / textEditing / hover / selectedAnnotation 一致
    case phaseConsistency
    /// 窗口模式只在 hovering；只能在窗口目标上进入；切到整屏时退出；隐藏放大镜
    case windowCaptureMode
    /// hoverDepth 在候选栈范围内，hover = candidates[hoverDepth]，离开 hovering 后清零
    case hoverDepth
    /// selectedAnnotation 指向文档中存在的标注
    case selectedAnnotation
    /// 序号按文档顺序连续编号 1…n，新放置的序号编号 = 放置前的 nextNumber
    case numbering
    /// 文档内标注 id 唯一，正在画的标注不在文档中
    case uniqueIDs
    /// 撤销 / 重做可逆（文档层面与 reducer 层面）
    case undoRedo
    /// 待确认放弃时文档非空；只由 Esc / hovering 右键进入；其他事件先解除
    case discardArmed
    /// drag 非 none 时鼠标必须处于按下状态（press 非 nil）
    case dragNeedsPress
    /// 「单独按空格」只在 hovering、鼠标空闲、空格按住时挂起
    case spaceTap
    /// modifiers 与最近一次修饰键事件一致；colorFormat 跟随 ⇧
    case modifiers
    /// beginTextEditing / endTextEditing / stylesChanged 与状态变化一一对应
    case effectsConsistency
    /// 被动事件（移动、修饰键、滚轮、文本同步、逐层切换）不改文档；多数也不改选区与阶段
    case passiveEvents
    /// 缩放时对边固定、移动选区与方向键不改尺寸
    case selectionEdits
    /// 画完的标注作为一步入栈；拖动标注整体只占一步撤销
    case drawingAndMoving
    /// 提交文字：去掉末尾空白，空白丢弃（重新编辑时删除原标注），否则新增或原位替换
    case textCommit
    /// 命令语义：选工具 / 方向键 / 删除 / 撤销重做 / ⌘A / Tab 逐层（§2.3、§2.11、§9.2）
    case commandSemantics
    /// 点击语义：双击选区内完成复制；序号单击放置；文字单击新建或重新编辑（§2.3、§2.7）
    case pointerSemantics
    /// 截图翻译：进行中的运行就是文档当前引用的那次；引用的运行存在；块与译文的 id 自洽；分隔线在选区内
    case translation

    func violation(in step: FuzzStep) -> String? {
        switch self {
        case .finiteGeometry: ReducerInvariantChecks.finiteGeometry(step)
        case .purity: ReducerInvariantChecks.purity(step)
        case .finishOnce: ReducerInvariantChecks.finishOnce(step)
        case .finishContext: ReducerInvariantChecks.finishContext(step)
        case .escapeAndRightClick: ReducerInvariantChecks.escapeAndRightClick(step)
        case .selectionGeometry: ReducerInvariantChecks.selectionGeometry(step)
        case .selectionScreenPairing: ReducerInvariantChecks.selectionScreenPairing(step)
        case .phaseConsistency: ReducerInvariantChecks.phaseConsistency(step)
        case .windowCaptureMode: ReducerInvariantChecks.windowCaptureMode(step)
        case .hoverDepth: ReducerInvariantChecks.hoverDepth(step)
        case .selectedAnnotation: ReducerInvariantChecks.selectedAnnotation(step)
        case .numbering: ReducerInvariantChecks.numbering(step)
        case .uniqueIDs: ReducerInvariantChecks.uniqueIDs(step)
        case .undoRedo: ReducerInvariantChecks.undoRedo(step)
        case .discardArmed: ReducerInvariantChecks.discardArmed(step)
        case .dragNeedsPress: ReducerInvariantChecks.dragNeedsPress(step)
        case .spaceTap: ReducerInvariantChecks.spaceTap(step)
        case .modifiers: ReducerInvariantChecks.modifiers(step)
        case .effectsConsistency: ReducerInvariantChecks.effectsConsistency(step)
        case .passiveEvents: ReducerInvariantChecks.passiveEvents(step)
        case .selectionEdits: ReducerInvariantChecks.selectionEdits(step)
        case .drawingAndMoving: ReducerInvariantChecks.drawingAndMoving(step)
        case .textCommit: ReducerInvariantChecks.textCommit(step)
        case .commandSemantics: ReducerInvariantChecks.commandSemantics(step)
        case .pointerSemantics: ReducerInvariantChecks.pointerSemantics(step)
        case .translation: ReducerInvariantChecks.translation(step)
        }
    }

    /// 第一个被违反的不变量
    static func firstViolation(in step: FuzzStep, checking invariants: [ReducerInvariant] = allCases)
        -> InvariantViolation?
    {
        for invariant in invariants {
            if let detail = invariant.violation(in: step) {
                return InvariantViolation(invariant: invariant, detail: detail)
            }
        }
        return nil
    }
}

/// 各不变量的实现（分文件：+State 为单步状态，+Transitions 为前后两步的关系）
enum ReducerInvariantChecks {
    /// 有选区、可编辑的阶段（adjusting / annotating）。用 switch 而不是 static 数组，避免并行分片争用同一存储
    static func isSelectionPhase(_ phase: ScreenshotPhase) -> Bool {
        switch phase {
        case .adjusting, .annotating: true
        case .hovering, .selecting, .editingText: false
        }
    }

    static func finiteGeometry(_ step: FuzzStep) -> String? {
        let session = step.session
        var values: [CGFloat] = [session.cursor.x, session.cursor.y]
        if let selection = session.selection {
            values += [selection.origin.x, selection.origin.y, selection.width, selection.height]
        }
        var shapes = step.documentChanged ? session.document.annotations.map(\.shape) : []
        if case .drawing(let annotation) = session.drag {
            shapes.append(annotation.shape)
        }
        values += shapes.flatMap(scalars(of:))
        if let editing = session.textEditing {
            values += [editing.origin.x, editing.origin.y, editing.maxWidth]
            guard editing.maxWidth > 0 else { return "text editor maxWidth \(editing.maxWidth) is not positive" }
        }
        if let bad = values.first(where: { !$0.isFinite }) {
            return "non-finite coordinate \(bad)"
        }
        return nil
    }

    /// 形状里全部坐标分量
    static func scalars(of shape: AnnotationShape) -> [CGFloat] {
        let flatten = { (points: [CGPoint]) in points.flatMap { [$0.x, $0.y] } }
        switch shape {
        case .rectangle(let rect), .ellipse(let rect):
            return [rect.origin.x, rect.origin.y, rect.width, rect.height]
        case .arrow(let from, let to):
            return flatten([from, to])
        case .pen(let points), .highlighter(let points), .mosaic(let points):
            return flatten(points)
        case .text(_, let origin, let maxWidth):
            return flatten([origin]) + [maxWidth]
        case .number(let center):
            return flatten([center])
        }
    }

    static func purity(_ step: FuzzStep) -> String? {
        let again = ScreenshotReducer.reduce(step.previous, event: step.event, topology: step.topology)
        if again.session != step.session {
            return "second reduce produced a different session"
        }
        if again.effects != step.effects {
            return "second reduce produced different effects \(again.effects) vs \(step.effects)"
        }
        return nil
    }

    static func finishOnce(_ step: FuzzStep) -> String? {
        let finishes = step.effects.indices.filter {
            if case .finish = step.effects[$0] { true } else { false }
        }
        if finishes.count > 1 {
            return "\(finishes.count) finish effects: \(step.effects)"
        }
        if let index = finishes.first, index != step.effects.count - 1 {
            return "finish is not the last effect: \(step.effects)"
        }
        return nil
    }

    static func finishContext(_ step: FuzzStep) -> String? {
        for effect in step.effects {
            guard case .finish(let outcome) = effect else { continue }
            if let problem = finishProblem(outcome, step: step) {
                return "finish(\(outcome)): \(problem)"
            }
        }
        return nil
    }

    private static func finishProblem(_ outcome: ScreenshotOutcome, step: FuzzStep) -> String? {
        let session = step.session
        switch outcome {
        case .copy, .save, .pin, .extractText:
            guard session.selection != nil, session.screenID != nil else { return "no selection to export" }
            guard isSelectionPhase(session.phase) else { return "phase \(session.phase)" }
            guard session.textEditing == nil else { return "text editor still open (text not committed)" }
            return nil
        case .copyColor(let text):
            guard !text.isEmpty else { return "empty color text" }
            return step.previous.isMagnifierVisible ? nil : "magnifier was not visible"
        case .captureWindow(let windowID, _):
            guard step.previous.phase == .hovering, step.previous.isWindowCaptureMode else {
                return "not in window capture mode"
            }
            if case .toolbarAction = step.event {
                return nil
            }
            return session.hover?.windowID == windowID ? nil : "window \(windowID) is not the hover target"
        case .cancel:
            switch step.event {
            case .command(.escape), .rightMouseDown, .toolbarAction(.cancel): return nil
            default: return "cancel from unexpected event"
            }
        }
    }
}
