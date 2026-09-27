import CoreGraphics

/// 版面计算共用的小工具
enum TranslationMath {
    /// 中位数（偶数个取中间两数的均值）；空数组为 0
    static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
