import AppKit

// 译文的写入入口（docs/CLIP-TRANSLATION-DESIGN.md §4、§0.1 A2 / A11）。
// 与条目写入一样附带 markerType：监听器跳过，复制 / 粘贴译文不会自动入历史。

public extension PasteboardWriter {
    /// 纯文本译文
    static func write(text: String, to pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw PasteboardWriteError.writeRejected }
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
    }

    /// 富文本条目的译文：RTF + HTML + 纯文本。plainText 由调用方给出（与缓存的拼接规则一致），
    /// 富文本导出失败时退回只写纯文本
    static func write(richText: AttributedString, plainText: String, to pasteboard: NSPasteboard) throws {
        let exported = RichTextExport.data(from: richText)
        pasteboard.clearContents()
        guard pasteboard.setString(plainText, forType: .string) else { throw PasteboardWriteError.writeRejected }
        if let exported {
            pasteboard.setData(exported.rtf, forType: .rtf)
            pasteboard.setData(exported.html, forType: .html)
        }
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
    }

    /// 译后图片（带 DPI 的 PNG 文件）：PNG + 按需 TIFF；文件缺失或不是 PNG 时抛 imageUnavailable，且不改动剪贴板
    static func write(pngAt url: URL, to pasteboard: NSPasteboard) throws {
        guard let png = try? Data(contentsOf: url) else { throw PasteboardWriteError.imageUnavailable }
        try ScreenshotPasteboard.write(png: png, to: pasteboard)
    }
}
