import CoreGraphics

/// 确定性伪随机数生成器（SplitMix64）
///
/// 模糊测试必须可复现：同一种子永远得到同一事件序列。这里不用标准库的 `random(in:using:)`，
/// 因为它把随机位映射到区间的算法不承诺跨 Swift 版本稳定；所有映射都在本类型里自己实现。
struct FuzzRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64 的下一个 64 位输出
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// [0, bound) 内的整数（bound 都很小，取模偏差可以忽略）
    mutating func int(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        return Int(next() % UInt64(bound))
    }

    /// [0, 1) 内的小数（取高 53 位，保证精确可表示）
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
    }

    /// 以 probability 的概率返回 true
    mutating func chance(_ probability: CGFloat) -> Bool {
        unit() < probability
    }

    /// [low, high) 内的小数
    mutating func value(in low: CGFloat, _ high: CGFloat) -> CGFloat {
        low + (high - low) * unit()
    }

    mutating func pick<Element>(_ items: [Element]) -> Element {
        items[int(below: items.count)]
    }

    /// 按整数权重选择；权重为 0 的项永远不会被选中
    mutating func weighted<Element>(_ items: [(Int, Element)]) -> Element {
        let total = items.reduce(0) { $0 + $1.0 }
        var remaining = int(below: total)
        for (weight, value) in items {
            if remaining < weight {
                return value
            }
            remaining -= weight
        }
        return items[items.count - 1].1
    }
}
