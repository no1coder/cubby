import Foundation

/// 自动检查更新的节奏（docs/UPDATE-REMINDER-DESIGN.md U1）：每天一次；失败后一小时内不重试
public enum UpdateCheckSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60
    /// 联网失败（例如刚从睡眠唤醒、网络还没连上）后的重试间隔：不推迟一整天，也不连续请求
    public static let retryAfterFailure: TimeInterval = 60 * 60
    /// 判断到期时的余量：记录的是请求结束的时间，每小时的判断又可能被系统推迟几分钟，
    /// 稍早于满一天（或满一小时）也算到期，免得每次都拖到下一小时
    public static let slack: TimeInterval = 10 * 60

    /// 是否到期：从未检查过、距上次满一天，或上次检查时间在未来（时钟被调回）；最近一小时内失败过则不到期
    public static func isDue(lastCheck: Date?, lastFailure: Date?, now: Date) -> Bool {
        if let lastFailure, isWithin(retryAfterFailure, since: lastFailure, now: now) { return false }
        guard let lastCheck else { return true }
        return !isWithin(interval, since: lastCheck, now: now)
    }

    /// date 不在未来，且距 now 不足 duration（扣除余量）
    private static func isWithin(_ duration: TimeInterval, since date: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(date)
        return elapsed >= 0 && elapsed < duration - slack
    }
}
