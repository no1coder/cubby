import AppKit
import Carbon.HIToolbox

/// 面板中的键盘指令
public enum PanelCommand: Equatable, Sendable {
    case moveUp
    case moveDown
    /// Home / ⌥↑ 跳到首条
    case moveToFirst
    /// End / ⌥↓ 跳到末条
    case moveToLast
    /// PageUp 上移一页（pageSize 条）
    case pageUp
    /// PageDown 下移一页（pageSize 条）
    case pageDown
    /// ↩ 按默认格式粘贴
    case paste
    /// ⇧↩ 以另一种格式粘贴
    case pasteAlternate
    /// ⌘↩ 仅复制，不粘贴
    case copyOnly
    /// ⌘1…⌘9 快速粘贴，参数为从 0 开始的序号
    case pasteAt(Int)
    case escape
    case nextCategory
    case previousCategory
    case delete
    case undo
    case toggleFavorite
    /// ⇧⌘P 把选中的图片贴到屏幕上（与 ⌘P 收藏成对，便于记忆）
    case pinToScreen
    case togglePreview
    case open
    case openSettings
    /// 截图：只由面板顶栏的相机按钮触发（面板内按截图快捷键会先被全局热键处理，不经过按键映射）
    case takeScreenshot
    /// ⌘T（别名 ⇧⌘T）打开 / 关闭翻译卡；不可用时由视图模型给出提示音
    case translate
    /// ⌥↩（及 ⌥ + 小键盘 Enter）翻译后粘贴；翻译卡打开时粘贴卡片上的译文
    case translateAndPaste
    /// ⌘C：仅在翻译卡打开时映射（否则放行给搜索框的「拷贝」）
    case copyTranslation
    /// ⌘S：仅在翻译卡打开时映射
    case saveTranslation
    /// 翻译卡打开且搜索框为空时的 ← / →（参数为 ±1，⇧ 为 ±largeTranslationStep）：
    /// 切换「译文 / 对照 / 原文」；图片卷帘获得焦点时改为微调分隔线
    case stepTranslationView(Int)
    /// ⌘B 打开 / 关闭拆词卡（docs/TEXT-PICK-DESIGN.md P2）；不支持的条目由视图模型给出提示音
    case pickWords
    /// ⌘C：仅在拆词卡打开时映射，复制所选（否则放行给搜索框的「拷贝」）
    case copyPickedWords
    /// ⌘A：仅在拆词卡打开且搜索框为空时映射，全选 / 已全选时清空（否则留给搜索框的「全选」）
    case selectAllWords

    /// ⌘ + 数字键的虚拟键码（按键位而非字符匹配，兼容 AZERTY 等布局）
    private static let digitKeyCodes: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// ⇧← / ⇧→ 的步长（卷帘大步微调；切换视图时只看方向）
    public static let largeTranslationStep = 5

    /// - Parameters:
    ///   - allowsSpace: 搜索框为空：空格用作预览开关，翻译卡里 ← / → 切换视图、拆词卡里 ⌘A 全选
    ///     （否则这些键用于输入、移动光标与搜索框的全选）
    ///   - translationCardOpen: 翻译卡打开时 ⌘C / ⌘S 归卡片，← / → 切换视图
    ///   - textPickOpen: 拆词卡打开时 ⌘C / ⌘A 归卡片
    public static func from(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        allowsSpace: Bool = false,
        translationCardOpen: Bool = false,
        textPickOpen: Bool = false
    ) -> PanelCommand? {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        let code = Int(keyCode)

        if let command = navigationCommand(code: code, flags: flags, allowsSpace: allowsSpace) {
            return command
        }
        if translationCardOpen, allowsSpace, let step = translationArrowStep(code: code, flags: flags) {
            return .stepTranslationView(step)
        }
        if flags == .command, let index = digitKeyCodes.firstIndex(of: code) {
            return .pasteAt(index)
        }
        let character = characters?.lowercased()
        if translationCardOpen, let command = cardCommand(flags: flags, character: character) {
            return command
        }
        if textPickOpen, let command = textPickCommand(flags: flags, character: character, allowsSpace: allowsSpace) {
            return command
        }
        return characterCommand(flags: flags, character: character)
    }

    /// 翻译卡里的 ← / →：无修饰为 ±1，⇧ 为 ±largeTranslationStep
    private static func translationArrowStep(code: Int, flags: NSEvent.ModifierFlags) -> Int? {
        let direction: Int
        switch code {
        case kVK_LeftArrow: direction = -1
        case kVK_RightArrow: direction = 1
        default: return nil
        }
        switch flags {
        case []: return direction
        case .shift: return direction * largeTranslationStep
        default: return nil
        }
    }

    /// 只在翻译卡打开时占用的字母快捷键
    private static func cardCommand(flags: NSEvent.ModifierFlags, character: String?) -> PanelCommand? {
        switch (flags, character) {
        case (.command, "c"): .copyTranslation
        case (.command, "s"): .saveTranslation
        default: nil
        }
    }

    /// 只在拆词卡打开时占用的字母快捷键；⌘A 还要求搜索框为空
    private static func textPickCommand(
        flags: NSEvent.ModifierFlags, character: String?, allowsSpace: Bool
    ) -> PanelCommand? {
        switch (flags, character) {
        case (.command, "c"): .copyPickedWords
        case (.command, "a") where allowsSpace: .selectAllWords
        default: nil
        }
    }

    private static func navigationCommand(
        code: Int,
        flags: NSEvent.ModifierFlags,
        allowsSpace: Bool
    ) -> PanelCommand? {
        switch code {
        case kVK_Escape:
            return .escape
        case kVK_UpArrow where flags.isEmpty:
            return .moveUp
        case kVK_DownArrow where flags.isEmpty:
            return .moveDown
        case kVK_UpArrow where flags == .option, kVK_Home where flags.isEmpty:
            return .moveToFirst
        case kVK_DownArrow where flags == .option, kVK_End where flags.isEmpty:
            return .moveToLast
        case kVK_PageUp where flags.isEmpty:
            return .pageUp
        case kVK_PageDown where flags.isEmpty:
            return .pageDown
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return returnCommand(flags: flags)
        case kVK_Tab where flags.isEmpty:
            return .nextCategory
        case kVK_Tab where flags == .shift:
            return .previousCategory
        case kVK_Delete where flags == .command, kVK_ForwardDelete where flags == .command:
            return .delete
        case kVK_Space where flags.isEmpty && allowsSpace:
            return .togglePreview
        default:
            return nil
        }
    }

    private static func returnCommand(flags: NSEvent.ModifierFlags) -> PanelCommand? {
        switch flags {
        case []: .paste
        case .shift: .pasteAlternate
        case .command: .copyOnly
        case .option: .translateAndPaste
        default: nil
        }
    }

    /// 字母类快捷键按字符匹配，兼容 Dvorak 等布局
    private static func characterCommand(flags: NSEvent.ModifierFlags, character: String?) -> PanelCommand? {
        switch (flags, character) {
        case (.command, "p"): .toggleFavorite
        case ([.command, .shift], "p"): .pinToScreen
        case (.command, "z"): .undo
        case (.command, "o"): .open
        case (.command, "y"): .togglePreview
        case (.command, "t"), ([.command, .shift], "t"): .translate
        case (.command, "b"): .pickWords
        case (.command, ","): .openSettings
        case (.control, "n"): .moveDown
        case (.control, "p"): .moveUp
        default: nil
        }
    }
}

// MARK: - 选择移动

public extension PanelCommand {
    /// 翻页一次移动的条数。卡片高度随类型变化（1–3 行文本、4 行代码、96pt 图片），
    /// 「可见卡片数」并不稳定且需要从视图回传几何信息；固定 5 条约等于 620pt 面板里一屏标准卡片，
    /// 行为可预期、可测试
    static let pageSize = 5

    /// 选择移动类指令从 current 出发的目标序号，结果夹在 0..<count 内；
    /// 非移动类指令或列表为空时返回 nil
    func selectionIndex(from current: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let last = count - 1
        let start = min(max(current, 0), last)
        let target: Int
        switch self {
        case .moveUp: target = start - 1
        case .moveDown: target = start + 1
        case .pageUp: target = start - Self.pageSize
        case .pageDown: target = start + Self.pageSize
        case .moveToFirst: target = 0
        case .moveToLast: target = last
        default: return nil
        }
        return min(max(target, 0), last)
    }
}
