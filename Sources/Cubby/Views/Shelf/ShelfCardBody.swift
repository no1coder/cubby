import CubbyCore
import SwiftUI

/// 横条方卡的中部内容：文本摘录、链接预览块、整幅图片、代码、居中的 HEX、文件图标与名称
struct ShelfCardBody: View {
    let item: ClipItem
    let style: CardStyle
    let palette: CardPalette
    let keywords: [String]
    let imageSource: ClipImageSource?

    private static let snippetLength = 300
    private static let maxLines = 7
    private static let maxCodeLines = 7
    private static let lineSpacing: CGFloat = 4
    private static let linkBlockHeight: CGFloat = 70
    private static let linkTileSize: CGFloat = 34
    private static let fileIconSize = CGSize(width: 46, height: 56)

    var body: some View {
        switch (item.payload, style) {
        case (.image(let ref), _):
            image(ref)
        case (.files(let paths), _):
            files(paths)
        case (.text(let text), .color):
            Text(verbatim: text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                .font(.system(size: FontSize.shelfHex, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (.text(let text), .code(let language)):
            code(text, language: language)
        case (.text(let text), _) where item.kind == .link:
            link(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case (.text(let text), _):
            Text(TextHighlighter.attributed(snippet(text), keywords: keywords, tint: .accentColor))
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(palette.primary)
                .lineSpacing(Self.lineSpacing)
                .lineLimit(Self.maxLines)
                .padding(ShelfMetrics.contentPadding)
        }
    }

    private func snippet(_ text: String) -> String {
        TextHighlighter.snippet(
            String(text.prefix(Self.snippetLength * 2)).trimmingCharacters(in: .whitespacesAndNewlines),
            keywords: keywords, maxLength: Self.snippetLength)
    }

    /// 整幅铺满（竖长图顶部对齐）
    private func image(_ ref: ImageRef) -> some View {
        let isTall = ImageThumbnail.isTall(width: ref.width, height: ref.height)
        return Color.clear
            .overlay(alignment: isTall ? .top : .center) {
                AsyncThumbnail(
                    source: imageSource, maxPixelSize: ImageThumbnail.pixelSize(width: ref.width, height: ref.height),
                    contentMode: .fill)
            }
            .clipped()
    }

    /// 预览块（域名首字母底板，不联网取网站图标）+ 域名 + 页面标题（有则显示）+ 地址
    private func link(_ url: String) -> some View {
        let host = LinkBadge.host(of: url) ?? url
        return VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: Self.linkBlockHeight)
                .overlay { LinkTile(host: host, size: Self.linkTileSize) }
            Text(verbatim: host)
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            if let title = item.linkTitle {
                Text(TextHighlighter.attributed(title, keywords: keywords, tint: .accentColor))
                    .font(.system(size: FontSize.caption, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
            }
            Text(TextHighlighter.attributed(url, keywords: keywords, tint: .accentColor))
                .font(.system(size: FontSize.caption))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(ShelfMetrics.contentPadding)
    }

    private func code(_ text: String, language: CodeLanguage?) -> some View {
        let lines = String(text.prefix(Self.snippetLength * 2))
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: .newlines)
            .prefix(Self.maxCodeLines)
        return VStack(alignment: .leading, spacing: Self.lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(CodeColoring.attributed(line, language: language, keywords: keywords))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: FontSize.caption, design: .monospaced))
        .foregroundStyle(palette.primary)
        .padding(ShelfMetrics.contentPadding)
    }

    /// 居中的文件图标 + 名称（中间截断，保留扩展名）；文件已不存在时名称加删除线
    private func files(_ paths: [String]) -> some View {
        let missing = FileAvailability.allMissing(paths)
        return VStack(spacing: 8) {
            Image(nsImage: ImageCache.shared.fileIcon(path: paths.first ?? ""))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.fileIconSize.width, height: Self.fileIconSize.height)
                .opacity(missing ? 0.4 : 1)
            Text(TextHighlighter.attributed(item.title, keywords: keywords, tint: .accentColor))
                .font(.system(size: FontSize.footnote, weight: .medium))
                .strikethrough(missing)
                .foregroundStyle(missing ? palette.secondary : palette.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(ShelfMetrics.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 底部一行的元信息：文本为长度，链接为来源，图片为尺寸，代码为「来源 · 语言」，颜色为 rgb()，文件为所在文件夹
    static func metadata(for item: ClipItem, style: CardStyle) -> String {
        let source = item.source?.name ?? TextStats.unknownSource
        switch (item.payload, style) {
        case (.image(let ref), _):
            return "\(ref.width) × \(ref.height)"
        case (.files(let paths), _):
            if let missing = FileAvailability.missingDescription(paths) { return missing }
            let folder = ((paths.first ?? "") as NSString).deletingLastPathComponent
            return (folder as NSString).abbreviatingWithTildeInPath
        case (_, .color(let rgba)):
            return ColorFormats.rgbValue(rgba)
        case (_, .code(let language)):
            return [source, language?.displayName].compactMap { $0 }.joined(separator: " · ")
        case (.text(let text), _) where item.kind == .text:
            return TextStats.lengthDescription(text)
        default:
            return source
        }
    }
}
