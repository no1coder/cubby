import SwiftUI
import CubbyCore

/// 单条剪贴板记录的卡片：左侧来源图标，中间内容，右侧时间与快捷键
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

    private static let quickPasteCount = 9

    var body: some View {
        let style = CardStyle(item: item)
        let palette = style.palette(colorScheme, increasedContrast: contrast == .increased)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)

        HStack(alignment: .top, spacing: 10) {
            AppIconView(
                bundleID: item.source?.bundleID,
                size: PanelMetrics.sourceIconSize,
                fallbackSymbol: item.kind.symbolName,
                fallbackTint: palette.isCustom ? palette.primary : nil
            )
            // 图标中心与正文首行中心对齐
            .offset(y: -1)
            mainColumn(style: style, palette: palette)
            trailingColumn(palette)
        }
        .padding(.horizontal, PanelMetrics.inset)
        .padding(.vertical, 10)
        .background(shape.fill(palette.background))
        .overlay(CardHoverLayer(isSelected: isSelected))
        .overlay { if translation?.inline?.isRunning == true { InlineRunningOverlay() } }
        .overlay(shape.strokeBorder(palette.stroke, lineWidth: 0.5))
        .overlay(selectionRing(palette))
        .shadow(color: .black.opacity(isSelected ? 0.12 : 0.06), radius: isSelected ? 4 : 2, y: 1)
        .contentShape(shape)
        .animation(.easeOut(duration: Motion.selection), value: isSelected)
        // VoiceOver 把整张卡片当作一个可操作的按钮（动作由 CardList 提供）
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(
            Text("Press Return to paste, or Space to preview.", comment: "VoiceOver hint for a clipboard card")
        )
    }

    // MARK: - 组成部分

    /// 内容（按住 ⌥ 时换成译文预览）、译文行、元信息与 ⌥↩ 的行内问题
    private func mainColumn(style: CardStyle, palette: CardPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let peek = translation?.peek {
                PeekContent(peek: peek, item: item, imageURL: imageURL)
                    .e2eAnchor("list.peek.\(item.id)")
            } else {
                CardContent(item: item, style: style, palette: palette, keywords: keywords, imageURL: imageURL)
                    .transition(.opacity)
            }
            if let line = translation?.line, translation?.peek == nil {
                TranslationLineView(line: line, keywords: keywords)
                    .e2eAnchor("list.line.\(item.id)")
            }
            metadataRow(palette)
            if let job = translation?.inline, case .failed(let issue) = job.phase {
                InlineIssueRow(
                    issue: issue, plan: job.plan, action: translation?.inlineAction, perform: onInlineAction
                )
                .e2eAnchor("list.inlineIssue.\(item.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: Motion.fade), value: translation?.peek != nil)
    }

    /// 元信息一行：⌥↩ 进行中换成进度，按住 ⌥ 时换成预览说明
    @ViewBuilder
    private func metadataRow(_ palette: CardPalette) -> some View {
        if let peek = translation?.peek {
            PeekMetaRow(peek: peek, isOptionHeld: translation?.isOptionHeld ?? false)
        } else if let job = translation?.inline, job.isRunning {
            InlineProgressRow(job: job)
                .e2eAnchor("list.inline.\(item.id)")
        } else {
            Text(metadata)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
    }

    private func trailingColumn(_ palette: CardPalette) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                if let languages = translation?.cachedLanguages, !languages.isEmpty {
                    TranslationChip(languages: languages)
                        .e2eAnchor("list.chip.\(item.id)")
                }
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: FontSize.caption2))
                        .foregroundStyle(palette.isCustom ? palette.secondary : Color.yellow)
                }
                Text(TimeFormatting.relative(item.createdAt))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if index < Self.quickPasteCount {
                // 与上方时间同一字形（系统默认 design），只保留等宽数字
                Text(verbatim: "⌘\(index + 1)")
                    .font(.system(size: FontSize.caption, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 选中态：2pt 强调色外环；彩色 / 代码卡再加一圈白色内环，保证在任何底色上可辨
    @ViewBuilder
    private func selectionRing(_ palette: CardPalette) -> some View {
        if isSelected {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            shape.strokeBorder(Color.accentColor, lineWidth: 2)
            if palette.isCustom {
                RoundedRectangle(cornerRadius: Radius.card - 2, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    .padding(2)
            }
        }
    }

    /// 来源 · 详情（以间隔号分隔的元信息列表，不是句子）
    private var metadata: String {
        let detail: String? =
            switch item.payload {
            case .text(let text) where item.kind == .text: TextStats.lengthDescription(text)
            case .text: nil
            case .image(let ref): "\(ref.width) × \(ref.height)"
            case .files(let paths): paths.count > 1 ? TextStats.fileCount(paths.count) : nil
            }
        return [sourceName, detail].compactMap { $0 }.joined(separator: " · ")
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

/// 悬停高亮叠层：自带悬停状态，鼠标进出只重绘这一层
private struct CardHoverLayer: View {
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.primary.opacity(opacity))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: Motion.fade), value: isHovered)
    }

    private var opacity: Double {
        guard isHovered, !isSelected else { return 0 }
        return colorScheme == .dark ? 0.06 : 0.04
    }
}

/// 卡片展示样式
enum CardStyle {
    case standard
    case code
    case color(RGBAColor)

    init(item: ClipItem) {
        if item.kind == .color, let color = item.text.flatMap(ColorText.parse) {
            self = .color(color)
        } else if item.kind == .text, let text = item.text, TextHeuristics.looksLikeCode(text) {
            self = .code
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
