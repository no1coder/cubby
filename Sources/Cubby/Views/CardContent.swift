import SwiftUI
import CubbyCore

/// 文本、代码与文件卡的主体（链接、颜色与图片卡见 Cards/TypedCardContent.swift）
struct CardContent: View {
    let item: ClipItem
    let style: CardStyle
    let palette: CardPalette
    let keywords: [String]

    private static let snippetLength = 400
    private static let maxCodeLines = 4
    private static let fileIconSize: CGFloat = 30
    /// 14pt 正文的行高约 1.5（21pt）：在系统默认行高之上再加的间距
    private static let bodyLineSpacing: CGFloat = 4
    /// 12pt 代码的行高约 1.6
    private static let codeLineSpacing: CGFloat = 4

    var body: some View {
        switch item.payload {
        case .text(let text):
            textContent(text)
        case .files(let paths):
            fileContent(paths)
        case .image:
            EmptyView()
        }
    }

    @ViewBuilder
    private func textContent(_ text: String) -> some View {
        if case .code(let language) = style {
            // 代码逐行截断而不折行，保留原有缩进结构；关键字 / 字符串 / 类型三色，搜索命中再叠黄色底
            VStack(alignment: .leading, spacing: Self.codeLineSpacing) {
                ForEach(Array(codeLines(text).enumerated()), id: \.offset) { _, line in
                    Text(CodeColoring.attributed(line, language: language, keywords: keywords))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: FontSize.footnote, design: .monospaced))
            .foregroundStyle(palette.primary)
        } else {
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
            .font(.system(size: FontSize.callout))
            .foregroundStyle(palette.primary)
            .lineLimit(3)
            .lineSpacing(Self.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 文件名中间截断（与访达一致，保留扩展名）；文件已不存在时名称加删除线、路径换成说明
    private func fileContent(_ paths: [String]) -> some View {
        let missingNote = FileAvailability.missingDescription(paths)
        let parent = ((paths.first ?? "") as NSString).deletingLastPathComponent.abbreviatingWithTildeInPath
        let folder = paths.count > 1 ? "\(TextStats.fileCount(paths.count)) · \(parent)" : parent
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
