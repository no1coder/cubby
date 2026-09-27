import AppKit
import CubbyCore

/// 覆盖层的结束与暂停：出口（立即回调或后台导出）、存储前的暂停（§9.4）、
/// 截图翻译「去设置」「下载语言」时的暂停与恢复（行为与存储对话框相同）
extension ScreenshotOverlayController {
    // MARK: - 暂停 / 恢复（截图翻译）

    /// 「去设置」「下载语言」回来：与存储对话框取消一样恢复覆盖层，值得时自动重试
    func resumeAfterResolving(retry: Bool) {
        resume()
        if retry {
            send(.translation(.retry))
        }
    }

    /// 「去设置」「下载语言」：像存储对话框那样暂停（隐藏但保留会话），交给协调器去解决
    func suspendForResolving(_ failure: TranslationFailure) {
        guard !isFinished else { return }
        isFinished = true
        isSuspended = true
        hide()
        delegate?.overlay(self, didRequestResolving: failure)
    }

    // MARK: - 结束

    func finish(_ outcome: ScreenshotOutcome) {
        // ⌘T 时开关在「译文」：提取结果就是译文（同「复制译文」），不再 OCR
        if outcome == .extractText, let text = translatedTextForExport, let selection = session.selection {
            deliverImmediately(.translatedText(text, selection: selection))
            return
        }
        switch outcome {
        case .cancel: deliverImmediately(.cancel)
        case .copyColor(let text): deliverImmediately(.copyColor(text))
        case .captureWindow(let id, let shadow):
            deliverImmediately(.captureWindow(windowID: id, includeShadow: shadow))
        case .save: requestSave()
        case .copy, .pin, .extractText: export(outcome)
        }
    }

    /// 立即隐藏并回调结果（不需要导出的出口）
    func deliverImmediately(_ result: ScreenshotResult) {
        guard !isFinished else { return }
        tearDown()
        deliver(result)
    }

    func deliver(_ result: ScreenshotResult) {
        guard !didDeliver else { return }
        didDeliver = true
        delegate?.overlay(self, didFinishWith: result)
    }

    /// 先隐藏覆盖层让用户马上看到桌面，再在后台导出；失败回调 `.failed(.exportFailed)`
    private func export(_ outcome: ScreenshotOutcome) {
        guard !isFinished else { return }
        guard let job = exportJob(for: outcome) else {
            deliverImmediately(.failed(.exportFailed))
            return
        }
        tearDown()
        exportTask = Task { [self] in
            #if DEBUG
            if debugExportDelay > .zero {
                try? await Task.sleep(for: debugExportDelay)
            }
            #endif
            let output = await Task.detached(priority: .userInitiated) { job.run() }.value
            exportTask = nil
            guard !Task.isCancelled else { return }
            deliver(Self.result(for: outcome, output: output))
        }
    }

    /// 存储（§9.4）：与其他出口一样先隐藏覆盖层、后台导出，但保留窗口与会话；
    /// 导出完成后请求存储位置，由协调器决定 resume()（对话框取消）或 dismiss()（已存储）
    private func requestSave() {
        guard !isFinished else { return }
        guard let job = exportJob(for: .save) else {
            deliverImmediately(.failed(.exportFailed))
            return
        }
        isFinished = true
        isSuspended = true
        hide()
        exportTask = Task { [self] in
            #if DEBUG
            if debugExportDelay > .zero {
                try? await Task.sleep(for: debugExportDelay)
            }
            #endif
            let output = await Task.detached(priority: .userInitiated) { job.run() }.value
            exportTask = nil
            guard !Task.isCancelled, isSuspended else { return }
            guard let export = output.export else {
                tearDown()
                deliver(.failed(.exportFailed))
                return
            }
            delegate?.overlay(self, didRequestSave: export)
        }
    }

    private func exportJob(for outcome: ScreenshotOutcome) -> OverlayExportJob? {
        guard let selection = session.selection,
            let screenID = session.screenID ?? capture.topology.screen(containing: selection.center)?.id,
            let frame = capture.frame(for: screenID)
        else { return nil }
        return OverlayExportJob(
            frame: frame,
            selection: selection,
            document: session.document,
            translation: session.exportedTranslation,
            pixelated: pixelation.image(for: screenID).map(OverlayImage.init),
            needsCleanCrop: outcome == .extractText
        )
    }

    private static func result(for outcome: ScreenshotOutcome, output: OverlayExportJob.Output) -> ScreenshotResult {
        guard let export = output.export else { return .failed(.exportFailed) }
        switch outcome {
        case .pin: return .pin(export)
        case .extractText:
            guard let clean = output.clean else { return .failed(.exportFailed) }
            return .extractText(export, clean: clean)
        default: return .copy(export)
        }
    }
}

extension CGRect {
    fileprivate var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
