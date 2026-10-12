import SwiftUI
import CubbyCore

/// 单条剪贴板记录的卡片（docs/UI-UPGRADE-PLAN.md 第 1 节）：文本与代码卡为「头部一行 + 正文」，
/// 链接、颜色、文件与图片卡各有自己的排布（悬停工具条由 CardList 叠在手势之上，见 CardHoverChrome）
struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let keywords: [String]
    let imageURL: URL?
    /// 翻译相关的装饰（「译」角标、译文行、⌥↩ 行内进度、按住 ⌥ 预览）；功能不可用或没有装饰时为 nil
    var translation: CardTranslationDecoration?
    /// ⌥↩ 行内问题上的按钮
    var onInlineAction: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let style = CardStyle(item: item)
        let palette = style.palette(colorScheme, increasedContrast: contrast == .increased)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)

        layout(style: style, palette: palette)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { if translation?.inline?.isRunning == true { InlineRunningOverlay() } }
            .clipShape(shape)
            .cardSurface(palette, isSelected: isSelected)
            .contentShape(shape)
            .animation(.easeOut(duration: Motion.selection), value: isSelected)
            .animation(.easeOut(duration: Motion.fade), value: translation?.peek != nil)
            // VoiceOver 把整张卡片当作一个可操作的按钮（动作由 CardList 提供）
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(
                Text("Press Return to paste, or Space to preview.", comment: "VoiceOver hint for a clipboard card")
            )
    }

    // MARK: - 排布

    @ViewBuilder
    private func layout(style: CardStyle, palette: CardPalette) -> some View {
        if case .image(let ref) = item.payload, translation?.peek == nil {
            // 图片卡：缩略图贴近卡片边缘，自己处理内边距
            VStack(alignment: .leading, spacing: 0) {
                ImageCardContent(
                    item: item, ref: ref, imageURL: imageURL, palette: palette, accessories: accessories(palette))
                extraRows(palette)
                    .padding(.horizontal, PanelMetrics.cardPadding.leading)
                    .padding(.bottom, hasExtraRows ? PanelMetrics.cardPadding.bottom : 0)
            }
        } else {
            VStack(alignment: .leading, spacing: PanelMetrics.cardRowSpacing) {
                mainContent(style: style, palette: palette)
                extraRows(palette)
            }
            .padding(padding(for: style))
        }
    }

    @ViewBuilder
    private func mainContent(style: CardStyle, palette: CardPalette) -> some View {
        if let peek = translation?.peek {
            CardHeader(item: item, palette: palette, accessories: accessories(palette))
            PeekContent(peek: peek, item: item, imageURL: imageURL)
                .e2eAnchor("list.peek.\(item.id)")
        } else {
            switch (item.payload, style) {
            case (.text(let text), .color(let rgba)):
                ColorCardContent(
                    item: item, text: text, color: rgba, palette: palette, accessories: accessories(palette))
            case (.text(let text), _) where item.kind == .link:
                LinkCardContent(
                    item: item, url: text.trimmingCharacters(in: .whitespacesAndNewlines), title: item.linkTitle,
                    palette: palette, keywords: keywords, accessories: accessories(palette))
            case (.files, _):
                HStack(alignment: .center, spacing: 8) {
                    CardContent(item: item, style: style, palette: palette, keywords: keywords)
                    Spacer(minLength: 4)
                    accessories(palette)
                }
            default:
                CardHeader(item: item, palette: palette, accessories: accessories(palette, style: style))
                CardContent(item: item, style: style, palette: palette, keywords: keywords)
                    .transition(.opacity)
            }
        }
    }

    /// 译文行、⌥↩ 进度或按住 ⌥ 的说明、⌥↩ 的行内问题
    @ViewBuilder
    private func extraRows(_ palette: CardPalette) -> some View {
        if let line = translation?.line, translation?.peek == nil {
            TranslationLineView(line: line, keywords: keywords)
                .e2eAnchor("list.line.\(item.id)")
        }
        if let peek = translation?.peek {
            PeekMetaRow(peek: peek, isOptionHeld: translation?.isOptionHeld ?? false)
        } else if let job = translation?.inline, job.isRunning {
            InlineProgressRow(job: job)
                .e2eAnchor("list.inline.\(item.id)")
        }
        if let job = translation?.inline, case .failed(let issue) = job.phase {
            InlineIssueRow(issue: issue, plan: job.plan, action: translation?.inlineAction, perform: onInlineAction)
                .e2eAnchor("list.inlineIssue.\(item.id)")
        }
    }

    private var hasExtraRows: Bool {
        guard let translation else { return false }
        return translation.line != nil || translation.inline != nil || translation.peek != nil
    }

    private func accessories(_ palette: CardPalette, style: CardStyle = .standard) -> CardAccessories {
        CardAccessories(
            item: item, index: index, isSelected: isSelected, palette: palette,
            translatedLanguages: translation?.cachedLanguages ?? [], badge: badge(for: style))
    }

    /// 代码卡的语言徽标：认不出语言时为「代码」
    private func badge(for style: CardStyle) -> String? {
        guard case .code(let language) = style else { return nil }
        return language?.displayName
            ?? String(localized: "Code", comment: "Badge on a code card whose language is not recognized")
    }

    /// 颜色卡左侧色块离边缘更近一些
    private func padding(for style: CardStyle) -> EdgeInsets {
        guard case .color = style, translation?.peek == nil else { return PanelMetrics.cardPadding }
        return PanelMetrics.colorCardPadding
    }

    private var sourceName: String {
        item.source?.name ?? TextStats.unknownSource
    }

    /// 「来源 · 标题 · 相对时间」（文件已不存在时在标题后注明；有缓存译文时注明「已翻译」）
    private var accessibilityLabel: String {
        let missingNote = item.kind == .file ? FileAvailability.missingDescription(item.filePaths) : nil
        let translated = translation?.cachedLanguages.isEmpty == false ? TranslationCopy.translatedAccessibility : nil
        return [sourceName, item.title, missingNote, translated, TimeFormatting.relative(item.createdAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// 卡片展示样式
enum CardStyle {
    case standard
    /// 代码与识别出的语言（认不出时为 nil）
    case code(CodeLanguage?)
    case color(RGBAColor)

    /// 只在视图里构造（主线程），语言识别结果走主线程缓存
    @MainActor
    init(item: ClipItem) {
        if item.kind == .color, let color = item.text.flatMap(ColorText.parse) {
            self = .color(color)
        } else if item.kind == .text, let text = item.text, TextHeuristics.looksLikeCode(text) {
            self = .code(CodeLanguageCache.language(of: text, hash: item.contentHash))
        } else {
            self = .standard
        }
    }

    func palette(_ scheme: ColorScheme, increasedContrast: Bool = false) -> CardPalette {
        switch self {
        case .standard: .standard(scheme, increasedContrast: increasedContrast)
        case .code: .code(scheme, increasedContrast: increasedContrast)
        case .color(let rgba): .color(rgba, scheme: scheme, increasedContrast: increasedContrast)
        }
    }
}

/// 代码语言识别的缓存（按内容哈希）：卡片在每次列表重算时都会重新求值，较长的代码识别一次约数毫秒
@MainActor
enum CodeLanguageCache {
    /// 超过这么多条时整体清空：历史上限内的代码卡不会接近这个数，清空只是兜底
    private static let limit = 1_000
    private static var languages: [String: CodeLanguage?] = [:]

    static func language(of text: String, hash: String) -> CodeLanguage? {
        if let cached = languages[hash] { return cached }
        if languages.count >= limit { languages.removeAll(keepingCapacity: true) }
        let language = CodeLanguage.detect(text)
        languages[hash] = language
        return language
    }
}
