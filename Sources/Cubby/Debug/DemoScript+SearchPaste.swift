#if DEBUG
import AppKit
import CubbyCore

/// `demo:search-paste`：呼出面板 → 键入关键词筛选 → ↓ 换选中项 → ↩ 粘贴到虚构的笔记窗口。
/// 粘贴只写私有剪贴板、把文字接到笔记窗口末尾，不发送 ⌘V
extension AppDelegate {
    private static let searchQuery = "issue"

    func runSearchPasteDemo() async {
        guard let panel else { return }
        let note = DemoNoteWindow(
            title: "Release checklist",
            body:
                "Thursday release\n\n- Record the demo GIF\n- Update the Homebrew cask\n- Reply to the dock issue:\n  ",
            topLeft: CGRect(x: 830, y: 330, width: 560, height: 300))
        let caption = DemoKeyCaption(center: DemoWindows.appKitPoint(CGPoint(x: 1280, y: 772)))
        panel.debugPasteTarget = PasteTarget(name: "Notes", bundleID: "com.apple.Notes", processID: 0)
        panel.viewModel.onPaste = { [weak panel] item, _ in
            guard let panel, let text = item.text else { return }
            try? PasteboardWriter.write(text: text, to: DemoPasteboard.shared)
            panel.hide(animated: false)
            Task { @MainActor in await note.paste(text) }
        }
        await DemoClock.pause(0.6)
        caption.show(HotKey.default.displayName, "Open Cubby")
        panel.show()
        await DemoClock.pause(1.2)
        for count in 1...Self.searchQuery.count {
            panel.viewModel.searchText = String(Self.searchQuery.prefix(count))
            await DemoClock.pause(0.2)
        }
        await DemoClock.pause(0.9)
        caption.show("\u{2193}")
        _ = panel.viewModel.handle(.moveDown)
        await DemoClock.pause(1.1)
        caption.show("\u{21A9}", "Paste")
        _ = panel.viewModel.handle(.paste)
        await DemoClock.pause(3.0)
    }
}
#endif
