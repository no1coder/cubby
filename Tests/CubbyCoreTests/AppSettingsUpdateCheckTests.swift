import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 检查更新设置")
@MainActor
struct AppSettingsUpdateCheckTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "cubby-test-update-\(UUID().uuidString)")!
    }

    @Test("默认关闭自动检查，且没有检查记录")
    func defaults() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(!settings.checksForUpdatesAutomatically)
        #expect(settings.lastUpdateCheck == nil)
        #expect(!settings.isAutomaticUpdateCheckDue())
    }

    @Test("设置值写入 UserDefaults 后可被新实例读回（沿用原来的键）")
    func persists() {
        let defaults = makeDefaults()
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let settings = AppSettings(defaults: defaults)
        settings.checksForUpdatesAutomatically = true
        settings.lastUpdateCheck = date

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.checksForUpdatesAutomatically)
        #expect(reloaded.lastUpdateCheck == date)
        #expect(defaults.bool(forKey: "checksForUpdatesAutomatically"))
    }

    @Test("老版本写入的开关（同一个键）原样保留")
    func keepsExistingChoice() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "checksForUpdatesAutomatically")
        #expect(AppSettings(defaults: defaults).checksForUpdatesAutomatically)
    }

    /// 已完成欢迎页的用户（到期规则只对他们生效）
    private func onboardedSettings() -> AppSettings {
        let settings = AppSettings(defaults: makeDefaults())
        settings.hasCompletedOnboarding = true
        return settings
    }

    @Test("开启后：从未检查过或距上次满一天才需要检查（U1）")
    func dueRules() {
        let settings = onboardedSettings()
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        #expect(AppSettings.updateCheckInterval == 24 * 60 * 60)
        settings.checksForUpdatesAutomatically = true
        #expect(settings.isAutomaticUpdateCheckDue(now: now))

        settings.lastUpdateCheck = now.addingTimeInterval(-AppSettings.updateCheckInterval / 2)
        #expect(!settings.isAutomaticUpdateCheckDue(now: now))

        settings.lastUpdateCheck = now.addingTimeInterval(-AppSettings.updateCheckInterval)
        #expect(settings.isAutomaticUpdateCheckDue(now: now))

        settings.checksForUpdatesAutomatically = false
        #expect(!settings.isAutomaticUpdateCheckDue(now: now))
    }

    @Test("最近一次失败后一小时内不重试")
    func retriesAfterFailure() {
        let settings = onboardedSettings()
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        settings.checksForUpdatesAutomatically = true
        #expect(!settings.isAutomaticUpdateCheckDue(now: now, lastFailure: now.addingTimeInterval(-60)))
        let old = now.addingTimeInterval(-UpdateCheckSchedule.retryAfterFailure)
        #expect(settings.isAutomaticUpdateCheckDue(now: now, lastFailure: old))
    }

    @Test("完成欢迎页之前从不到期：欢迎页显示期间开关已默认打开，用户还可能取消勾选（U3）")
    func neverDueBeforeOnboarding() {
        let settings = AppSettings(defaults: makeDefaults())
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        #expect(settings.applyFirstRunUpdateDefault())
        #expect(settings.checksForUpdatesAutomatically)
        #expect(!settings.isAutomaticUpdateCheckDue(now: now))
        settings.hasCompletedOnboarding = true
        #expect(settings.isAutomaticUpdateCheckDue(now: now))
    }
}
