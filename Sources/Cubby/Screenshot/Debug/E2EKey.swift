#if DEBUG
import AppKit
import Carbon.HIToolbox

/// 合成按键的描述：虚拟键码 + 字符 + 该键自带的修饰标志（方向键带 numericPad / function，与真实事件一致）
struct E2EKey: CustomStringConvertible {
    let keyCode: UInt16
    let characters: String
    let intrinsicFlags: NSEvent.ModifierFlags
    let name: String

    init(_ keyCode: Int, _ characters: String, name: String, flags: NSEvent.ModifierFlags = []) {
        self.keyCode = UInt16(keyCode)
        self.characters = characters
        self.intrinsicFlags = flags
        self.name = name
    }

    var description: String {
        name
    }

    static let returnKey = E2EKey(kVK_Return, "\r", name: "Return")
    static let escape = E2EKey(kVK_Escape, "\u{1B}", name: "Esc")
    static let tab = E2EKey(kVK_Tab, "\t", name: "Tab")
    static let space = E2EKey(kVK_Space, " ", name: "Space")
    static let delete = E2EKey(kVK_Delete, "\u{7F}", name: "Delete")
    static let forwardDelete = E2EKey(
        kVK_ForwardDelete, functionKey(NSDeleteFunctionKey), name: "ForwardDelete", flags: .function)
    static let upArrow = arrow(kVK_UpArrow, NSUpArrowFunctionKey, name: "Up")
    static let downArrow = arrow(kVK_DownArrow, NSDownArrowFunctionKey, name: "Down")
    static let leftArrow = arrow(kVK_LeftArrow, NSLeftArrowFunctionKey, name: "Left")
    static let rightArrow = arrow(kVK_RightArrow, NSRightArrowFunctionKey, name: "Right")

    /// 字母、数字与常见符号（美式键位）；其他字符沿用空格键码，只靠 characters 区分
    static func character(_ character: Character) -> E2EKey {
        let lower = Character(character.lowercased())
        let code = letterCodes[lower] ?? digitCodes[lower] ?? symbolCodes[lower] ?? kVK_Space
        return E2EKey(code, String(character), name: String(character))
    }

    /// 修饰键本身的键码（flagsChanged 事件用）
    static func modifierKeyCode(for flag: NSEvent.ModifierFlags) -> UInt16 {
        switch flag {
        case .shift: UInt16(kVK_Shift)
        case .option: UInt16(kVK_Option)
        case .control: UInt16(kVK_Control)
        default: UInt16(kVK_Command)
        }
    }

    // MARK: - 私有

    private static func arrow(_ code: Int, _ function: Int, name: String) -> E2EKey {
        E2EKey(code, functionKey(function), name: name, flags: [.numericPad, .function])
    }

    private static func functionKey(_ value: Int) -> String {
        UnicodeScalar(UInt32(value)).map { String(Character($0)) } ?? ""
    }

    private static let letterCodes: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    ]

    private static let digitCodes: [Character: Int] = [
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    private static let symbolCodes: [Character: Int] = [
        " ": kVK_Space, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "-": kVK_ANSI_Minus, "!": kVK_ANSI_1,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
    ]
}
#endif
