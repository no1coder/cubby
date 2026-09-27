#if DEBUG
import AppKit
import CubbyCore

/// README 截图的截图翻译演示：`Cubby --scenario screenshot:translate-demo[:compare]`（仅调试构建，macOS 26）。
///
/// 冻结帧是展示场景的合成桌面（英文原文、不带标注）加预置选区，上屏即按 ⇧⌘T。识别用真实的
/// VisionTranslationRecognizer，排版与绘制也是正式流程；只有引擎换成按手写译文返回的 DemoTranslationEngine，
/// 不联网、不读写用户的翻译设置。compare 为 true 时译完打开卷帘对比（分隔线在选区中央）
extension ScreenshotCoordinator {
    func startTranslationDemo(compare: Bool) {
        guard #available(macOS 26, *) else {
            logger.error("The translation demo needs macOS 26")
            return
        }
        translation = DemoTranslationProvider()
        translationRecognizer = VisionTranslationRecognizer()
        debugAfterPresent = { overlay in
            guard let overlay = overlay as? ScreenshotOverlayController else { return }
            overlay.send(.command(.translate))
            if compare { Self.openWipeWhenTranslated(overlay) }
        }
        let source = ShowcaseFrameSource(screens: ScreenTopologyProvider.screens(), copy: .translationSource)
        begin(frameSource: source, windowSource: source) { [logger] capture in
            let session = ShowcaseSession.selectionOnly(topology: capture.topology)
            if session == nil {
                logger.error("Translation demo needs a screen")
            }
            return session
        }
    }

    /// 等翻译完成（最多 15 秒）后打开卷帘对比
    private static func openWipeWhenTranslated(_ overlay: ScreenshotOverlayController) {
        Task { @MainActor [weak overlay] in
            for _ in 0..<150 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let overlay, !overlay.debugIsFinished else { return }
                if let run = overlay.session.translation, run.hasResult, !run.status.isBusy {
                    overlay.send(.translation(.setWipe(true)))
                    return
                }
            }
        }
    }
}
#endif
