import Accelerate
import CoreGraphics

/// 衬底下的模糊背景：取冻结帧中衬底周围的像素（只取这一小块），先去掉原文墨迹（否则模糊后留下原文的虚影），
/// 再三次盒式模糊近似高斯模糊
enum PlateBlur {
    /// 去墨迹：lines（全局点）内的像素减去其覆盖度 × (文字色 − 背景色)
    struct Deinking {
        let model: InkModel
        let lines: [CGRect]
    }

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// plate 为全局点（应已对齐像素）；radius 为高斯标准差（点）。返回与 plate 像素大小一致的图，失败时 nil
    static func image(frame: FrozenFrame, plate: CGRect, radius: CGFloat, deinking: Deinking) -> CGImage? {
        let screen = frame.screen
        let sigma = radius * screen.scale
        let imageBounds = CGRect(x: 0, y: 0, width: frame.image.width, height: frame.image.height)
        let target = screen.pixelRect(plate).intersection(imageBounds)
        let source = screen.pixelRect(plate.insetBy(dx: -3 * radius, dy: -3 * radius)).intersection(imageBounds)
        let lines = deinking.lines.map { screen.pixelRect($0).offsetBy(dx: -source.minX, dy: -source.minY) }
        guard !target.isNull, !target.isEmpty,
            let context = blurredContext(frame.image, source, sigma: sigma, deinking: (deinking.model, lines)),
            let blurred = context.makeImage()
        else { return nil }
        // context 的第 0 行是 source 的顶行（位图内存自上而下）
        let crop = CGRect(
            x: target.minX - source.minX, y: target.minY - source.minY, width: target.width, height: target.height)
        return blurred.cropping(to: crop)
    }

    /// 把 source 像素区域画进位图，去墨迹后原地模糊
    private static func blurredContext(
        _ image: CGImage, _ source: CGRect, sigma: CGFloat, deinking: (model: InkModel, lines: [CGRect])
    ) -> CGContext? {
        guard let cropped = image.cropping(to: source), let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(source.width), height: Int(source.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo),
            let data = context.data
        else { return nil }
        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        removeInk(in: context, model: deinking.model, lines: deinking.lines)
        var buffer = vImage_Buffer(
            data: data, height: vImagePixelCount(context.height), width: vImagePixelCount(context.width),
            rowBytes: context.bytesPerRow)
        let kernel = boxKernel(sigma: sigma)
        guard kernel > 1 else { return context }
        var scratch = [UInt8](repeating: 0, count: context.bytesPerRow * context.height)
        scratch.withUnsafeMutableBytes { raw in
            var temporary = vImage_Buffer(
                data: raw.baseAddress, height: buffer.height, width: buffer.width, rowBytes: buffer.rowBytes)
            // 三次盒式模糊 ≈ 高斯；两块缓冲区来回倒，最后结果落回 buffer
            for (from, to) in [(buffer, temporary), (temporary, buffer), (buffer, temporary)] {
                var input = from
                var output = to
                vImageBoxConvolve_ARGB8888(
                    &input, &output, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend))
            }
            vImageCopyBuffer(&temporary, &buffer, 4, vImage_Flags(kvImageNoFlags))
        }
        return context
    }

    /// 位图内存第 0 行是顶行；lines 为位图像素坐标（左上原点）
    private static func removeInk(in context: CGContext, model: InkModel, lines: [CGRect]) {
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return }
        let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        let delta = [
            model.ink.red - model.background.red, model.ink.green - model.background.green,
            model.ink.blue - model.background.blue,
        ]
        for line in lines.map({ $0.intersection(bounds) }) where !line.isNull {
            for y in Int(line.minY)..<Int(line.maxY) {
                for x in Int(line.minX)..<Int(line.maxX) {
                    let offset = y * context.bytesPerRow + x * 4
                    let pixel = RGB(red: Int(data[offset]), green: Int(data[offset + 1]), blue: Int(data[offset + 2]))
                    let amount = model.coverage(pixel)
                    for channel in 0..<3 {
                        let value = Double(data[offset + channel]) - amount * Double(delta[channel])
                        data[offset + channel] = UInt8(min(max(value.rounded(), 0), 255))
                    }
                }
            }
        }
    }

    /// 三次盒式模糊逼近标准差 sigma 的高斯：盒宽 ≈ √(4σ² + 1)，取奇数
    static func boxKernel(sigma: CGFloat) -> UInt32 {
        let width = Int((4 * sigma * sigma + 1).squareRoot().rounded())
        return UInt32(max(1, width | 1))
    }
}
