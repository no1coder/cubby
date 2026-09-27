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

    @Test("设置值写入 UserDefaults 后可被新实例读回")
    func persists() {
        let defaults = makeDefaults()
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let settings = AppSettings(defaults: defaults)
        settings.checksForUpdatesAutomatically = true
        settings.lastUpdateCheck = date

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.checksForUpdatesAutomatically)
        #expect(reloaded.lastUpdateCheck == date)
    }

    @Test("开启后：从未检查过或距上次超过一周才需要检查")
    func dueRules() {
        let settings = AppSettings(defaults: makeDefaults())
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        settings.checksForUpdatesAutomatically = true
        #expect(settings.isAutomaticUpdateCheckDue(now: now))

        settings.lastUpdateCheck = now.addingTimeInterval(-AppSettings.updateCheckInterval + 60)
        #expect(!settings.isAutomaticUpdateCheckDue(now: now))

        settings.lastUpdateCheck = now.addingTimeInterval(-AppSettings.updateCheckInterval)
        #expect(settings.isAutomaticUpdateCheckDue(now: now))

        settings.checksForUpdatesAutomatically = false
        #expect(!settings.isAutomaticUpdateCheckDue(now: now))
    }
}
