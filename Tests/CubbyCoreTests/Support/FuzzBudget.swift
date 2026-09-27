import Foundation

/// 模糊 / 性质测试的规模。
///
/// 环境变量 `CUBBY_FUZZ_SEEDS` 设定截图状态机模糊测试的种子数（默认 2048）；其余随机测试按同一比例
/// 缩放各自的默认次数（至少 1 次）。CI 设为 256（各取 1/8），缩短 CPU 密集的阶段；本地不设时保持默认，
/// 设得更大（例如 20000）即可做深度模糊。种子固定，同一设置下每次运行的输入完全相同
enum FuzzBudget {
    static let defaultSeeds = 2048

    static var seeds: Int {
        guard let raw = ProcessInfo.processInfo.environment["CUBBY_FUZZ_SEEDS"], let value = Int(raw), value > 0 else {
            return defaultSeeds
        }
        return value
    }

    /// 按种子数相对默认值的比例缩放 defaultCount
    static func scaled(_ defaultCount: Int) -> Int {
        max(1, defaultCount * seeds / defaultSeeds)
    }
}
