import AppKit
import CoreGraphics

/// 截图会话的阶段（§2.2）；idle / capturing / finishing 由 App 层管理，不在 reducer 中
public enum ScreenshotPhase: Equatable, Sendable {
    /// 无选区：悬停识别窗口
    case hovering
    /// 正在拖拽创建选区
    case selecting
    /// 有选区、指针模式
    case adjusting
    /// 有选区、某个标注工具激活
    case annotating
    /// 文字标注的编辑器打开中
    case editingText
}

/// 覆盖层关心的修饰键；空格不是系统修饰键，由覆盖层在 keyDown / keyUp 时自行维护
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let command = KeyModifiers(rawValue: 1 << 2)
    /// 空格按住中（selecting 时平移选区；hovering 时单独按下再松开 = 切换窗口模式）
    public static let space = KeyModifiers(rawValue: 1 << 3)

    /// 从 `NSEvent.ModifierFlags` 转换（只取 ⇧ ⌥ ⌘）；spaceDown 为空格是否按住
    public init(flags: NSEvent.ModifierFlags, spaceDown: Bool = false) {
        let pairs: [(NSEvent.ModifierFlags, KeyModifiers)] = [
            (.shift, .shift), (.option, .option), (.command, .command),
        ]
        let mapped = pairs.filter { flags.contains($0.0) }.map(\.1)
        self = KeyModifiers(mapped).union(spaceDown ? .space : [])
    }
}

/// 鼠标拖拽的子状态（§2.2）
public enum DragState: Equatable, Sendable {
    case none
    /// previous：拖拽前已有的选区，Esc 时恢复
    case creatingSelection(anchor: CGPoint, previous: CGRect?)
    case movingSelection(last: CGPoint)
    case resizing(SelectionHandle)
    /// 正在画的标注（尚未进入文档，覆盖层画在实时层）
    case drawing(Annotation)
    case movingAnnotation(AnnotationID, last: CGPoint)
    /// 契约扩展：拖动选中箭头的一端重新指向（另一端固定）
    case movingArrowEnd(AnnotationID, end: ArrowEnd)

    /// 是否为作用于选区本身的拖拽（此时隐藏工具栏）
    var isSelectionDrag: Bool {
        switch self {
        case .creatingSelection, .movingSelection, .resizing: true
        case .none, .drawing, .movingAnnotation, .movingArrowEnd: false
        }
    }
}

/// 箭头的一端：尾（起点）或头（箭尖）
public enum ArrowEnd: Equatable, Sendable, CaseIterable {
    case tail
    case head
}

/// 文字编辑器的状态
///
/// 契约扩展：`text`（编辑器当前内容，覆盖层用 `.textChanged` 同步）与 `maxWidth`（换行宽度，
/// 编辑器与 CoreText 渲染必须使用同一值）。
public struct TextEditingState: Equatable, Sendable {
    /// 文字第一行行框的左上角（全局点）；编辑器的内边距在它之外
    public let origin: CGPoint
    /// 重新编辑已有文字时为其 id
    public let existing: AnnotationID?
    /// 编辑器当前文本
    public let text: String
    /// 换行宽度（点）
    public let maxWidth: CGFloat

    public init(origin: CGPoint, existing: AnnotationID?, text: String, maxWidth: CGFloat) {
        self.origin = origin
        self.existing = existing
        self.text = text
        self.maxWidth = maxWidth
    }

    /// 返回只改文本的新状态
    func withText(_ text: String) -> TextEditingState {
        TextEditingState(origin: origin, existing: existing, text: text, maxWidth: maxWidth)
    }
}

/// 一次鼠标按下的上下文：用于拖拽阈值判定、按下时的选区 / 文档快照（拖拽按总位移计算，不漂移）
struct PointerPress: Equatable, Sendable {
    /// 按下后拖拽超过阈值时要做的事
    enum Intent: Equatable, Sendable {
        /// hovering：单击选中悬停目标，拖拽新建选区
        case selectHover
        /// 窗口模式：单击截取窗口，拖拽无效
        case captureWindow
        /// adjusting 选区外：拖拽新建选区（原选区作为 previous）
        case newSelection
        /// 选区内：拖拽移动选区
        case moveSelection
        case resize(SelectionHandle)
        case moveAnnotation(AnnotationID)
        /// 选中箭头的端点手柄：拖拽重新指向
        case moveArrowEnd(AnnotationID, ArrowEnd)
        /// annotating：按当前工具绘制
        case draw
        /// 无后续动作（序号已放置、拖拽已作废等）
        case none
    }

    let location: CGPoint
    let intent: Intent
    let selection: CGRect?
    let screenID: UInt32?
    let document: AnnotationDocument

    func with(intent: Intent) -> PointerPress {
        PointerPress(location: location, intent: intent, selection: selection, screenID: screenID, document: document)
    }

    /// 换掉按下时的文档快照（按住鼠标期间 Esc 取消了翻译：拖动重建文档时不能把被取消的译文带回来）
    func with(document: AnnotationDocument) -> PointerPress {
        PointerPress(location: location, intent: intent, selection: selection, screenID: screenID, document: document)
    }
}
