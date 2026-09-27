import CoreGraphics

/// 位图中非透明像素的外接矩形。纯净窗口截图带阴影时，ScreenCaptureKit 输出在右下留有
/// 多余的透明画布，据此裁掉（设计文档 §9.3）
public enum AlphaBounds {
    /// 裁到非透明像素的外接矩形；整张透明或无法读取时为 nil
    public static func cropped(_ image: CGImage) -> CGImage? {
        bounds(of: image).flatMap { image.cropping(to: $0) }
    }

    /// 像素坐标（左上原点）；从四条边向内找第一行 / 列含 alpha > 0 的像素，整张透明时为 nil
    public static func bounds(of image: CGImage) -> CGRect? {
        guard let alpha = alphaChannel(of: image) else { return nil }
        let width = image.width
        let height = image.height
        func isClear(row: Int, columns: Range<Int>) -> Bool {
            columns.allSatisfy { alpha[row * width + $0] == 0 }
        }
        func isClear(column: Int, rows: Range<Int>) -> Bool {
            rows.allSatisfy { alpha[$0 * width + column] == 0 }
        }
        guard let top = (0..<height).first(where: { !isClear(row: $0, columns: 0..<width) }) else { return nil }
        let bottom = (top..<height).last { !isClear(row: $0, columns: 0..<width) } ?? top
        let rows = top..<(bottom + 1)
        let left = (0..<width).first { !isClear(column: $0, rows: rows) } ?? 0
        let right = (left..<width).last { !isClear(column: $0, rows: rows) } ?? left
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// 每个像素的 alpha（行 0 为图像顶部）；先画进 RGBA 位图再取 alpha 通道
    private static func alphaChannel(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return (0..<(width * height)).map { bytes[$0 * 4 + 3] }
    }
}
