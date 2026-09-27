import AppKit
import Carbon.HIToolbox

/// 全局快捷键：Carbon 虚拟键码 + Carbon 修饰键 + 按键显示名
public struct HotKey: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    /// 按键显示名（如 "V"、"Space"、"F5"）
    public let keyLabel: String

    public static let `default` = HotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "V"
    )

    /// 截图默认快捷键 ⇧⌘2：与系统 ⇧⌘3/4/5 同族，且未被 macOS 保留
    public static let screenshotDefault = HotKey(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "2"
    )

    /// 显示顺序遵循系统惯例：⌃ ⌥ ⇧ ⌘
    private static let modifierOrder: [(mask: Int, symbol: String)] = [
        (controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘"),
    ]

    private static let functionKeyCodes: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// 从键盘事件构造。必须包含 ⌘ / ⌥ / ⌃ 之一（功能键除外），Esc 保留用于取消录制。
    public init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String?) {
        let code = Int(keyCode)
        guard code != kVK_Escape else { return nil }

        let carbon = Self.carbonModifiers(from: modifierFlags)
        let isFunctionKey = Self.functionKeyCodes[code] != nil
        let hasPrimaryModifier = carbon & UInt32(cmdKey | optionKey | controlKey) != 0
        guard hasPrimaryModifier || isFunctionKey else { return nil }

        guard let label = Self.label(forKeyCode: code, characters: characters) else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: carbon, keyLabel: label)
    }

    /// 修饰键符号 + 按键，如 "⇧⌘V"
    public var displayName: String {
        keySymbols.joined()
    }

    /// 逐个按键的符号，便于渲染为键帽
    public var keySymbols: [String] {
        Self.modifierOrder
            .filter { modifiers & UInt32($0.mask) != 0 }
            .map(\.symbol) + [keyLabel]
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    private static func label(forKeyCode code: Int, characters: String?) -> String? {
        if let name = functionKeyCodes[code] ?? specialKeyLabels[code] { return name }
        guard let characters = characters?.trimmingCharacters(in: .whitespacesAndNewlines),
            !characters.isEmpty
        else { return nil }
        return characters.uppercased()
    }
}

/// 面板出现的位置
public enum PanelPosition: String, CaseIterable, Sendable {
    case mouse
    case statusItem
    case center

    public var displayName: String {
        switch self {
        case .mouse: String(localized: "Next to the pointer", comment: "Panel position option")
        case .statusItem: String(localized: "Below the menu bar icon", comment: "Panel position option")
        case .center: String(localized: "Center of the screen", comment: "Panel position option")
        }
    }
}

/// 粘贴文本时的默认格式
public enum PasteFormat: String, CaseIterable, Sendable {
    case original
    case plainText

    public var displayName: String {
        switch self {
        case .original: String(localized: "Original formatting", comment: "Paste format option")
        case .plainText: String(localized: "Plain text", comment: "Paste format option")
        }
    }

    /// ⇧↩ 使用的另一种格式
    public var alternate: PasteFormat {
        self == .original ? .plainText : .original
    }
}
