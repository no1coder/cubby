import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

/// 截图结果写入剪贴板；都带 `PasteboardReader.markerType`，监听器因此跳过（历史由调用方直接记录）
public enum ScreenshotPasteboard {
    /// PNG + TIFF（部分老应用只认 TIFF）+ markerType；PNG 无效时抛 `PasteboardWriteError.imageUnavailable`，
    /// 此时不改动剪贴板；系统拒绝写入时抛 `.writeRejected`
    ///
    /// PNG 与标记立即写入；TIFF 只登记为「承诺」，由 `LazyTIFFProvider` 在有应用读取时才解码生成，
    /// 避免完成截图时在主线程上解码整帧并生成未压缩 TIFF（6K 帧约多占 160 MB）。
    public static func write(png: Data, to pasteboard: NSPasteboard) throws {
        guard isPNG(png) else { throw PasteboardWriteError.imageUnavailable }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([imageItem(png: png, tiffProvider: LazyTIFFProvider(png: png))]) else {
            throw PasteboardWriteError.writeRejected
        }
    }

    /// 纯文本（取色结果、OCR 文字）+ markerType；返回是否写入成功
    @discardableResult
    public static func write(text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let written = pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
        return written
    }

    /// 一个剪贴板项：PNG 与标记为实际数据，TIFF 由 provider 惰性提供。
    /// AppKit 持有 provider，直到 TIFF 已提供或剪贴板被清空（`pasteboardFinishedWithDataProvider`）后释放
    static func imageItem(png: Data, tiffProvider: LazyTIFFProvider) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setDataProvider(tiffProvider, forTypes: [.tiff])
        item.setData(Data(), forType: PasteboardReader.markerType)
        return item
    }

    /// 只读取文件头判断是否为可用的 PNG（不解码像素）
    private static func isPNG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) as String? == UTType.png.identifier,
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return properties[kCGImagePropertyPixelWidth] != nil && properties[kCGImagePropertyPixelHeight] != nil
    }
}

/// 按需把 PNG 转成 TIFF 的剪贴板数据提供者；只持有不可变的 PNG 与加锁计数，因此是 Sendable
final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider, Sendable {
    private let png: Data
    private let generated = OSAllocatedUnfairLock(initialState: 0)

    init(png: Data) {
        self.png = png
    }

    /// 已生成 TIFF 的次数（测试用于验证惰性）
    var generatedCount: Int {
        generated.withLock { $0 }
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .tiff, let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation else { return }
        generated.withLock { $0 += 1 }
        item.setData(tiff, forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        // 无需额外清理：AppKit 在此之后释放 provider，连同它持有的 PNG
    }
}
