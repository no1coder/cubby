import CoreGraphics
import Foundation

/// 8 位 sRGB 颜色（整数分量，便于逐像素统计）
struct RGB: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    /// 欧氏距离的平方（0…3 × 255²）
    func distanceSquared(to other: RGB) -> Int {
        let dr = red - other.red
        let dg = green - other.green
        let db = blue - other.blue
        return dr * dr + dg * dg + db * db
    }

    var pixelColor: PixelColor {
        PixelColor(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

/// 帧位图里的整数像素矩形（左上原点，max 不含）
struct PixelBox: Equatable, Sendable {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }
    var isEmpty: Bool { width <= 0 || height <= 0 }

    func insetBy(_ amount: Int) -> PixelBox {
        PixelBox(minX: minX + amount, minY: minY + amount, maxX: maxX - amount, maxY: maxY - amount)
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= minX && x < maxX && y >= minY && y < maxY
    }

    func intersects(_ other: PixelBox) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }
}

/// 冻结帧中一小块区域的像素（sRGB RGBA8，左上原点）。只复制这一块，不复制整帧；坐标一律用帧位图像素
struct PixelPatch {
    let bounds: PixelBox
    let screen: CaptureScreen
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// region 为全局点；与帧位图无交集或无法读取时为 nil
    init?(frame: FrozenFrame, region: CGRect) {
        let imageBounds = CGRect(x: 0, y: 0, width: frame.image.width, height: frame.image.height)
        let rect = frame.screen.pixelRect(region).intersection(imageBounds)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
            let cropped = frame.image.cropping(to: rect),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let width = Int(rect.width)
        let height = Int(rect.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: Self.bitmapInfo)
            else { return false }
            context.interpolationQuality = .none
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.bounds = PixelBox(
            minX: Int(rect.minX), minY: Int(rect.minY), maxX: Int(rect.maxX), maxY: Int(rect.maxY))
        self.screen = frame.screen
        self.bytes = buffer
        self.bytesPerRow = width * 4
    }

    /// 帧像素坐标处的颜色（调用方保证在 bounds 内）
    func color(x: Int, y: Int) -> RGB {
        let offset = (y - bounds.minY) * bytesPerRow + (x - bounds.minX) * 4
        return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    /// 全局点矩形 → 帧像素矩形（向外取整），再与本块相交；无交集为 nil
    func box(_ rect: CGRect) -> PixelBox? {
        let scale = screen.scale
        let minX = Int(((rect.minX - screen.frame.minX) * scale).rounded(.down))
        let minY = Int(((rect.minY - screen.frame.minY) * scale).rounded(.down))
        let maxX = Int(((rect.maxX - screen.frame.minX) * scale).rounded(.up))
        let maxY = Int(((rect.maxY - screen.frame.minY) * scale).rounded(.up))
        let clipped = PixelBox(
            minX: max(minX, bounds.minX), minY: max(minY, bounds.minY),
            maxX: min(maxX, bounds.maxX), maxY: min(maxY, bounds.maxY))
        return clipped.isEmpty ? nil : clipped
    }

    /// 帧像素坐标 → 全局点
    func globalX(_ pixel: Int) -> CGFloat { screen.frame.minX + CGFloat(pixel) / screen.scale }
    func globalY(_ pixel: Int) -> CGFloat { screen.frame.minY + CGFloat(pixel) / screen.scale }

    /// 帧像素矩形 → 全局点矩形
    func globalRect(_ box: PixelBox) -> CGRect {
        CGRect(
            x: globalX(box.minX), y: globalY(box.minY), width: CGFloat(box.width) / screen.scale,
            height: CGFloat(box.height) / screen.scale)
    }

    /// 本块内、落在 boxes 任一个里的像素（逐个访问，重叠处只访问一次）。
    /// 只与之前那些真正相交的框去重（行框通常互不相交，此时不做任何逐像素比较），整体接近线性
    func forEachPixel(in boxes: [PixelBox], _ body: (_ x: Int, _ y: Int, _ color: RGB) -> Void) {
        for (index, box) in boxes.enumerated() {
            let earlier = boxes[..<index].filter { $0.intersects(box) }
            for y in box.minY..<box.maxY {
                let covering = earlier.filter { $0.minY <= y && y < $0.maxY }
                for x in box.minX..<box.maxX where !covering.contains(where: { x >= $0.minX && x < $0.maxX }) {
                    body(x, y, color(x: x, y: y))
                }
            }
        }
    }
}
