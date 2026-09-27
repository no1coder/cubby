import CubbyCore
import SwiftUI

/// 翻译卡底栏（36pt，原型 tcFootHTML）：左侧统计或短暂提示，右侧「复制译文 ⌘C」「存为新条目 ⌘S」「粘贴译文 ↩」
struct TranslationCardFooter: View {
    let card: TranslationCard
    let item: ClipItem
    let controller: TranslationCardController
    let flash: TranslationFlash?
    let targetName: String?
    let isRecordingPaused: Bool

    var body: some View {
        HStack(spacing: 8) {
            statistics
                .font(.system(size: FontSize.caption))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            Button(TranslationCopy.copyButton) { controller.copy() }
                .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                .disabled(!isReady)
                .help(TranslationCopy.copyTooltip)
                .e2eAnchor("card.copy")
            Button(TranslationCopy.saveButton) { controller.save() }
                .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                .disabled(!isReady || isRecordingPaused)
                .help(isRecordingPaused ? TranslationCopy.pausedTooltip : TranslationCopy.saveTooltip)
                .e2eAnchor("card.save")
            Button {
                controller.paste(.standard)
            } label: {
                HStack(spacing: 5) {
                    if card.pendingPaste != nil {
                        TranslationSpinner()
                    }
                    Text(card.pendingPaste != nil ? TranslationCopy.pasteWhenDoneButton : TranslationCopy.pasteButton)
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(!isReady && !card.phase.isWorking)
            .help(TranslationCopy.pasteTooltip(app: targetName))
            .e2eAnchor("card.paste")
        }
        .padding(.horizontal, 14)
        .frame(height: PanelMetrics.footerHeight)
    }

    private var isReady: Bool {
        card.phase == .done
    }

    @ViewBuilder
    private var statistics: some View {
        if let flash {
            HStack(spacing: 5) {
                Image(systemName: flash.isWarning ? "exclamationmark.triangle" : "checkmark")
                    .font(.system(size: FontSize.caption, weight: .semibold))
                Text(flash.message)
            }
            .foregroundStyle(flash.isWarning ? AnyShapeStyle(.secondary) : AnyShapeStyle(TranslationPalette.ok))
            .transition(.opacity)
        } else {
            Text(statisticsText)
                .foregroundStyle(.secondary)
        }
    }

    /// 原型 tcStats
    private var statisticsText: String {
        let target = card.displayedLanguages.target
        switch card.phase {
        case .done:
            let size =
                card.isImage
                ? TranslationCopy.imageBlockCount(card.content.imageBlocks.count)
                : TranslationCopy.length(of: card.content.result?.plainText ?? "", language: target)
            return [size, timing].joined(separator: " · ")
        case .streaming where !card.isImage:
            let length = TranslationCopy.length(of: card.content.shownPlainText, language: target)
            return "\(TranslationCopy.translating) \(length)"
        case .holding:
            return TranslationCopy.holdingDetail
        case .waiting:
            if card.isImage { return TranslationCopy.recognizingOnDevice }
            return card.plan?.sendsTextOffDevice == true ? TranslationCopy.sentWaiting : TranslationCopy.translating
        case .streaming:
            return TranslationCopy.translating
        default:
            return sourceSummary
        }
    }

    private var timing: String {
        guard let result = card.content.result, !result.fromCache, let elapsed = card.elapsed else {
            return TranslationCopy.cached
        }
        return TranslationCopy.timing(engine: TranslationCopy.shortEngineName(result.engineName), elapsed: elapsed)
    }

    /// 「英语 · 1,234 个字符」「英语 · 800 × 500 像素」
    private var sourceSummary: String {
        let source = card.plan?.detectedSource.map(TranslationCopy.languageName)
        let detail: String =
            switch item.payload {
            case .text(let text): TextStats.lengthDescription(text)
            case .image(let ref):
                String(
                    localized: "\(ref.width) × \(ref.height) pixels",
                    comment: "Translation card footer: image size in pixels")
            case .files(let paths): TextStats.fileCount(paths.count)
            }
        return [source, detail].compactMap { $0 }.joined(separator: " · ")
    }
}
