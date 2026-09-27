import AppKit
import CubbyCore

/// 截图翻译的浮层：翻译条内容、卷帘分隔线、按住空格的提示、悬停气泡
extension OverlayScreenView {
    /// 翻译条内容变化才刷新 SwiftUI
    func updateTranslationBar(_ model: TranslationBarModel?) {
        guard let model, model != translationBarModel else { return }
        translationBarModel = model
        translationBar.update(rootView: TranslationBar(model: model) { [onTranslation] in onTranslation(.bar($0)) })
    }

    /// 卷帘、提示与气泡只画在选区所在的屏幕
    func renderTranslationChrome(_ chrome: OverlayTranslationChrome) {
        renderWipe(chrome.wipe)
        renderPeekChip(chrome.peekSelection)
        renderBubble(chrome.bubble)
    }

    /// 鼠标是否落在卷帘分隔线的命中区（此时光标为左右调整）
    func isOverWipeHandle(_ global: CGPoint) -> Bool {
        wipeDivider.isHandle(at: wipeDivider.convert(space.viewPoint(global), from: self))
    }

    private func renderWipe(_ wipe: OverlayTranslationChrome.Wipe?) {
        guard let wipe, space.intersects(wipe.selection) else {
            wipeDivider.isHidden = true
            return
        }
        let frame = alignedViewRect(space.pixelAligned(wipe.selection.intersection(space.screen.frame)))
        wipeDivider.show(
            frame: frame, lineX: space.pixelRounded(wipe.x), selectionMinX: space.globalPoint(fromView: frame.origin).x,
            isFocused: wipe.isFocused)
    }

    private func renderPeekChip(_ selection: CGRect?) {
        guard let selection, space.intersects(selection) else {
            peekChip.isHidden = true
            return
        }
        let rect = space.viewRect(selection)
        let size = peekChip.frame.size
        peekChip.setFrameOrigin(
            CGPoint(x: (rect.midX - size.width / 2).rounded(), y: (rect.minY + OverlayTokens.peekChipTop).rounded()))
        peekChip.isHidden = false
    }

    private func renderBubble(_ model: OverlayTranslationChrome.Bubble?) {
        guard let model, space.intersects(model.block) else {
            bubble.isHidden = true
            return
        }
        bubble.show(
            model.text, block: space.viewRect(model.block), selection: space.viewRect(model.selection), within: bounds)
    }

    static let emptyTranslationBar = TranslationBarModel(
        languagePair: "", languages: [], engine: nil, content: .progress(""))
}

#if DEBUG
/// 仅调试构建：端到端测试读取翻译条、卷帘与气泡
extension OverlayScreenView {
    /// 显示中的翻译条（全局点）
    var debugTranslationBarFrame: CGRect? {
        translationBar.isShown ? space.globalRect(fromView: translationBar.frame) : nil
    }

    /// 翻译条上某个元素的中心（全局点）
    func debugTranslationBarCenter(of item: TranslationBarItem) -> CGPoint? {
        guard let bar = debugTranslationBarFrame, let frame = TranslationBarDebugFrames.shared.frames[item] else {
            return nil
        }
        return CGPoint(x: bar.minX + frame.midX, y: bar.minY + frame.midY)
    }

    /// 卷帘拖柄的中心（全局点）；卷帘未显示时为 nil
    var debugWipeKnobCenter: CGPoint? {
        guard !wipeDivider.isHidden else { return nil }
        let knob = wipeDivider.debugKnobCenter
        return space.globalPoint(fromView: wipeDivider.convert(knob, to: self))
    }

    var debugPeekChipVisible: Bool {
        !peekChip.isHidden
    }

    var debugBubbleText: String? {
        bubble.debugText
    }
}
#endif
