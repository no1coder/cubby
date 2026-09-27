import CoreGraphics

/// 马赛克用的整帧像素化：每个 blockSize × blockSize 块取平均色（边缘不完整块按自身像素平均）
///
/// 纯 CPU、单次遍历、原地写回；线程安全（无共享状态），调用方应在后台线程执行。
public enum Pixelator {
    /// 马赛克块的最小像素边长
    public static let minimumBlockSize = 6

    private static let bytesPerPixel = 4
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// 像素化副本；blockSize = 1 返回原图，< 1 或无法创建位图时返回 nil
    public static func pixelated(_ image: CGImage, blockSize: Int) -> CGImage? {
        guard blockSize >= 1 else { return nil }
        guard blockSize > 1 else { return image }
        guard let context = makeContext(width: image.width, height: image.height, like: image) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        guard let data = context.data else { return nil }
        let buffer = PixelBuffer(
            pixels: data.bindMemory(to: UInt32.self, capacity: context.bytesPerRow / bytesPerPixel * image.height),
            width: image.width,
            height: image.height,
            pixelsPerRow: context.bytesPerRow / bytesPerPixel
        )
        buffer.averageBlocks(size: blockSize)
        return context.makeImage()
    }

    /// 马赛克块大小：max(6, 笔刷宽 × scale / 2)，四舍五入到整数像素
    public static func blockSize(forBrushWidth width: CGFloat, scale: CGFloat) -> Int {
        max(minimumBlockSize, Int((width * scale / 2).rounded()))
    }

    /// RGBA 8 位预乘位图；沿用原图的 RGB 色彩空间，否则用 sRGB
    private static func makeContext(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let space =
            image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: bitmapInfo
        )
    }
}

/// 位图像素的原地块平均（每个 UInt32 为内存顺序 R, G, B, A 的一个像素）
private struct PixelBuffer {
    let pixels: UnsafeMutablePointer<UInt32>
    let width: Int
    let height: Int
    let pixelsPerRow: Int

    func averageBlocks(size: Int) {
        let columns = (width + size - 1) / size
        var sums = [UInt64](repeating: 0, count: columns * 4)
        for top in stride(from: 0, to: height, by: size) {
            let rows = min(size, height - top)
            sums.withUnsafeMutableBufferPointer { sums in
                accumulate(top: top, rows: rows, size: size, into: sums)
                fill(top: top, rows: rows, size: size, from: sums)
            }
        }
    }

    /// 把一行块中每个块的四个通道分别求和
    private func accumulate(top: Int, rows: Int, size: Int, into sums: UnsafeMutableBufferPointer<UInt64>) {
        sums.update(repeating: 0)
        for row in top..<(top + rows) {
            let line = pixels + row * pixelsPerRow
            for column in 0..<sums.count / 4 {
                let start = column * size
                var red: UInt64 = 0
                var green: UInt64 = 0
                var blue: UInt64 = 0
                var alpha: UInt64 = 0
                for x in start..<min(start + size, width) {
                    let value = UInt32(bigEndian: line[x])
                    red += UInt64(value >> 24)
                    green += UInt64((value >> 16) & 0xFF)
                    blue += UInt64((value >> 8) & 0xFF)
                    alpha += UInt64(value & 0xFF)
                }
                sums[column * 4] += red
                sums[column * 4 + 1] += green
                sums[column * 4 + 2] += blue
                sums[column * 4 + 3] += alpha
            }
        }
    }

    /// 用块平均值（四舍五入）填满这一行块
    private func fill(top: Int, rows: Int, size: Int, from sums: UnsafeMutableBufferPointer<UInt64>) {
        for column in 0..<sums.count / 4 {
            let start = column * size
            let count = min(start + size, width) - start
            let area = UInt64(count * rows)
            let average = { (channel: Int) in (sums[column * 4 + channel] + area / 2) / area }
            let packed = UInt32(average(0) << 24 | average(1) << 16 | average(2) << 8 | average(3))
            let value = packed.bigEndian
            for row in top..<(top + rows) {
                (pixels + row * pixelsPerRow + start).update(repeating: value, count: count)
            }
        }
    }
}
