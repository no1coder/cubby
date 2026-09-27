import AppKit
import CubbyCore

/// 截图翻译在协调器里的部分：可用性、「去设置」「下载语言」的暂停 / 恢复、复制译文
extension ScreenshotCoordinator {
    /// 覆盖层做截图翻译所需的服务：macOS 26+ 且 App 提供了翻译与识别（设计文档 §2 可用条件）
    var translationServices: ScreenshotTranslationServices? {
        guard #available(macOS 26, *), let translation, let translationRecognizer else { return nil }
        return ScreenshotTranslationServices(provider: translation, recognizer: translationRecognizer)
    }

    /// 「去设置」「下载语言」：覆盖层已暂停（同存储对话框），等 provider 处理完再恢复，值得时自动重试。
    /// 期间再按截图快捷键不开始新截图也不取消（见 hotKeyPressedWhileActive）
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestResolving failure: TranslationFailure) {
        guard case .presenting(let presentation) = state, presentation.overlay === overlay, let provider = translation
        else {
            overlay.resumeAfterResolving(retry: false)
            return
        }
        state = .suspended(presentation, .resolvingTranslation)
        layoutChangedWhileSuspended = false
        // 设置窗口会激活 Cubby：会话结束时把前台还给截图前的应用
        focusToRestore = focusToRestore ?? FocusRestorer.capture()
        logger.info("Resolving a translation failure: \(String(describing: failure), privacy: .public)")
        Task { [weak self] in
            let retry = await provider.resolve(failure)
            self?.resolveFinished(retry: retry, overlay: overlay)
        }
    }

    /// 处理完：覆盖层带着原来的会话回来；期间屏幕布局变了则结束会话（冻结帧与新布局对不上）
    private func resolveFinished(retry: Bool, overlay: any ScreenshotOverlayPresenting) {
        guard case .suspended(let presentation, .resolvingTranslation) = state, presentation.overlay === overlay else {
            overlay.dismiss()
            if case .idle = state { restoreFocus() }
            return
        }
        guard !layoutChangedWhileSuspended else {
            state = .idle
            overlay.dismiss()
            restoreFocus()
            warn(
                String(
                    localized: "Screen layout changed",
                    comment: "HUD when a screenshot is cancelled by a display change"))
            return
        }
        state = .presenting(presentation)
        overlay.resumeAfterResolving(retry: retry)
    }

    /// 翻译条「复制译文」：覆盖层保持打开
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestCopyingText text: String, selection: CGRect) {
        output.copyText(
            text, success: TranslationBarText.copiedTranslation, anchor: ScreenshotOutputService.anchor(for: selection))
    }

    /// ⌘T 时开关在「译文」：复制译文（覆盖层已关闭）
    func copyExtractedTranslation(_ text: String, selection: CGRect) {
        output.copyText(
            text, success: String(localized: "Text copied", comment: "HUD after copying recognized text"),
            anchor: ScreenshotOutputService.anchor(for: selection))
    }
}
