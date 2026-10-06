import AppKit
import CubbyCore

// 视图模型里的拆词路由（docs/TEXT-PICK-DESIGN.md §2）：拆词状态在 TextPickController，
// 这里只把按键、长按、右键菜单与选中项变化转给它，并维护详情区（预览 / 翻译卡 / 拆词卡三者互斥）

extension PanelViewModel {
    var isTextPickOpen: Bool {
        detailPane == .textPick
    }

    /// ⌘B：先关帮助；拆词卡打开时关闭（从预览切来的回到预览）；否则对选中项打开（预览或翻译卡打开时切过来）
    func toggleTextPick() {
        if isShowingHelp { toggleHelp() }
        if isTextPickOpen {
            closeTextPick()
            return
        }
        guard let item = selectedItem else { return }
        openTextPick(for: item)
    }

    /// 对指定条目打开拆词卡（⌘B、长按、右键菜单、读屏操作）。不支持的条目：选中它，提示音 + 底栏提示（P4）；
    /// 拆词卡已打开时跟到这一条
    func openTextPick(for item: ClipItem) {
        if isShowingHelp { toggleHelp() }
        select(item)
        guard TextPickSource(item: item).text != nil else {
            rejectTextPick()
            return
        }
        if isTextPickOpen {
            textPick.follow(item)
            return
        }
        let fromPreview = isPreviewVisible || (isTranslationCardOpen && cardOpenedFromPreview)
        guard textPick.open(item, fromPreview: fromPreview) else {
            rejectTextPick()
            return
        }
        translation?.card.close()
        translation?.peek.cancel()
        setDetailPane(.textPick)
    }

    /// 关闭拆词卡：从预览（或从预览切来的翻译卡）切来的回到预览
    func closeTextPick() {
        let backToPreview = textPick.openedFromPreview
        textPick.close()
        setDetailPane(backToPreview ? .preview : nil)
    }

    /// 选中项变化：拆词卡跟随（选取清空）；没有选中项时关闭
    func textPickSelectionChanged() {
        guard isTextPickOpen else { return }
        textPick.follow(selectedItem)
        if !textPick.isOpen {
            setDetailPane(nil)
        }
    }

    /// 拆词卡打开时的 ↩ / ⇧↩（粘贴所选）、⌘↩ / ⌘C（复制所选）、⌘A（全选）；返回是否由卡片处理
    func handleTextPickCommand(_ command: PanelCommand) -> Bool {
        guard isTextPickOpen else { return false }
        switch command {
        case .paste, .pasteAlternate: pastePickedWords()
        case .copyOnly, .copyPickedWords: copyPickedWords()
        case .selectAllWords: textPick.toggleAll()
        default: return false
        }
        return true
    }

    /// 粘贴所选（P9）：与条目粘贴同一投递段；没有选取时提示音
    func pastePickedWords() {
        guard let request = textPick.request, let onPastePicked else {
            NSSound.beep()
            return
        }
        onPastePicked(request)
    }

    /// 复制所选并留在面板，底栏轻提示「已复制」（P9）；没有选取时提示音
    func copyPickedWords() {
        guard let request = textPick.request else {
            NSSound.beep()
            return
        }
        guard onCopyPicked?(request) == true else {
            NSSound.beep()
            showToast(.error(TextPickCopy.copyFailed))
            return
        }
        showToast(.info(TextPickCopy.copied(characters: textPick.resultLength), symbolName: "checkmark"))
    }

    /// 没有可拆分的文字：提示音 + 底栏提示（同「贴到屏幕」「翻译」对不支持类型的处理）
    private func rejectTextPick() {
        NSSound.beep()
        showToast(.info(TextPickCopy.noText, symbolName: "nosign"))
    }
}
