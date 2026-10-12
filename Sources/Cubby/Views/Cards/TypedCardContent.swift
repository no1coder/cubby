import CubbyCore
import SwiftUI

/// 链接卡：38pt 字母底板 + 域名 · 时间 + 页面标题（复制时带来的才有）+ 完整地址（中间截断）。
/// 不联网取网站图标：底板是域名首字母，颜色由域名决定，同一网站每次一致
struct LinkCardContent: View {
    let item: ClipItem
    let url: String
    /// 复制时随链接带来的页面标题；没有时不显示这一行
    let title: String?
    let palette: CardPalette
    let keywords: [String]
    let accessories: CardAccessories

    private static let tileSize: CGFloat = 38

    var body: some View {
        let host = LinkBadge.host(of: url) ?? url
        HStack(alignment: .top, spacing: 11) {
            LinkTile(host: host, size: Self.tileSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    CardSourceLine(name: host, date: item.createdAt, palette: palette)
                    Spacer(minLength: 4)
                    accessories
                }
                if let title {
                    Text(TextHighlighter.attributed(title, keywords: keywords, tint: .accentColor))
                        .font(.system(size: FontSize.body, weight: .medium))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                }
                Text(TextHighlighter.attributed(url, keywords: keywords, tint: .accentColor))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// 域名首字母底板：深浅外观下都用同一个由域名决定的颜色
struct LinkTile: View {
    let host: String
    let size: CGFloat

    var body: some View {
        Text(verbatim: LinkBadge.letter(for: host))
            .font(.system(size: FontSize.display, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                    .fill(Color(hue: LinkBadge.hue(for: host), saturation: 0.55, brightness: 0.72))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            )
            .accessibilityHidden(true)
    }
}

/// 颜色卡：左侧 40pt 色块图标 + HEX（18pt 等宽）+ 「rgb(...) · 来源 · 时间」；卡片底色仍是该颜色
struct ColorCardContent: View {
    let item: ClipItem
    let text: String
    let color: RGBAColor
    let palette: CardPalette
    let accessories: CardAccessories

    private static let swatchSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eyedropper")
                .font(.system(size: FontSize.title, weight: .medium))
                .foregroundStyle(palette.primary)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .background(
                    RoundedRectangle(cornerRadius: Radius.cardImage, style: .continuous)
                        .fill(palette.primary.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.cardImage, style: .continuous)
                                .strokeBorder(palette.primary.opacity(0.25), lineWidth: 1))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    .font(.system(size: FontSize.display, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(verbatim: details)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            accessories
        }
    }

    private var details: String {
        [
            ColorFormats.rgbValue(color), item.source?.name ?? TextStats.unknownSource,
            TimeFormatting.relative(item.createdAt),
        ]
        .joined(separator: " · ")
    }
}

/// 图片卡：缩略图内缩 6pt、圆角 11、高 128；下方一行「来源 · 尺寸」与 ⌘N
struct ImageCardContent: View {
    let item: ClipItem
    let ref: ImageRef
    let imageURL: URL?
    let palette: CardPalette
    let accessories: CardAccessories

    private static let captionIconSize: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            thumbnail
                .padding([.top, .horizontal], PanelMetrics.cardImageInset)
            HStack(spacing: 7) {
                AppIconView(
                    bundleID: item.source?.bundleID, size: Self.captionIconSize, fallbackSymbol: item.kind.symbolName)
                Text(item.source?.name ?? TextStats.unknownSource)
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .foregroundStyle(palette.primary.opacity(0.86))
                    .lineLimit(1)
                Text(verbatim: "\(ref.width) × \(ref.height)")
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                accessories
            }
            .padding(.top, PanelMetrics.imageCaptionPadding.top)
            .padding(.bottom, PanelMetrics.imageCaptionPadding.bottom)
            .padding(.horizontal, PanelMetrics.cardPadding.leading)
        }
    }

    /// 先用透明占位确定尺寸，再把图片放进 overlay：fill 模式下宽幅图片的理想宽度会超过卡片，
    /// 直接参与布局会把整张卡片撑宽。竖长图顶部对齐，看得到开头而不是中段
    private var thumbnail: some View {
        let isTall = ImageThumbnail.isTall(width: ref.width, height: ref.height)
        let pixelSize = ImageThumbnail.pixelSize(width: ref.width, height: ref.height)
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.cardImageHeight)
            .overlay(alignment: isTall ? .top : .center) {
                AsyncThumbnail(url: imageURL, maxPixelSize: pixelSize, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardImage, style: .continuous))
    }
}
