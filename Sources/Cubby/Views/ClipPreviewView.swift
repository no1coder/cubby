import AppKit
import SwiftUI
import CubbyCore

/// 预览内容是否挂载：只在预览面板显示期间为 true，由 PreviewPanelController 在 show / hide 时切换
@MainActor
@Observable
final class PreviewMount {
    var isActive = false
}

/// 详情区面板：空格预览或翻译卡（二者互斥）。预览显示期间随选中项实时更新，展示完整内容与元信息。
/// 面板隐藏时不挂载内容：不读取 selectedItem、不触发 onChange，
/// 选中项变化（每次按键、方向键）不再在后台排版预览文本、解码预览图
struct PreviewPanelView: View {
    let viewModel: PanelViewModel
    let mount: PreviewMount
    /// 选中项变化时通知面板调整高度
    let onItemChange: () -> Void

    var body: some View {
        if !mount.isActive {
            Color.clear
        } else if viewModel.detailPane == .translation, let translation = viewModel.translation {
            TranslationCardView(viewModel: viewModel, translation: translation, onLayoutChange: onItemChange)
        } else {
            MountedPreview(viewModel: viewModel, onItemChange: onItemChange)
        }
    }
}

/// 挂载后的预览内容，跟随选中项。挂载时的首个选中项不触发 onChange（高度已在 show 中测好）
private struct MountedPreview: View {
    let viewModel: PanelViewModel
    let onItemChange: () -> Void

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                ClipPreviewView(item: item, viewModel: viewModel)
                    .id(item.id)
            } else {
                Text("No item selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: viewModel.selectedItem?.id) { onItemChange() }
    }
}

struct ClipPreviewView: View {
    let item: ClipItem
    let viewModel: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // 与卡片同一尺寸（20pt）
            AppIconView(bundleID: item.source?.bundleID, fallbackSymbol: item.kind.symbolName)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.source?.name ?? TextStats.unknownSource)
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                Text(TimeFormatting.absolute(item.createdAt))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(item.kind.displayName, systemImage: item.kind.symbolName)
                .font(.system(size: FontSize.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 14)
        .frame(height: PreviewMetrics.headerHeight)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch item.payload {
        case .text(let text):
            switch item.kind {
            case .link: LinkPreview(url: text.trimmingCharacters(in: .whitespacesAndNewlines))
            case .color: ColorPreview(hex: text.trimmingCharacters(in: .whitespacesAndNewlines))
            default: TextPreview(text: text, keywords: viewModel.keywords)
            }
        case .image(let ref):
            ImagePreview(url: viewModel.imageURL(for: item), ref: ref)
        case .files(let paths):
            FilesPreview(paths: paths)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(statistics)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if item.kind == .link || item.kind == .file || item.kind == .image {
                Button("Open") { viewModel.open(item) }
                    .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                    // 文件全部不存在时打开只会提示音，直接置灰
                    .disabled(item.kind == .file && FileAvailability.allMissing(item.filePaths))
            }
            if item.kind == .image {
                Button("Pin to Screen") { viewModel.pin(item) }
                    .buttonStyle(CapsuleButtonStyle(isPrimary: false))
            }
            Button("Paste") { viewModel.paste(item) }
                .buttonStyle(CapsuleButtonStyle())
        }
        .padding(.horizontal, 14)
        .frame(height: PanelMetrics.footerHeight)
    }

    /// 页脚统计：给出类型徽标之外的信息（文本的长度与行数、链接的协议与域名、颜色的不透明度等）
    private var statistics: String {
        switch item.payload {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch item.kind {
            case .link: return Self.linkStatistics(trimmed)
            case .color: return ColorText.parse(trimmed).map(ColorFormats.opacityDescription) ?? item.kind.displayName
            default: return textStatistics(text)
            }
        case .image(let ref):
            return String(
                localized: "\(ref.width) × \(ref.height) pixels · PNG",
                comment: "Image preview statistics: width × height in pixels"
            )
        case .files(let paths):
            return TextStats.fileCount(paths.count)
        }
    }

    private func textStatistics(_ text: String) -> String {
        let lines = max(text.prefix(TextPreview.maxCharacters).split(whereSeparator: \.isNewline).count, 1)
        // 以间隔号分隔的统计项列表（不是句子）
        let parts = [
            TextStats.lengthDescription(text),
            String(localized: "\(lines) lines", comment: "Number of lines of a text item"),
            item.formatsName != nil ? String(localized: "Rich text", comment: "Text item has formatting") : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// 「https · example.com · 234 字符」
    private static func linkStatistics(_ link: String) -> String {
        let url = URL(string: link)
        return [url?.scheme?.lowercased(), url?.host, TextStats.lengthDescription(link)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - 各类型预览

private struct TextPreview: View {
    static let maxCharacters = 20_000

    let text: String
    let keywords: [String]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isCode = TextHeuristics.looksLikeCode(text)
        let head = text.prefix(Self.maxCharacters)
        let shown = head.endIndex < text.endIndex ? String(head) + "\n…" : text
        ScrollView {
            Text(TextHighlighter.attributed(shown, keywords: keywords, tint: isCode ? .yellow : .accentColor))
                .font(isCode ? .system(size: FontSize.footnote, design: .monospaced) : .system(size: FontSize.body))
                .foregroundStyle(isCode ? Color.white.opacity(0.9) : Color.primary)
                .lineSpacing(isCode ? 2 : 4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(isCode ? 14 : 16)
                .background {
                    if isCode {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(CardPalette.code(colorScheme).background)
                    }
                }
                .padding(isCode ? 12 : 0)
        }
    }
}

private struct LinkPreview: View {
    let url: String

    var body: some View {
        let parsed = ItemOpener.safeWebURL(url)
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                .accessibilityHidden(true)
            Text(parsed?.host ?? url)
                .font(.system(size: FontSize.title, weight: .semibold))
            Text(url)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                .textSelection(.enabled)
            if parsed != nil {
                KeyHint(
                    keys: "⌘O",
                    label: String(localized: "Open in browser", comment: "Shortcut hint in the link preview")
                )
            }
        }
        .padding(28)
    }
}

/// 图片按宽高比完整显示，不放大到超过原始像素尺寸（小图标不会被拉糊）
private struct ImagePreview: View {
    let url: URL?
    let ref: ImageRef

    var body: some View {
        AsyncThumbnail(url: url, maxPixelSize: 1600)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .frame(maxWidth: CGFloat(max(ref.width, 1)), maxHeight: CGFloat(max(ref.height, 1)))
            .padding(PreviewMetrics.imageInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FilesPreview: View {
    let paths: [String]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    FileRow(path: path)
                }
            }
            .padding(12)
        }
    }
}

private struct FileRow: View {
    let path: String

    private var parentFolder: String {
        ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: path)
        HStack(spacing: 10) {
            Image(nsImage: ImageCache.shared.fileIcon(path: path))
                .resizable()
                .frame(width: 34, height: 34)
                .opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: FontSize.body, weight: .medium))
                    .strikethrough(!exists)
                    .truncationMode(.middle)
                // 父目录与卡片一样用「~」缩写，不在界面上露出完整的用户目录
                Text(exists ? parentFolder : String(localized: "File no longer exists"))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(exists ? .secondary : Color.red.opacity(0.8))
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer()
            if exists {
                Button {
                    ItemOpener.revealInFinder([path])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show in Finder")
                .accessibilityLabel(Text("Show in Finder"))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
