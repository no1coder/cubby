import CoreGraphics

/// 截图会话的完整状态（不可变值）；只由 `ScreenshotReducer.reduce` 产生新值，覆盖层据此渲染（单向数据流）
///
/// 契约扩展（只读）：`isDiscardArmed`（PM Q1）、`hoverDepth`（重叠窗口逐层切换）、
/// `isWindowCaptureMode`（纯净窗口截图）、截图翻译的开关与卷帘（ScreenshotTranslation.swift）；
/// 另有若干派生属性，见 ScreenshotSession+Derived.swift 与 ScreenshotSession+Translation.swift。
public struct ScreenshotSession: Equatable, Sendable {
    public let phase: ScreenshotPhase
    /// 选区所在屏
    public let screenID: UInt32?
    /// 选区（全局点）；hovering 时为 nil
    public let selection: CGRect?
    /// 当前悬停目标（= 候选栈中 hoverDepth 那一层）；只在 hovering 时有值
    public let hover: HoverTarget?
    public let cursor: CGPoint
    public let modifiers: KeyModifiers
    /// pointer = 无工具
    public let tool: ScreenshotTool
    public let styles: ToolStyles
    public let document: AnnotationDocument
    public let selectedAnnotation: AnnotationID?
    public let drag: DragState
    public let textEditing: TextEditingState?
    /// ⇧ 按住时 .rgb
    public let colorFormat: ColorFormat
    /// 有标注时按过一次 Esc，正等待第二次 Esc 确认放弃（PM Q1）
    public let isDiscardArmed: Bool
    /// 重叠窗口的层深：0 = 最上层窗口，最大 = 整屏
    public let hoverDepth: Int
    /// 纯净窗口截图模式（hovering 时在窗口上单独按一下空格）
    public let isWindowCaptureMode: Bool
    /// 截图翻译可用（macOS 26+ 且 App 提供了翻译服务）；不可用时翻译事件与 ⇧⌘T 一律忽略
    public let isTranslationAvailable: Bool
    /// 「原文 | 译文」开关：true = 译文。决定复制 / 存储 / 贴图导出哪个版本
    public let showsTranslation: Bool
    /// 卷帘对比已打开（只影响查看）
    public let isWipeEnabled: Bool
    /// 卷帘分隔线位置（全局点 x）；nil = 选区水平中点
    public let wipePosition: CGFloat?
    /// 分隔线有键盘焦点（拖过之后）：← / → 微调分隔线而不是移动选区
    public let isWipeFocused: Bool

    // MARK: - 内部状态（不属于公开契约）

    /// 当前鼠标按下的上下文；松开后为 nil
    let press: PointerPress?
    /// 计算 hover 时的候选栈；栈变化时 hoverDepth 归零
    let hoverCandidates: [HoverTarget]
    /// 滚轮切换层级的累积量（点）
    let scrollAccumulator: CGFloat
    /// hovering 时空格已按下且期间没有其他操作：松开即切换窗口模式
    let isSpaceTapPending: Bool
    /// 下一个新标注的序号（生成确定性 id，reducer 不依赖随机数）
    let annotationSerial: Int
    /// 本会话的全部翻译运行（文档的撤销快照按 id 引用）
    let translationRuns: [TranslationRunID: TranslationRun]
    /// 识别 / 翻译进行中的那次运行（同一时刻至多一个；它总是当前文档引用的运行）
    let activeTranslation: TranslationRunID?
    /// 下一次翻译运行的序号
    let translationSerial: Int

    /// 会话起点：hovering、指针工具、空文档；hover 需在第一次 `.mouseMoved` 后才有值
    public static func initial(styles: ToolStyles, cursor: CGPoint) -> ScreenshotSession {
        ScreenshotSession(Draft(styles: styles, cursor: cursor))
    }

    /// 同 `initial(styles:cursor:)`，并立即按拓扑计算光标下的悬停目标（契约扩展）
    public static func initial(styles: ToolStyles, cursor: CGPoint, topology: ScreenTopology) -> ScreenshotSession {
        ScreenshotReducer.refreshingHover(initial(styles: styles, cursor: cursor), at: cursor, topology: topology)
    }

    // MARK: - 不可变更新

    /// 可变镜像：只在构造新会话的闭包内使用，会话本身始终不可变
    struct Draft {
        var phase: ScreenshotPhase = .hovering
        var screenID: UInt32?
        var selection: CGRect?
        var hover: HoverTarget?
        var cursor: CGPoint
        var modifiers: KeyModifiers = []
        var tool: ScreenshotTool = .pointer
        var styles: ToolStyles
        var document: AnnotationDocument = .empty
        var selectedAnnotation: AnnotationID?
        var drag: DragState = .none
        var textEditing: TextEditingState?
        var colorFormat: ColorFormat = .hex
        var isDiscardArmed = false
        var hoverDepth = 0
        var isWindowCaptureMode = false
        var isTranslationAvailable = false
        var showsTranslation = true
        var isWipeEnabled = false
        var wipePosition: CGFloat?
        var isWipeFocused = false
        var press: PointerPress?
        var hoverCandidates: [HoverTarget] = []
        var scrollAccumulator: CGFloat = 0
        var isSpaceTapPending = false
        var annotationSerial = 1
        var translationRuns: [TranslationRunID: TranslationRun] = [:]
        var activeTranslation: TranslationRunID?
        var translationSerial = 1

        init(styles: ToolStyles, cursor: CGPoint) {
            self.styles = styles
            self.cursor = cursor
        }

        init(_ session: ScreenshotSession) {
            phase = session.phase
            screenID = session.screenID
            selection = session.selection
            hover = session.hover
            cursor = session.cursor
            modifiers = session.modifiers
            tool = session.tool
            styles = session.styles
            document = session.document
            selectedAnnotation = session.selectedAnnotation
            drag = session.drag
            textEditing = session.textEditing
            colorFormat = session.colorFormat
            isDiscardArmed = session.isDiscardArmed
            hoverDepth = session.hoverDepth
            isWindowCaptureMode = session.isWindowCaptureMode
            isTranslationAvailable = session.isTranslationAvailable
            showsTranslation = session.showsTranslation
            isWipeEnabled = session.isWipeEnabled
            wipePosition = session.wipePosition
            isWipeFocused = session.isWipeFocused
            press = session.press
            hoverCandidates = session.hoverCandidates
            scrollAccumulator = session.scrollAccumulator
            isSpaceTapPending = session.isSpaceTapPending
            annotationSerial = session.annotationSerial
            translationRuns = session.translationRuns
            activeTranslation = session.activeTranslation
            translationSerial = session.translationSerial
        }
    }

    init(_ draft: Draft) {
        phase = draft.phase
        screenID = draft.screenID
        selection = draft.selection
        hover = draft.hover
        cursor = draft.cursor
        modifiers = draft.modifiers
        tool = draft.tool
        styles = draft.styles
        document = draft.document
        selectedAnnotation = draft.selectedAnnotation
        drag = draft.drag
        textEditing = draft.textEditing
        colorFormat = draft.colorFormat
        isDiscardArmed = draft.isDiscardArmed
        hoverDepth = draft.hoverDepth
        isWindowCaptureMode = draft.isWindowCaptureMode
        isTranslationAvailable = draft.isTranslationAvailable
        showsTranslation = draft.showsTranslation
        isWipeEnabled = draft.isWipeEnabled
        wipePosition = draft.wipePosition
        isWipeFocused = draft.isWipeFocused
        press = draft.press
        hoverCandidates = draft.hoverCandidates
        scrollAccumulator = draft.scrollAccumulator
        isSpaceTapPending = draft.isSpaceTapPending
        annotationSerial = draft.annotationSerial
        translationRuns = draft.translationRuns
        activeTranslation = draft.activeTranslation
        translationSerial = draft.translationSerial
    }

    /// 标记截图翻译是否可用（契约扩展）：协调器在覆盖层上屏前按「macOS 26+ 且提供了翻译服务」设置
    public func settingTranslationAvailable(_ available: Bool) -> ScreenshotSession {
        updating { $0.isTranslationAvailable = available }
    }

    /// 返回应用了 change 的新会话；self 不变
    func updating(_ change: (inout Draft) -> Void) -> ScreenshotSession {
        var draft = Draft(self)
        change(&draft)
        return ScreenshotSession(draft)
    }
}
