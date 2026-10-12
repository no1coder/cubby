/// 首次引导向导的四步：欢迎 → 授权 → 选择样子 → 快捷键（docs/UI-UPGRADE-PLAN.md 第 2、3、8 节）
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case permissions
    case style
    case shortcut

    /// 步骤指示器里某一步相对当前步骤的状态
    public enum Progress: Sendable, Equatable {
        /// 已完成：绿色对勾
        case done
        /// 当前：蓝色序号
        case current
        /// 尚未到达：灰色序号
        case upcoming
    }

    /// 从 1 开始的序号（步骤指示器显示）
    public var number: Int { rawValue + 1 }

    public var isFirst: Bool { self == Self.allCases.first }
    public var isLast: Bool { self == Self.allCases.last }

    /// 下一步；已是最后一步时为 nil
    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }

    /// 上一步；已是第一步时为 nil
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// 本步骤在当前步骤为 `current` 时的状态
    public func progress(current: OnboardingStep) -> Progress {
        if self == current { return .current }
        return rawValue < current.rawValue ? .done : .upcoming
    }
}
