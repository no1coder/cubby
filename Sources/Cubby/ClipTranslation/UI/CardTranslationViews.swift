import CubbyCore
import SwiftUI

/// 卡片上与翻译有关的装饰（原型 cardHTML）：「译」角标、译文行、⌥↩ 行内进度 / 问题、按住 ⌥ 的译文预览
struct CardTranslationDecoration: Equatable {
    /// 已缓存译文的语言（非空时显示「译」角标）
    let cachedLanguages: [String]
    /// 卡片上的译文行（开启「在卡片上显示译文」或只因译文命中搜索时）
    let line: TranslationLine?
    let inline: InlineTranslation?
    /// 行内问题上的按钮
    let inlineAction: InlineTranslationAction?
    let peek: TranslationPeek?
    /// ⌥ 是否正按着（预览尾注用）
    var isOptionHeld = false

    var isEmpty: Bool {
        cachedLanguages.isEmpty && line == nil && inline == nil && peek == nil
    }
}

/// 卡片上的一行译文
struct TranslationLine: Equatable {
    let text: String
    let language: String
}

@MainActor
enum CardTranslationDecorations {
    /// 条目的装饰；功能不可用时为 nil
    static func make(
        for item: ClipItem, keywords: [String], viewModel: PanelViewModel
    ) -> CardTranslationDecoration? {
        guard let translation = viewModel.translation else { return nil }
        let entries = item.translations?.entries ?? []
        let inline = translation.inline.job.flatMap { $0.itemID == item.id ? $0 : nil }
        let peek = translation.peek.peek.flatMap { $0.itemID == item.id ? $0 : nil }
        let decoration = CardTranslationDecoration(
            cachedLanguages: entries.map(\.target),
            line: line(for: item, entries: entries, keywords: keywords, showsAlways: viewModel.showsTranslationOnCards),
            inline: inline,
            inlineAction: inline.flatMap { job in
                if case .failed(let issue) = job.phase { return translation.inline.action(for: issue) }
                return nil
            },
            peek: peek,
            // 只有正在预览的那张卡片关心 ⌥ 的状态：其他卡片的装饰不随 ⌥ 变化而重绘
            isOptionHeld: peek != nil && translation.peek.isOptionHeld)
        return decoration.isEmpty ? nil : decoration
    }

    /// 只因译文命中搜索时总是显示命中的那种语言（否则用户看不懂为何命中）；开关打开时显示界面语言（或最近一次）的译文首行
    private static func line(
        for item: ClipItem, entries: [ClipTranslation], keywords: [String], showsAlways: Bool
    ) -> TranslationLine? {
        guard !entries.isEmpty else { return nil }
        // 与搜索档位同一判定（SearchRelevance.matchedField == .translation）：有关键词只在译文里找得到
        if !keywords.isEmpty, let matched = item.translationMatch(keywords: keywords) {
            return line(matched, keywords: keywords)
        }
        guard showsAlways else { return nil }
        let interface = TranslationLanguageCatalog.interfaceLocale.identifier
        let chosen =
            entries.first { ClipLanguageMatch.isSameLanguage(interface, $0.target) }
            ?? entries.max { $0.createdAt < $1.createdAt }
        return chosen.map { line($0, keywords: keywords) }
    }

    /// 一行显示：换行换成空格，关键词靠后时从命中处截取
    private static func line(_ entry: ClipTranslation, keywords: [String]) -> TranslationLine {
        let text = entry.plainText.replacingOccurrences(of: "\n", with: " ")
        return TranslationLine(
            text: TextHighlighter.snippet(text, keywords: keywords, maxLength: 400), language: entry.target)
    }
}

// MARK: - 视图

/// 「译」角标（收藏星标旁）
struct TranslationChip: View {
    let languages: [String]

    var body: some View {
        Text(TranslationCopy.chip)
            .font(.system(size: FontSize.caption2, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.opacity(0.22)))
            .help(TranslationCopy.chipTooltip(languages))
            .accessibilityHidden(true)
    }
}

/// 卡片上的译文行：12pt 单行，左侧 2pt 强调色竖条（A10），搜索关键词高亮
struct TranslationLineView: View {
    let line: TranslationLine
    let keywords: [String]

    var body: some View {
        Text(TextHighlighter.attributed(line.text, keywords: keywords, tint: .accentColor))
            .font(.system(size: FontSize.footnote))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 7)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: TranslationCardMetrics.lineBarWidth)
            }
            .help(TranslationCopy.lineTooltip(line.language))
            .transition(.opacity)
    }
}

/// ⌥↩ 进行中：卡片元信息一行换成「翻译中 3/12 · esc 取消」
struct InlineProgressRow: View {
    let job: InlineTranslation

    var body: some View {
        HStack(spacing: 5) {
            TranslationSpinner()
            Text(TranslationCopy.inlineProgress(done: job.content.arrivedCount, total: job.content.translatableCount))
                .lineLimit(1)
        }
        .font(.system(size: FontSize.caption))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// ⌥↩ 的问题：橙色说明 + 操作按钮
struct InlineIssueRow: View {
    let issue: InlineTranslationIssue
    let plan: ClipTranslationPlan?
    let action: InlineTranslationAction?
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: FontSize.caption))
                .accessibilityHidden(true)
            Text(TranslationCopy.inlineIssue(issue, plan: plan))
                .lineLimit(1)
                .truncationMode(.tail)
            if let action {
                Button(title(action), action: perform)
                    .buttonStyle(.plain)
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .foregroundStyle(TranslationPalette.link)
                    .fixedSize()
                    .e2eAnchor("list.inlineAction")
            }
        }
        .font(.system(size: FontSize.caption))
        .foregroundStyle(TranslationPalette.warning)
        .accessibilityElement(children: .contain)
    }

    private func title(_ action: InlineTranslationAction) -> String {
        switch action {
        case .retry: TranslationCopy.retry
        case .translateAnyway: TranslationCopy.translateAnyway
        case .resolve(let failure): TranslationCopy.resolveAction(failure)
        }
    }
}

/// 按住 ⌥ 的译文预览：卡片内容淡入为流式译文（最多 6 行）
struct PeekContent: View {
    let peek: TranslationPeek
    let item: ClipItem
    let imageURL: URL?

    var body: some View {
        Group {
            if case .note(let text) = peek.phase {
                Label(text, systemImage: "exclamationmark.triangle")
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(TranslationPalette.warning)
            } else if item.kind == .image {
                imagePeek
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    // 卡片只显示 6 行，段落之间的空行不占行（与卡片正文一致）
                    Text(peek.content.shownPlainText.replacingOccurrences(of: "\n\n", with: "\n"))
                        .font(.system(size: FontSize.body))
                        .foregroundStyle(.primary)
                        .lineLimit(6)
                        .lineSpacing(1.5)
                    if peek.isStreaming { StreamingCaret() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private var imagePeek: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .overlay {
                AsyncThumbnail(url: peek.content.result?.imageURL ?? imageURL, maxPixelSize: 600, contentMode: .fill)
            }
            .overlay { if peek.isStreaming { ShimmerSweep(tint: Color.accentColor.opacity(0.3)) } }
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
    }
}

/// 预览时的元信息：「译文预览 · 简体中文 · 系统翻译 · 已缓存 · ↩ 粘贴这段译文」
struct PeekMetaRow: View {
    let peek: TranslationPeek
    let isOptionHeld: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "translate")
                .font(.system(size: FontSize.caption))
            Text(TranslationCopy.peekMeta(peek))
                .foregroundStyle(TranslationPalette.link)
            if let tail = TranslationCopy.peekTail(peek, isOptionHeld: isOptionHeld) {
                Text(verbatim: "· \(tail)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: FontSize.caption))
        .foregroundStyle(TranslationPalette.link)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// ⌥↩ 进行中：卡片上一层淡蓝底 + 扫光
struct InlineRunningOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.accentColor.opacity(0.06))
            .overlay(ShimmerSweep(tint: Color.accentColor.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .allowsHitTesting(false)
    }
}
