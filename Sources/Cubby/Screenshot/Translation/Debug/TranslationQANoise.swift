#if DEBUG
import CoreGraphics

/// 照片感的平滑彩色噪点（两层插值噪声 + 颗粒），偏暗以衬白字；种子相同则结果相同
enum TranslationQANoise {
    static func image(size: CGSize, seed: UInt64) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let data = context.data
        else { return nil }
        let buffer = data.assumingMemoryBound(to: UInt8.self)
        var random = SplitMix(state: seed)
        for channel in 0..<3 {
            let coarse = Grid(width: width, height: height, step: 96, random: &random)
            let fine = Grid(width: width, height: height, step: 28, random: &random)
            for y in 0..<height {
                for x in 0..<width {
                    let value = 0.7 * coarse.sample(x, y) + 0.3 * fine.sample(x, y)
                    let grain = (random.unit() - 0.5) * 12
                    buffer[(y * width + x) * 4 + channel] = UInt8(max(0, min(255, 20 + value * 130 + grain)))
                }
            }
        }
        return context.makeImage()
    }

    /// 可复现的随机数
    private struct SplitMix {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    }

    /// 网格随机值 + smoothstep 双线性插值
    private struct Grid {
        let columns: Int
        let step: Int
        let values: [Double]

        init(width: Int, height: Int, step: Int, random: inout SplitMix) {
            columns = width / step + 2
            self.step = step
            values = (0..<(columns * (height / step + 2))).map { _ in random.unit() }
        }

        func sample(_ x: Int, _ y: Int) -> Double {
            let fx = Double(x) / Double(step)
            let fy = Double(y) / Double(step)
            let ix = Int(fx)
            let iy = Int(fy)
            let tx = smooth(fx - Double(ix))
            let ty = smooth(fy - Double(iy))
            let top = values[iy * columns + ix] + (values[iy * columns + ix + 1] - values[iy * columns + ix]) * tx
            let bottomLeft = values[(iy + 1) * columns + ix]
            let bottom = bottomLeft + (values[(iy + 1) * columns + ix + 1] - bottomLeft) * tx
            return top + (bottom - top) * ty
        }

        private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    }
}
#endif
