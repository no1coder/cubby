import AppKit

public enum PasteboardWriteError: Error, Equatable {
    case imageUnavailable
    case filesMissing
    /// 系统拒绝写入剪贴板（writeObjects / setString 返回 false）
    case writeRejected
}

/// 将历史条目写回系统剪贴板
public enum PasteboardWriter {
    /// - Parameter formats: 文本条目的富文本格式（键为 UTI）；传空表示仅写入纯文本
    public static func write(
        _ item: ClipItem,
        imageURL: URL?,
        formats: [String: Data] = [:],
        to pasteboard: NSPasteboard
    ) throws {
        switch item.payload {
        case .text(let text):
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            for (type, data) in formats.sorted(by: { $0.key < $1.key }) {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }

        case .image:
            guard let imageURL,
                let png = try? Data(contentsOf: imageURL),
                let rep = NSBitmapImageRep(data: png)
            else { throw PasteboardWriteError.imageUnavailable }
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            // 部分老应用只识别 TIFF
            if let tiff = rep.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }

        case .files(let paths):
            let urls =
                paths
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { throw PasteboardWriteError.filesMissing }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls)
        }
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
    }
}
