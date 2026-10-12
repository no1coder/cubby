import CubbyCore
import Foundation

/// 帮助浮层的内容：按「选择与粘贴 / 查看与整理 / 图片 / 翻译」分组的行（docs/DESIGN.md 键盘一节）
struct ShortcutHelpContent {
    /// 翻译相关的行
    enum Translation {
        case unavailable
        case available
        /// 翻译卡打开：另有 ⌘C、⌘S
        case cardOpen
    }

    /// 图片分组用到的设置：全局快捷键关闭（nil）时隐藏对应行，晾衣绳关闭时隐藏两行晾衣绳
    struct Images {
        var onlyImagesHotKey: String?
        var clotheslineEnabled = true
        var clotheslineHotKey: String?
    }

    struct Row: Identifiable {
        /// 每个键帽一项（「⌘⌫」「⌘Z」两个键帽）
        let keys: [String]
        let label: String

        var id: String { keys.joined(separator: " ") }

        init(_ keys: String..., label: String) {
            self.keys = keys
            self.label = label
        }
    }

    struct Section: Identifiable {
        let title: String
        /// 标题旁的「新」徽标
        var isNew = false
        let rows: [Row]

        var id: String { title }
    }

    let alternateFormat: PasteFormat
    /// ↩ / ⇧↩ 是否直接粘贴到目标应用；为 false 时两者都只复制，对应的动作随之改为「复制」
    let pastesDirectly: Bool
    var translation: Translation = .unavailable
    /// 拆词卡打开时 ⌘B 之后再加 ⌘A、⌘C（docs/TEXT-PICK-DESIGN.md §2）
    var textPickOpen = false
    var images = Images()

    var sections: [Section] {
        [selectAndPaste, viewAndOrganize, imageSection, translationSection].compactMap { $0 }
    }

    // MARK: - 选择与粘贴

    private var selectAndPaste: Section {
        Section(
            title: String(localized: "Select & Paste", comment: "Shortcut help section title"),
            rows: [
                Row("↑↓", "←→", label: String(localized: "Select (or ⌃P ⌃N)", comment: "Shortcut help")),
                Row(
                    "⌥↑", "⌥↓",
                    label: String(localized: "First / last item (or Home, End)", comment: "Shortcut help")),
                // ⇞ ⇟ 在 10pt 键帽里难以辨认；笔记本上翻页就是 fn↑ fn↓
                Row(
                    "fn↑", "fn↓",
                    label: String(
                        localized: "Up / down 5 items (or Page Up, Page Down)",
                        comment: "Shortcut help: move the selection by a page")),
                Row("↩", label: primaryActionLabel),
                Row("⇧↩", label: pastesDirectly ? alternateFormat.pasteActionLabel : alternateFormat.copyActionLabel),
                Row("⌘↩", label: String(localized: "Copy only", comment: "Shortcut help")),
                Row("⌘1 – ⌘9", label: quickPasteLabel),
                Row(
                    String(localized: "Drag", comment: "Shortcut help: mouse gesture, shown in a key cap"),
                    label: String(localized: "Drop a card into another app", comment: "Shortcut help")),
            ]
        )
    }

    /// ↩（与双击卡片）的动作：仅复制时写「复制」，与底栏「↩ 复制」一致
    private var primaryActionLabel: String {
        pastesDirectly
            ? String(
                localized: "Paste to the current app (or double-click)",
                comment: "Shortcut help: ↩ or double-clicking a card pastes into the app in front")
            : String(
                localized: "Copy (or double-click a card)",
                comment: "Shortcut help: ↩ when choosing an item only copies it")
    }

    private var quickPasteLabel: String {
        pastesDirectly
            ? String(localized: "Quick paste the first nine", comment: "Shortcut help: ⌘1 – ⌘9")
            : String(
                localized: "Quick copy the first nine",
                comment: "Shortcut help: ⌘1 – ⌘9 when direct pasting is unavailable")
    }

    // MARK: - 查看与整理

    private var viewAndOrganize: Section {
        Section(
            title: String(localized: "View & Organize", comment: "Shortcut help section title"),
            rows: [
                Row(
                    String(localized: "Space", comment: "Shortcut help: key name, shown in a key cap"), "⌘Y",
                    label: String(localized: "Preview", comment: "Shortcut help"))
            ]
                + textPickRows
                + [
                    Row("⇥", "⇧⇥", label: String(localized: "Switch category", comment: "Shortcut help")),
                    Row("⌘P", label: String(localized: "Favorite / unfavorite", comment: "Shortcut help")),
                    Row("⌘⌫", "⌘Z", label: String(localized: "Delete / undo", comment: "Shortcut help")),
                    Row("⌘O", label: String(localized: "Open link or file", comment: "Shortcut help")),
                    Row(
                        String(localized: "Right-click", comment: "Shortcut help: mouse gesture, shown in a key cap"),
                        label: translation == .unavailable
                            ? String(localized: "More actions, like Pin to Screen", comment: "Shortcut help")
                            : String(
                                localized: "More actions, like Pin to Screen or Translate", comment: "Shortcut help")),
                    Row("⌘,", label: String(localized: "Settings", comment: "Shortcut help")),
                    Row(
                        "esc",
                        label: String(
                            localized: "Close, one step at a time",
                            comment:
                                "Shortcut help: esc closes help or preview, then clears the search, then closes the panel"
                        )),
                ]
        )
    }

    /// ⌘B（长按卡片写在同一行，像「双击」写在 ↩ 一行）；拆词卡打开时另有 ⌘A、⌘C
    private var textPickRows: [Row] {
        let open = Row("⌘B", label: String(localized: "Pick words (or long-press a card)", comment: "Shortcut help"))
        guard textPickOpen else { return [open] }
        return [
            open,
            Row("⌘A", label: String(localized: "Select all words (again to clear)", comment: "Shortcut help")),
            Row("⌘C", label: String(localized: "Copy the picked words", comment: "Shortcut help")),
        ]
    }

    // MARK: - 图片

    private var imageSection: Section {
        var rows: [Row] = []
        if let hotKey = images.onlyImagesHotKey {
            rows.append(
                Row(hotKey, label: String(localized: "Only images (global)", comment: "Shortcut help: global shortcut"))
            )
        }
        if images.clotheslineEnabled {
            rows.append(
                Row(
                    "⌘L",
                    label: String(
                        localized: "Hang on / take down from the clothesline", comment: "Shortcut help: ⌘L on an image")
                ))
            if let hotKey = images.clotheslineHotKey {
                rows.append(
                    Row(
                        hotKey,
                        label: String(
                            localized: "Show the clothesline (global)", comment: "Shortcut help: global shortcut")
                    ))
            }
        }
        rows.append(Row("⇧⌘P", label: String(localized: "Pin to screen", comment: "Shortcut help: ⇧⌘P on an image")))
        return Section(
            title: String(localized: "Images", comment: "Shortcut help section title"), isNew: true, rows: rows)
    }

    // MARK: - 翻译

    /// ⌘T、⌥↩、按住 ⌥（翻译卡打开时另有 ⌘C、⌘S）；翻译不可用时整组不显示
    private var translationSection: Section? {
        guard translation != .unavailable else { return nil }
        var rows = [
            Row("⌘T", label: String(localized: "Open translation card", comment: "Shortcut help")),
            Row("⌥↩", label: String(localized: "Translate and paste", comment: "Shortcut help")),
            Row(
                String(localized: "Hold ⌥", comment: "Shortcut help: key names"),
                label: translation == .cardOpen
                    ? String(localized: "Preview the translation (in the card: the original)", comment: "Shortcut help")
                    : String(localized: "Hold to preview translation", comment: "Shortcut help")),
        ]
        if translation == .cardOpen {
            rows += [
                Row("⌘C", label: String(localized: "Copy the translation", comment: "Shortcut help")),
                Row("⌘S", label: String(localized: "Save the translation as a new item", comment: "Shortcut help")),
            ]
        }
        return Section(
            title: String(localized: "Translation", comment: "Shortcut help section title"), rows: rows)
    }
}
