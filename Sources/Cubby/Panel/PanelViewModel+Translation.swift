import AppKit
import CubbyCore

// 视图模型里的翻译路由（docs/CLIP-TRANSLATION-DESIGN.md §1.3、§1.5）：翻译逻辑在 ClipTranslationController，
// 这里只把按键、右键菜单与选中项变化转给它，并维护详情区（预览 / 翻译卡）

extension PanelViewModel {
    var isTranslationCardOpen: Bool {
        detailPane == .translation
    }

    /// ⌘T：先关帮助；翻译卡打开时关闭（从预览切来的回到预览）；否则打开（预览打开时切到翻译卡）
    func toggleTranslationCard() {
        if isShowingHelp { toggleHelp() }
        if isTranslationCardOpen {
            closeTranslationCard()
            return
        }
        guard let item = selectedItem else { return }
        openTranslation(for: item)
    }

    /// 对指定条目打开翻译卡（右键菜单、⌘T）
    func openTranslation(for item: ClipItem) {
        guard let translation else {
            NSSound.beep()
            return
        }
        select(item)
        if let reason = translation.card.open(item, fromPreview: isPreviewVisible || cardOpenedFromPreview) {
            rejectTranslation(reason)
            return
        }
        translation.inline.cancel()
        translation.peek.cancel()
        setDetailPane(.translation)
    }

    /// 关闭翻译卡：从预览切来的回到预览
    func closeTranslationCard() {
        let backToPreview = cardOpenedFromPreview
        translation?.card.close()
        setDetailPane(backToPreview ? .preview : nil)
    }

    /// ⌥↩：翻译卡打开时粘贴卡片上的译文；按住 ⌥ 预览时粘贴显示的内容；否则行内翻译后粘贴
    func translateAndPasteSelected() {
        if isShowingHelp { toggleHelp() }
        guard let translation else {
            NSSound.beep()
            return
        }
        if isTranslationCardOpen {
            translation.card.paste(.standard)
            return
        }
        if translation.pasteShownPeek() { return }
        guard let item = selectedItem else { return }
        translateAndPaste(item)
    }

    /// 对指定条目行内翻译后粘贴（右键菜单、⌥↩）。翻译卡开着时交给卡片：卡片先跟到这一条，
    /// 再「完成后粘贴」（云端引擎停留中也立即发送）——只发一次，不另起行内任务
    func translateAndPaste(_ item: ClipItem) {
        guard let translation else {
            NSSound.beep()
            return
        }
        if isTranslationCardOpen {
            select(item)
            translation.card.follow(item)
            translation.card.paste(.standard)
            return
        }
        select(item)
        translation.peek.cancel()
        if let reason = translation.inline.start(item) {
            rejectTranslation(reason)
        }
    }

    /// 右键「复制译文」：复制该条已缓存的译文，留在面板
    func copyCachedTranslation(_ item: ClipItem) {
        guard let translation, let result = translation.cachedResult(for: item) else {
            NSSound.beep()
            return
        }
        let request = TranslationPasteRequest(item: item, result: result, style: .standard, origin: .menu)
        let copied = translation.onCopy?(request) ?? false
        showToast(
            copied
                ? .info(TranslationCopy.copiedFlash(isImage: item.kind == .image), symbolName: "checkmark")
                : .error(TranslationCopy.copyFailed))
    }

    /// 翻译卡打开时的 ↩ / ⇧↩ / ⌘↩ / ⌘C / ⌘S / ← →；返回是否由卡片处理
    func handleCardCommand(_ command: PanelCommand) -> Bool {
        guard isTranslationCardOpen, let card = translation?.card else { return false }
        switch command {
        case .paste: card.paste(.standard)
        case .pasteAlternate: card.paste(.plainText)
        case .copyOnly, .copyTranslation: card.copy()
        case .saveTranslation: card.save()
        case .stepTranslationView(let step): card.step(step)
        default: return false
        }
        return true
    }

    /// 选中项变化（PanelView 观察后调用）：翻译卡跟随；⌥↩ 与预览属于原条目，取消
    func selectionDidChange() {
        guard let translation else { return }
        translation.selectionChanged(to: selectedItem)
        if isTranslationCardOpen, !translation.card.isOpen {
            setDetailPane(nil)
        }
    }

    /// ⌥ 单独按下 / 松开
    func optionKeyChanged(isDown: Bool) {
        translation?.optionChanged(isDown: isDown, canPeek: !isShowingHelp) { [weak self] in self?.selectedItem }
    }

    /// 按下鼠标（⌥ 点按等）：与按下其他键一样取消按住 ⌥ 的计时、停留与预览
    func pointerPressed() {
        translation?.keyPressed(isOptionReturn: false, isEscape: false)
    }

    /// 任意按键按下（取消按住 ⌥ 的预览；⌥↩ 除外）
    func keyPressed(isOptionReturn: Bool, isEscape: Bool) {
        translation?.keyPressed(isOptionReturn: isOptionReturn, isEscape: isEscape)
    }

    private var cardOpenedFromPreview: Bool {
        translation?.card.card?.openedFromPreview ?? false
    }

    /// 不支持的类型：提示音 + 底栏提示（同「贴到屏幕」对非图片条目的处理）
    private func rejectTranslation(_ reason: ClipTranslationUnsupportedReason) {
        NSSound.beep()
        showToast(.info(TranslationCopy.unsupportedTitle(reason), symbolName: "nosign"))
    }
}
