import SwiftUI
import CubbyCore

/// 按类型渲染的卡片主体
struct CardContent: View {
    let item: ClipItem
    let style: CardStyle
    let palette: CardPalette
    let keywords: [String]
    let imageURL: URL?

    private static let snippetLength = 400
    private static let maxCodeLines = 4
    /// 图片卡固定高度：加载前后不跳动，列表节奏稳定
    private static let imageHeight: CGFloat = 96
    private static let fileIconSize: CGFloat = 30

    var body: some View {
        switch item.payload {
        case .text(let text):
            textContent(text)
        case .image(let ref):
            imageContent(ref)
        case .files(let paths):
            fileContent(paths)
        }
    }

    /// 先用透明占位确定尺寸，再把图片放进 overlay：fill 模式下宽幅图片的理想宽度
    /// 会超过内容列，若直接参与布局会把整张卡片撑宽、越过面板内边距
    private func imageContent(_ ref: ImageRef) -> some View {
        // 竖长图（如长网页截图）顶部对齐，看得到开头而不是中段。
        // 请求尺寸与记录时预生成的缩略图同一规则（ImageThumbnail），命中小文件解码不到 1ms
        let isTall = ImageThumbnail.isTall(width: ref.width, height: ref.height)
        let pixelSize = ImageThumbnail.pixelSize(width: ref.width, height: ref.height)
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.imageHeight)
            .overlay(alignment: isTall ? .top : .center) {
                AsyncThumbnail(url: imageURL, maxPixelSize: pixelSize, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
    }

    @ViewBuilder
    private func textContent(_ text: String) -> some View {
        switch (item.kind, style) {
        case (.link, _):
            linkContent(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case (.color, _):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                .font(.system(size: FontSize.title, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.primary)
        case (_, .code):
            // 代码逐行截断而不折行，保留原有缩进结构
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(codeLines(text).enumerated()), id: \.offset) { _, line in
                    Text(TextHighlighter.attributed(line, keywords: keywords, tint: .yellow))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: FontSize.footnote, design: .monospaced))
            .foregroundStyle(palette.primary)
        default:
            Text(
                TextHighlighter.attributed(
                    TextHighlighter.snippet(
                        String(text.prefix(Self.snippetLength * 2))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .collapsingBlankLines,
                        keywords: keywords,
                        maxLength: Self.snippetLength
                    ),
                    keywords: keywords,
                    tint: .accentColor
                )
            )
            .font(.system(size: FontSize.body))
            .foregroundStyle(palette.primary)
            .lineLimit(3)
            .lineSpacing(1.5)
        }
    }

    /// 链接：域名 + 完整地址（来源浏览器图标已表明是网页，不再重复链接图标）
    private func linkContent(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(URL(string: url)?.host ?? url)
                .font(.system(size: FontSize.body, weight: .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Text(TextHighlighter.attributed(url, keywords: keywords, tint: .accentColor))
                .font(.system(size: FontSize.caption))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// 文件名中间截断（与访达一致，保留扩展名）；文件已不存在时名称加删除线、路径换成说明
    private func fileContent(_ paths: [String]) -> some View {
        let missingNote = FileAvailability.missingDescription(paths)
        let folder = ((paths.first ?? "") as NSString).deletingLastPathComponent.abbreviatingWithTildeInPath
        return HStack(spacing: 8) {
            Image(nsImage: ImageCache.shared.fileIcon(path: paths.first ?? ""))
                .resizable()
                .frame(width: Self.fileIconSize, height: Self.fileIconSize)
                .opacity(missingNote == nil ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(TextHighlighter.attributed(item.title, keywords: keywords, tint: .accentColor))
                    .font(.system(size: FontSize.body, weight: .medium))
                    .strikethrough(missingNote != nil)
                    .foregroundStyle(missingNote == nil ? palette.primary : palette.secondary)
                    .truncationMode(.middle)
                Text(missingNote ?? folder)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .truncationMode(missingNote == nil ? .head : .tail)
            }
            .lineLimit(1)
        }
    }

    /// 代码取前几行，保留缩进，只去掉首尾空行
    private func codeLines(_ text: String) -> [String] {
        let lines = String(text.prefix(Self.snippetLength))
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: .newlines)
        let shown = Array(lines.prefix(Self.maxCodeLines))
        return lines.count > Self.maxCodeLines ? shown + ["…"] : shown
    }
}

/// 文件条目指向的文件是否还在
enum FileAvailability {
    /// 全部文件都已不存在（常见情况下第一个文件就存在，只需一次 stat）
    static func allMissing(_ paths: [String]) -> Bool {
        !paths.isEmpty && paths.allSatisfy { !FileManager.default.fileExists(atPath: $0) }
    }

    /// 全部文件都已不存在时的说明，否则为 nil
    static func missingDescription(_ paths: [String]) -> String? {
        guard allMissing(paths) else { return nil }
        return paths.count > 1
            ? String(localized: "Files no longer exist", comment: "File item whose files were all deleted or moved")
            : String(localized: "File no longer exists", comment: "Error when copying a file item")
    }
}

/// 文本长度描述：小文本精确计数，大文本按体积显示，避免每次渲染遍历整段字符
enum TextStats {
    private static let exactCountLimit = 20_000

    static func lengthDescription(_ text: String) -> String {
        let bytes = text.utf8.count
        guard bytes > exactCountLimit else {
            return String(localized: "\(text.count) characters", comment: "Length of a text item")
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return String(localized: "\(size) of text", comment: "Size of a large text item, e.g. “1.2 MB of text”")
    }

    static func fileCount(_ count: Int) -> String {
        String(localized: "\(count) files", comment: "Number of files in a file item")
    }

    /// 来源应用未知时的占位
    static var unknownSource: String {
        String(localized: "Unknown source", comment: "Source app of an item is unknown")
    }
}

private extension String {
    var abbreviatingWithTildeInPath: String {
        (self as NSString).abbreviatingWithTildeInPath
    }

    /// 连续的空行合并为一个换行：卡片只显示 3 行，不该浪费在空行上
    var collapsingBlankLines: String {
        replacingOccurrences(of: #"(?:[ \t]*\r?\n){2,}"#, with: "\n", options: .regularExpression)
    }
}
