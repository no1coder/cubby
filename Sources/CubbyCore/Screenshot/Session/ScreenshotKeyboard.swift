import AppKit
import Carbon.HIToolbox

/// 一次按键（从 NSEvent 取出的值，便于测试）
public struct ScreenshotKeyInput: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: NSEvent.ModifierFlags
    /// `NSEvent.characters`：⌘ 组合用它匹配（俄文等布局下系统给出拉丁字母，与菜单快捷键一致）
    public let characters: String?
    /// `NSEvent.charactersIgnoringModifiers`：其余按键用它匹配
    public let charactersIgnoringModifiers: String?
    public let isRepeat: Bool
    /// 事件落在覆盖层窗口上（其他窗口的按下不处理；松开照常同步）
    public let isOverlayWindow: Bool

    public init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        charactersIgnoringModifiers: String?,
        isRepeat: Bool,
        isOverlayWindow: Bool
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.isRepeat = isRepeat
        self.isOverlayWindow = isOverlayWindow
    }

    /// 快捷键匹配用的字符
    var shortcutCharacters: String? {
        modifiers.contains(.command) ? characters : charactersIgnoringModifiers
    }
}

/// 按键解释的输出
public enum ScreenshotKeyOutput: Equatable, Sendable {
    case event(ScreenshotEvent)
    /// C 键取色：读数由覆盖层从放大镜取，再发 `.toolbarAction(.copyColor(...))`
    case copyColor
}

/// 一次按键的处理结果：是否吞掉（不再交给窗口 / 菜单）以及要发出的输出
public struct ScreenshotKeyDecision: Equatable, Sendable {
    public let consumed: Bool
    public let outputs: [ScreenshotKeyOutput]

    public init(consumed: Bool, outputs: [ScreenshotKeyOutput]) {
        self.consumed = consumed
        self.outputs = outputs
    }

    static let pass = ScreenshotKeyDecision(consumed: false, outputs: [])
    static let swallow = ScreenshotKeyDecision(consumed: true, outputs: [])
}

/// 覆盖层的按键解释（§3.4.5）：keyDown / keyUp / flagsChanged → 输出，纯值类型、可测试
///
/// - editingText 且输入法有组字文本时一律放行（⌘Q 之类除外），Esc / ↩ / 空格都交给输入法；
/// - 空格不是系统修饰键：非编辑阶段由这里维护按下状态，随 `.modifiersChanged` 上报（忽略自动重复）；
/// - 非编辑阶段吞掉所有按键：覆盖层看起来像别的应用，⌘Q 之类不能落到 Cubby 的菜单上；
/// - 编辑文字时只放行编辑类 ⌘ 组合（剪切、拷贝、粘贴、全选、撤销、重做）。
public struct ScreenshotKeyboard: Equatable, Sendable {
    /// 编辑文字时允许交给文本视图 / 编辑菜单的 ⌘ 组合
    private static let editingCommandKeys: Set<String> = ["a", "c", "v", "x", "z"]
    private static let relevantFlags: NSEvent.ModifierFlags = [.shift, .option, .control, .command]

    public private(set) var isSpaceDown = false
    public private(set) var flags: NSEvent.ModifierFlags = []

    public init() {}

    public mutating func keyDown(_ key: ScreenshotKeyInput, phase: ScreenshotPhase, isComposingText: Bool)
        -> ScreenshotKeyDecision
    {
        guard key.isOverlayWindow else { return .pass }
        let isEditing = phase == .editingText
        if isEditing && isComposingText {
            return blocksInEditor(key) ? .swallow : .pass
        }
        if Int(key.keyCode) == kVK_Space && !isEditing && key.modifiers.isDisjoint(with: .command) {
            guard !key.isRepeat && !isSpaceDown else { return .swallow }
            isSpaceDown = true
            return ScreenshotKeyDecision(consumed: true, outputs: [modifiersOutput(phase: phase)])
        }
        let command = ScreenshotCommand.from(
            keyCode: key.keyCode,
            modifiers: key.modifiers,
            characters: key.shortcutCharacters,
            phase: phase
        )
        guard let command else {
            return isEditing && !blocksInEditor(key) ? .pass : .swallow
        }
        let output: ScreenshotKeyOutput = command == .copyColor ? .copyColor : .event(.command(command))
        return ScreenshotKeyDecision(consumed: true, outputs: [output])
    }

    /// 空格松开：只要之前按下过就同步（不看窗口，按住期间 key 可能已转到别的窗口）
    public mutating func keyUp(keyCode: UInt16, phase: ScreenshotPhase) -> ScreenshotKeyDecision {
        guard Int(keyCode) == kVK_Space, isSpaceDown else { return .pass }
        isSpaceDown = false
        return ScreenshotKeyDecision(consumed: true, outputs: [modifiersOutput(phase: phase)])
    }

    /// 修饰键变化：上报但不吞掉（文本视图也需要看到）
    public mutating func flagsChanged(_ flags: NSEvent.ModifierFlags, phase: ScreenshotPhase) -> ScreenshotKeyDecision {
        self.flags = flags
        return ScreenshotKeyDecision(consumed: false, outputs: [modifiersOutput(phase: phase)])
    }

    /// 覆盖层重新成为 key：焦点离开期间的松开事件到不了这里，修饰键以系统当前状态为准、空格视为已松开；
    /// 有变化才上报
    public mutating func resynchronize(flags current: NSEvent.ModifierFlags, phase: ScreenshotPhase)
        -> ScreenshotKeyDecision
    {
        let relevant = current.intersection(Self.relevantFlags)
        guard relevant != flags.intersection(Self.relevantFlags) || isSpaceDown else { return .pass }
        flags = relevant
        isSpaceDown = false
        return ScreenshotKeyDecision(consumed: false, outputs: [modifiersOutput(phase: phase)])
    }

    public mutating func reset() {
        isSpaceDown = false
        flags = []
    }

    // MARK: - 内部

    /// 编辑文字时：普通输入交给文本视图；⌘ 组合只放行编辑类，其余（⌘Q、⌘W…）吞掉
    private func blocksInEditor(_ key: ScreenshotKeyInput) -> Bool {
        guard key.modifiers.contains(.command) else { return false }
        let letter = key.shortcutCharacters?.lowercased() ?? ""
        return !Self.editingCommandKeys.contains(letter)
    }

    /// 编辑文字时空格是正文，不作为修饰键上报
    private func modifiersOutput(phase: ScreenshotPhase) -> ScreenshotKeyOutput {
        .event(.modifiersChanged(KeyModifiers(flags: flags, spaceDown: isSpaceDown && phase != .editingText)))
    }
}
