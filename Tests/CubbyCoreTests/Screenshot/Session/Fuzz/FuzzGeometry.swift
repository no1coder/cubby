import CoreGraphics
@testable import CubbyCore

/// 性质测试用的几何生成器：偏向边界、小数、负坐标与退化形状（零尺寸、负尺寸、比边界还大）
enum FuzzGeometry {
    /// 浮点容差：小数边界上 `(maxX − w) + w` 之类的运算会差一个 ulp
    static let tolerance: CGFloat = 1e-9

    /// 屏幕大小的边界：夹具屏幕、整数原点（含负坐标）的常见尺寸、很小的尺寸、小数原点与尺寸
    static func bounds(_ rng: inout FuzzRandom) -> CGRect {
        switch rng.int(below: 5) {
        case 0:
            return rng.pick([FuzzTopologies.primary.frame, FuzzTopologies.external.frame, FuzzTopologies.lower.frame])
        case 1:
            return CGRect(
                x: CGFloat(rng.int(below: 8001) - 4000), y: CGFloat(rng.int(below: 6001) - 3000),
                width: CGFloat(rng.int(below: 3997) + 4), height: CGFloat(rng.int(below: 2997) + 4))
        case 2:
            return CGRect(
                x: CGFloat(rng.int(below: 201) - 100), y: CGFloat(rng.int(below: 201) - 100),
                width: rng.value(in: 4, 40), height: rng.value(in: 4, 40))
        default:
            return CGRect(
                x: rng.value(in: -3000, 3000), y: rng.value(in: -3000, 3000),
                width: rng.value(in: 4, 3000), height: rng.value(in: 4, 3000))
        }
    }

    /// 一维取值：内部、贴边 ± 小偏移、远处
    static func coordinate(_ rng: inout FuzzRandom, low: CGFloat, high: CGFloat) -> CGFloat {
        let offsets: [CGFloat] = [-10, -4, -1, -0.5, -0.25, -0.001, 0, 0, 0.001, 0.25, 0.5, 1, 4, 10]
        switch rng.int(below: 6) {
        case 0: return low + rng.pick(offsets)
        case 1: return high + rng.pick(offsets)
        case 2: return low + (high - low) * rng.unit()
        case 3: return (low + (high - low) * rng.unit()).rounded()
        case 4: return low - (high - low) * rng.unit() * 2
        default: return high + (high - low) * rng.unit() * 2
        }
    }

    static func point(_ rng: inout FuzzRandom, around bounds: CGRect) -> CGPoint {
        CGPoint(
            x: coordinate(&rng, low: bounds.minX, high: bounds.maxX),
            y: coordinate(&rng, low: bounds.minY, high: bounds.maxY)
        )
    }

    /// 任意矩形：内部、跨边、完全在外、比边界大、零尺寸、负尺寸
    static func rect(_ rng: inout FuzzRandom, around bounds: CGRect) -> CGRect {
        let first = point(&rng, around: bounds)
        switch rng.int(below: 8) {
        case 0:
            return CGRect(origin: first, size: .zero)
        case 1:
            // 负尺寸（反向拖出）
            let second = point(&rng, around: bounds)
            return CGRect(x: first.x, y: first.y, width: second.x - first.x, height: second.y - first.y)
        case 2:
            return bounds.insetBy(dx: -rng.value(in: 0, 50), dy: -rng.value(in: 0, 50))
        case 3, 4:
            return insideRect(&rng, in: bounds)
        default:
            let second = point(&rng, around: bounds)
            return CGRect(
                x: min(first.x, second.x), y: min(first.y, second.y),
                width: abs(second.x - first.x), height: abs(second.y - first.y))
        }
    }

    /// 完整位于 bounds 内的矩形（尺寸可以为 0）
    static func insideRect(_ rng: inout FuzzRandom, in bounds: CGRect) -> CGRect {
        let width = bounds.width * rng.unit() * (rng.chance(0.3) ? 0.02 : 1)
        let height = bounds.height * rng.unit() * (rng.chance(0.3) ? 0.02 : 1)
        let x = bounds.minX + (bounds.width - width) * rng.unit()
        let y = bounds.minY + (bounds.height - height) * rng.unit()
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// inner 是否（在容差内）完整位于 outer 内，且尺寸非负
    static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        inner.width >= 0 && inner.height >= 0
            && inner.minX >= outer.minX - tolerance && inner.maxX <= outer.maxX + tolerance
            && inner.minY >= outer.minY - tolerance && inner.maxY <= outer.maxY + tolerance
    }

    static func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= tolerance * max(1, abs(lhs), abs(rhs))
    }

    static func close(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        close(lhs.minX, rhs.minX) && close(lhs.minY, rhs.minY) && close(lhs.width, rhs.width)
            && close(lhs.height, rhs.height)
    }
}

/// 性质测试的失败收集：只保留前几个反例，最后统一断言，避免成千上万条重复报告
struct PropertyFailures {
    private(set) var count = 0
    private(set) var examples: [String] = []

    mutating func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        guard !condition else { return }
        count += 1
        if examples.count < 5 {
            examples.append(message())
        }
    }

    var summary: String {
        "\(count) counterexamples, e.g.\n" + examples.joined(separator: "\n")
    }
}
