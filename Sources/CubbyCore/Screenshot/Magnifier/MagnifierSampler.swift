import CoreGraphics

/// 放大镜的像素网格：以中心像素为原点、边长 2 × radius + 1，行优先存储；nil 表示该格在帧外
public struct PixelGrid: Equatable, Sendable {
    /// 8 → 17×17
    public let radius: Int
    /// 行优先；nil = 帧外
    public let colors: [RGBAColor?]

    public init(radius: Int, colors: [RGBAColor?]) {
        self.radius = radius
        self.colors = colors
    }

    /// 网格边长（格数）
    public var side: Int { radius * 2 + 1 }

    /// 中心像素颜色（帧外为 nil）
    public var center: RGBAColor? { color(dx: 0, dy: 0) }

    /// 相对中心偏移 (dx, dy) 的格子颜色；超出网格或帧外为 nil
    public func color(dx: Int, dy: Int) -> RGBAColor? {
        guard abs(dx) <= radius, abs(dy) <= radius else { return nil }
        let index = (dy + radius) * side + (dx + radius)
        guard colors.indices.contains(index) else { return nil }
        return colors[index]
    }
}

/// 从冻结帧采样放大镜网格（§2.4）；读数统一换算到 sRGB 8 位
public enum MagnifierSampler {
    private static let bytesPerPixel = 4
    private static let maxComponent = 255.0

    /// centerPixel 为帧内像素坐标（左上原点）；小数向下取整
    public static func sample(frame: CGImage, centerPixel: CGPoint, radius: Int) -> PixelGrid {
        let radius = max(0, radius)
        let side = radius * 2 + 1
        let centerX = Int(centerPixel.x.rounded(.down))
        let centerY = Int(centerPixel.y.rounded(.down))
        let window = CGRect(x: centerX - radius, y: centerY - radius, width: side, height: side)
        let visible = window.intersection(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        let empty = PixelGrid(radius: radius, colors: Array(repeating: nil, count: side * side))
        guard !visible.isEmpty, let patch = PixelPatch(image: frame, region: visible) else { return empty }

        let colors = (0..<(side * side)).map { index -> RGBAColor? in
            let x = centerX - radius + index % side
            let y = centerY - radius + index / side
            return patch.color(atImageX: x, y: y)
        }
        return PixelGrid(radius: radius, colors: colors)
    }

    /// 帧中一块矩形区域的 RGBA 预乘字节（sRGB）
    private struct PixelPatch {
        let originX: Int
        let originY: Int
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(image: CGImage, region: CGRect) {
            guard let cropped = image.cropping(to: region),
                let space = CGColorSpace(name: CGColorSpace.sRGB)
            else { return nil }
            let width = cropped.width
            let height = cropped.height
            let rowBytes = width * MagnifierSampler.bytesPerPixel
            var buffer = [UInt8](repeating: 0, count: rowBytes * height)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard
                    let context = CGContext(
                        data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: rowBytes, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.setBlendMode(.copy)
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.originX = Int(region.minX)
            self.originY = Int(region.minY)
            self.width = width
            self.height = height
            self.bytes = buffer
        }

        /// 图像像素坐标处的非预乘颜色；不在本区域内为 nil
        func color(atImageX x: Int, y: Int) -> RGBAColor? {
            let localX = x - originX
            let localY = y - originY
            guard (0..<width).contains(localX), (0..<height).contains(localY) else { return nil }
            let index = (localY * width + localX) * MagnifierSampler.bytesPerPixel
            let alpha = Double(bytes[index + 3])
            guard alpha > 0 else { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) }
            let component = { (offset: Int) -> Double in min(1, Double(bytes[index + offset]) / alpha) }
            return RGBAColor(
                red: component(0),
                green: component(1),
                blue: component(2),
                alpha: alpha / MagnifierSampler.maxComponent
            )
        }
    }
}
