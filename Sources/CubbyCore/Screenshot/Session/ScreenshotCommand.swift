import AppKit
import Carbon.HIToolbox

/// 覆盖层的键盘命令（§2.11）；工具栏按钮也可以直接发送对应命令
public enum ScreenshotCommand: Equatable, Sendable {
    case escape
    case confirm
    case save
    case pin
    case extractText
    case selectAll
    case undo
    case redo
    /// C 键取色。命令本身不带读数，reducer 会忽略它：覆盖层必须把它翻译为
    /// `.toolbarAction(.copyColor(放大镜第二行当前显示的文本))` 再交给 reducer
    case copyColor
    case selectTool(ScreenshotTool)
    case nudge(NudgeDirection, large: Bool)
    case deleteAnnotation
    case commitText
    /// 契约扩展：hovering 时在重叠窗口间逐层切换（Tab = 向后，⇧Tab = 向前）
    case cycleHover(forward: Bool)
    /// 契约扩展：数字键 1–8 选色（顺序同样式条）；作用于选中标注，否则当前工具
    case selectColor(AnnotationColor)
    /// 契约扩展：`]` 加粗一档、`[` 减细一档；作用对象同上
    case adjustWeight(heavier: Bool)
    /// 契约扩展：⇧⌘T 截图翻译——开始翻译；已有译文时切换原文 / 译文；失败时重试。
    /// 映射不看翻译是否可用，由 reducer 按 `ScreenshotSession.isTranslationAvailable` 决定是否生效
    case translate

    /// 有选区的两个阶段
    private static let selectionPhases: Set<ScreenshotPhase> = [.adjusting, .annotating]

    /// 按阶段解释按键（editingText 只识别 escape / commitText）；字母按字符匹配
    public static func from(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        phase: ScreenshotPhase
    ) -> ScreenshotCommand? {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        let code = Int(keyCode)
        if phase == .editingText {
            return textEditingCommand(code: code, flags: flags, characters: characters)
        }
        if let command = keyCodeCommand(code: code, flags: flags, phase: phase) {
            return command
        }
        if selectionPhases.contains(phase), flags.isEmpty,
            let command = styleCommand(code: code, characters: characters)
        {
            return command
        }
        guard let character = characters?.lowercased().first else { return nil }
        return characterCommand(character, flags: flags, phase: phase)
    }

    /// 编辑文字时只拦截 Esc、⌘↩ 与 ⇧⌘T（先提交文字再翻译），其余全部交给 NSTextView
    private static func textEditingCommand(code: Int, flags: NSEvent.ModifierFlags, characters: String?)
        -> ScreenshotCommand?
    {
        switch code {
        case kVK_Escape: return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return flags == .command ? .commitText : nil
        default: return flags == [.command, .shift] && characters?.lowercased() == "t" ? .translate : nil
        }
    }

    /// 按键位匹配的键：Esc、↩、Tab、方向键、删除
    private static func keyCodeCommand(code: Int, flags: NSEvent.ModifierFlags, phase: ScreenshotPhase)
        -> ScreenshotCommand?
    {
        let hasSelection = selectionPhases.contains(phase)
        switch code {
        case kVK_Escape:
            return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return returnCommand(flags: flags, phase: phase)
        case kVK_Tab where phase == .hovering && flags.isEmpty:
            return .cycleHover(forward: true)
        case kVK_Tab where phase == .hovering && flags == .shift:
            return .cycleHover(forward: false)
        case kVK_Delete, kVK_ForwardDelete:
            return hasSelection && flags.isEmpty ? .deleteAnnotation : nil
        default:
            guard hasSelection, let direction = nudgeDirection(code), flags.isEmpty || flags == .shift else {
                return nil
            }
            return .nudge(direction, large: flags == .shift)
        }
    }

    /// 数字键 1–8（主键盘或小键盘，按键位）选色；方括号（按字符，非拉丁字符时退回键位）调粗细
    private static func styleCommand(code: Int, characters: String?) -> ScreenshotCommand? {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8]
        let keypad = [
            kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
            kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8,
        ]
        if let index = digits.firstIndex(of: code) ?? keypad.firstIndex(of: code) {
            return .selectColor(AnnotationColor.allCases[index])
        }
        switch characters {
        case "[": return .adjustWeight(heavier: false)
        case "]": return .adjustWeight(heavier: true)
        case let other? where other.unicodeScalars.allSatisfy(\.isASCII): return nil
        default: break
        }
        switch code {
        case kVK_ANSI_LeftBracket: return .adjustWeight(heavier: false)
        case kVK_ANSI_RightBracket: return .adjustWeight(heavier: true)
        default: return nil
        }
    }

    private static func returnCommand(flags: NSEvent.ModifierFlags, phase: ScreenshotPhase) -> ScreenshotCommand? {
        switch (flags, phase) {
        case ([], .hovering), ([], .adjusting), ([], .annotating): .confirm
        case (.command, .adjusting), (.command, .annotating): .confirm
        default: nil
        }
    }

    private static func nudgeDirection(_ code: Int) -> NudgeDirection? {
        switch code {
        case kVK_UpArrow: .up
        case kVK_DownArrow: .down
        case kVK_LeftArrow: .left
        case kVK_RightArrow: .right
        default: nil
        }
    }

    /// 字母类快捷键按字符匹配，兼容 Dvorak 等布局
    private static func characterCommand(
        _ character: Character,
        flags: NSEvent.ModifierFlags,
        phase: ScreenshotPhase
    ) -> ScreenshotCommand? {
        switch flags {
        case .command:
            return commandLetter(character, phase: phase)
        case [.command, .shift]:
            guard selectionPhases.contains(phase) else { return nil }
            switch character {
            case "z": return .redo
            case "t": return .translate
            default: return nil
            }
        case [], .shift:
            if character == "c" {
                return [.hovering, .selecting, .adjusting].contains(phase) ? .copyColor : nil
            }
            return flags.isEmpty ? toolCommand(character, phase: phase) : nil
        default:
            return nil
        }
    }

    private static func commandLetter(_ character: Character, phase: ScreenshotPhase) -> ScreenshotCommand? {
        let hasSelection = selectionPhases.contains(phase)
        let hoveringOrSelection = hasSelection || phase == .hovering
        switch character {
        case "c": return hoveringOrSelection ? .confirm : nil
        case "a": return hoveringOrSelection ? .selectAll : nil
        case "s": return hasSelection ? .save : nil
        case "p": return hasSelection ? .pin : nil
        case "t": return hasSelection ? .extractText : nil
        case "z": return hasSelection ? .undo : nil
        default: return nil
        }
    }

    /// 工具键：adjusting 只接受真正的工具（V 无操作），annotating 接受全部（V 回指针）
    private static func toolCommand(_ character: Character, phase: ScreenshotPhase) -> ScreenshotCommand? {
        guard let tool = ScreenshotTool.tool(forShortcut: character) else { return nil }
        switch phase {
        case .annotating: return .selectTool(tool)
        case .adjusting: return tool == .pointer ? nil : .selectTool(tool)
        default: return nil
        }
    }
}
