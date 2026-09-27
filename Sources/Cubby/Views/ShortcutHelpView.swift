import SwiftUI
import CubbyCore

/// 快捷键帮助浮层：点击空白处或按 esc 关闭
struct HelpOverlay: View {
    let alternateFormat: PasteFormat
    /// ↩ / ⇧↩ 是否直接粘贴到目标应用；为 false 时两者都只复制，帮助里对应的动作随之改为「复制」
    let pastesDirectly: Bool
    /// 翻译可用时加 ⌘T、⌥↩、按住 ⌥ 三行；翻译卡打开时再加 ⌘C、⌘S
    var translation: ShortcutHelpView.Translation = .unavailable
    /// 底部「完整使用说明…」链接
    var onOpenUserGuide: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .clipShape(RoundedRectangle(cornerRadius: PanelChrome.cornerRadius, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            ShortcutHelpView(
                alternateFormat: alternateFormat,
                pastesDirectly: pastesDirectly,
                translation: translation,
                onOpenUserGuide: onOpenUserGuide
            )
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}

/// 全部快捷键与鼠标操作说明（以面板内浮层展示）
struct ShortcutHelpView: View {
    /// 翻译相关的行
    enum Translation {
        case unavailable
        case available
        /// 翻译卡打开：另有 ⌘C、⌘S
        case cardOpen
    }

    let alternateFormat: PasteFormat
    let pastesDirectly: Bool
    var translation: Translation = .unavailable
    /// 底部「完整使用说明…」链接；nil 时不显示
    var onOpenUserGuide: (() -> Void)?

    private struct Row {
        let keys: String
        let label: String

        init(_ keys: String, _ label: String) {
            self.keys = keys
            self.label = label
        }
    }

    private var keyboardRows: [Row] {
        [
            Row("↑ ↓", String(localized: "Select (or ⌃P ⌃N)", comment: "Shortcut help")),
            Row("⌥↑ ⌥↓", String(localized: "First / last item (or Home, End)", comment: "Shortcut help")),
            // ⇞ ⇟ 在 10pt 键帽里难以辨认；笔记本上翻页就是 fn↑ fn↓
            Row(
                "fn↑ fn↓",
                String(
                    localized: "Up / down 5 items (or Page Up, Page Down)",
                    comment: "Shortcut help: move the selection by a page"
                )
            ),
            Row("↩", primaryActionLabel),
            Row("⇧↩", pastesDirectly ? alternateFormat.pasteActionLabel : alternateFormat.copyActionLabel),
            Row("⌘↩", String(localized: "Copy only", comment: "Shortcut help")),
            Row(
                "⌘1–9",
                pastesDirectly
                    ? String(localized: "Quick paste", comment: "Shortcut help")
                    : String(localized: "Quick copy", comment: "Shortcut help when direct pasting is unavailable")
            ),
            Row(
                String(localized: "Space / ⌘Y", comment: "Shortcut help: key names"),
                String(localized: "Preview", comment: "Shortcut help")
            ),
        ] + translationRows + [
            Row("⇥ / ⇧⇥", String(localized: "Switch category", comment: "Shortcut help")),
            Row("⌘P", String(localized: "Favorite / unfavorite", comment: "Shortcut help")),
            Row("⇧⌘P", String(localized: "Pin image to screen", comment: "Shortcut help")),
            Row("⌘⌫", String(localized: "Delete", comment: "Shortcut help")),
            Row("⌘Z", String(localized: "Undo delete", comment: "Shortcut help")),
            Row("⌘O", String(localized: "Open link or file", comment: "Shortcut help")),
            Row("⌘,", String(localized: "Settings", comment: "Shortcut help")),
            Row(
                "esc",
                String(
                    localized: "Close, one step at a time",
                    comment: "Shortcut help: esc closes help or preview, then clears the search, then closes the panel"
                )
            ),
        ]
    }

    /// ⌘T、⌥↩、按住 ⌥（翻译卡打开时另有 ⌘C、⌘S）
    private var translationRows: [Row] {
        guard translation != .unavailable else { return [] }
        let rows = [
            Row("⌘T", String(localized: "Translate (press again to close)", comment: "Shortcut help")),
            Row("⌥↩", String(localized: "Translate, then paste", comment: "Shortcut help")),
            Row(
                String(localized: "Hold ⌥", comment: "Shortcut help: key names"),
                String(localized: "Preview the translation (in the card: the original)", comment: "Shortcut help")
            ),
        ]
        guard translation == .cardOpen else { return rows }
        return rows + [
            Row("⌘C", String(localized: "Copy the translation", comment: "Shortcut help")),
            Row("⌘S", String(localized: "Save the translation as a new item", comment: "Shortcut help")),
        ]
    }

    /// ↩（与双击卡片）的动作：仅复制时写「复制」，与底栏「↩ 复制」一致
    private var primaryActionLabel: String {
        pastesDirectly
            ? String(localized: "Paste (or double-click a card)", comment: "Shortcut help")
            : String(
                localized: "Copy (or double-click a card)",
                comment: "Shortcut help: ↩ when choosing an item only copies it"
            )
    }

    /// 鼠标操作：双击粘贴已写在 ↩ 一行
    private var mouseRows: [Row] {
        [
            Row(
                String(localized: "Drag", comment: "Shortcut help: mouse gesture, shown in a key cap"),
                String(localized: "Drop a card into another app", comment: "Shortcut help")
            ),
            Row(
                String(localized: "Right-click", comment: "Shortcut help: mouse gesture, shown in a key cap"),
                translation == .unavailable
                    ? String(localized: "More actions, like Pin to Screen", comment: "Shortcut help")
                    : String(localized: "More actions, like Pin to Screen or Translate", comment: "Shortcut help")
            ),
        ]
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            sectionTitle(Text("Keyboard Shortcuts"))
            ForEach(keyboardRows, id: \.keys, content: row)
            sectionTitle(Text("Mouse", comment: "Shortcut help section title"))
                .padding(.top, 6)
            ForEach(mouseRows, id: \.keys, content: row)
            if let onOpenUserGuide {
                GridRow {
                    Button("Full user guide…", action: onOpenUserGuide)
                        .buttonStyle(.link)
                        .font(.system(size: FontSize.footnote))
                        .padding(.top, 6)
                        .gridCellColumns(2)
                }
            }
        }
        .padding(16)
    }

    private func sectionTitle(_ title: Text) -> some View {
        GridRow {
            title
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .padding(.bottom, 4)
                .gridCellColumns(2)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func row(_ row: Row) -> some View {
        GridRow {
            KeyCap(text: row.keys)
                .gridColumnAlignment(.trailing)
            Text(row.label)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .e2eAnchor("help.\(row.keys)")
        }
    }
}
