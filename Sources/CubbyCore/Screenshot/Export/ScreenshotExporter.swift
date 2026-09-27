import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 一次导出的结果：选区裁剪 + 标注后的原生像素位图及其 PNG
///
/// `@unchecked Sendable` 的理由：CGImage 不可变，其余字段都是值类型。
public struct ScreenshotExport: @unchecked Sendable {
    /// 原生像素位图（sRGB）
    public let image: CGImage
    /// PNG 编码，带 DPI = 72 × scale
    public let png: Data
    /// 像素尺寸
    public let pixelSize: CGSize
    /// 导出时的选区（全局点）
    public let selection: CGRect
    /// 选区所在屏幕
    public let screen: CaptureScreen

    public init(image: CGImage, png: Data, pixelSize: CGSize, selection: CGRect, screen: CaptureScreen) {
        self.image = image
        self.png = png
        self.pixelSize = pixelSize
        self.selection = selection
        self.screen = screen
    }
}

/// 导出失败的原因
public enum ScreenshotExportError: Error, Equatable, Sendable {
    /// 选区为空或完全不在帧内
    case emptySelection
    /// 无法创建位图 context
    case contextUnavailable
    /// PNG 编码失败
    case encodingFailed
}

/// 把「选区裁剪 + 译文 + 标注」渲染为屏幕原生像素的位图并编码 PNG
///
/// 像素矩形 = `(selection − screen.origin) × scale` 向外取整，再与帧位图相交。
/// 层级：冻结帧 → 译文层（截图翻译，由调用方按「原文 | 译文」开关决定是否传入）→ 用户标注。
/// 纯函数、无共享状态，可在任意线程调用。
public enum ScreenshotExporter {
    /// PNG 的基准 DPI（1x 屏）
    private static let baseDPI: CGFloat = 72
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// 裁剪 + 译文 + 标注 → 原生像素 PNG；PNG 写入 DPI = 72 × scale
    /// - Parameter translation: 译文块（契约扩展，默认空 = 原文版本）；画在冻结帧之上、标注之下
    public static func export(
        frame: FrozenFrame,
        selection: CGRect,
        document: AnnotationDocument,
        translation: [TranslatedBlock] = [],
        pixelatedFrame: CGImage?
    ) throws(ScreenshotExportError) -> ScreenshotExport {
        let pixelRect = try pixelRect(frame: frame, selection: selection)
        let context = try makeContext(size: pixelRect.size, like: frame.image)
        drawFrame(frame.image, cropping: pixelRect, into: context)

        let screen = frame.screen
        let environment = RenderEnvironment(
            origin: CGPoint(
                x: screen.frame.minX + pixelRect.minX / screen.scale,
                y: screen.frame.minY + pixelRect.minY / screen.scale
            ),
            scale: screen.scale,
            targetPixelSize: pixelRect.size,
            pixelatedFrame: pixelatedFrame,
            frameOrigin: screen.frame.origin
        )
        if !translation.isEmpty {
            TranslationPainter.draw(translation, in: context, environment: environment)
        }
        AnnotationRenderer.draw(document, in: context, environment: environment)

        guard let image = context.makeImage() else { throw .contextUnavailable }
        guard let png = pngData(image, scale: screen.scale) else { throw .encodingFailed }
        return ScreenshotExport(image: image, png: png, pixelSize: pixelRect.size, selection: selection, screen: screen)
    }

    /// 仅裁剪、不叠加标注（供 OCR）；返回独立的位图，不引用整帧
    public static func crop(frame: FrozenFrame, selection: CGRect) throws(ScreenshotExportError) -> CGImage {
        let pixelRect = try pixelRect(frame: frame, selection: selection)
        let context = try makeContext(size: pixelRect.size, like: frame.image)
        drawFrame(frame.image, cropping: pixelRect, into: context)
        guard let image = context.makeImage() else { throw .contextUnavailable }
        return image
    }

    /// PNG 编码并写入 DPI = 72 × scale，让 Preview 等按点尺寸显示
    public static func pngData(_ image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { return nil }
        let dpi = baseDPI * scale
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - 内部

    /// 选区在帧位图中的像素矩形（已与位图范围相交）；为空时抛 emptySelection
    private static func pixelRect(frame: FrozenFrame, selection: CGRect) throws(ScreenshotExportError) -> CGRect {
        guard !selection.isNull, !selection.isEmpty else { throw .emptySelection }
        let imageBounds = CGRect(x: 0, y: 0, width: frame.image.width, height: frame.image.height)
        let rect = frame.screen.pixelRect(selection).intersection(imageBounds)
        guard !rect.isNull, !rect.isEmpty else { throw .emptySelection }
        return rect
    }

    /// 与帧相同色彩空间（非 RGB 时用 sRGB）的 RGBA 8 位预乘位图
    private static func makeContext(size: CGSize, like image: CGImage) throws(ScreenshotExportError) -> CGContext {
        let space =
            image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space,
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: bitmapInfo
            )
        else { throw .contextUnavailable }
        return context
    }

    /// 把帧中 pixelRect 区域 1:1 画到 context 的 (0, 0)
    private static func drawFrame(_ image: CGImage, cropping pixelRect: CGRect, into context: CGContext) {
        // CoreGraphics 默认 y 向上：位图第 pixelRect.minY 行（自上而下）要落在 context 顶部
        let drawRect = CGRect(
            x: -pixelRect.minX,
            y: pixelRect.maxY - CGFloat(image.height),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        context.interpolationQuality = .none
        context.draw(image, in: drawRect)
    }
}
