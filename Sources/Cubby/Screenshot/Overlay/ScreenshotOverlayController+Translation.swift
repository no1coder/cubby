import AppKit
import CubbyCore

/// 截图翻译：翻译条与卷帘的操作 → 会话事件 / 委托（复制译文、去设置 / 下载语言）
extension ScreenshotOverlayController {
    /// ⌘T 提取文字时的结果：开关在「译文」且已有译文时为全部译文（同「复制译文」）；否则 nil，照常 OCR
    var translatedTextForExport: String? {
        session.exportedTranslation.isEmpty ? nil : session.translatedText
    }

    func translationInput(_ input: OverlayTranslationInput) {
        switch input {
        case .bar(let action):
            barAction(action)
        case .moveWipe(let x):
            translation?.wipeDragged(cursor: session.cursor)
            send(.translation(.moveWipe(x)))
        case .stepWipe(let rightward):
            guard case .split(let x) = session.translationDisplay, let selection = session.selection else { return }
            let step = selection.width * ScreenshotSession.wipeSmallStep
            send(.translation(.moveWipe(x + (rightward ? step : -step))))
        }
    }

    private func barAction(_ action: TranslationBarAction) {
        switch action {
        case .showTranslation(let shows):
            send(.translation(.showTranslation(shows)))
        case .setWipe(let enabled):
            send(.translation(.setWipe(enabled)))
        case .copy:
            guard let text = session.translatedText, let selection = session.selection else { return }
            delegate?.overlay(self, didRequestCopyingText: text, selection: selection)
        case .retry:
            send(.translation(.retry))
        case .retranslateSelection:
            send(.translation(.retranslateSelection))
        case .resolve(let failure):
            suspendForResolving(failure)
        case .chooseLanguage(let code):
            // 选定即写回设置（持久化），再沿用已识别的块重译
            translation?.services.provider.targetLanguage = code
            send(.translation(.changeTarget(code)))
        }
    }
}

#if DEBUG
/// 仅调试构建：端到端测试直接触发翻译条操作（语言选单是系统菜单，合成事件无法驱动它的跟踪循环）
extension ScreenshotOverlayController {
    func debugTranslationBarAction(_ action: TranslationBarAction) {
        barAction(action)
    }
}
#endif
