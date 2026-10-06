import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 更新提醒的持久化设置")
@MainActor
struct AppSettingsUpdateReminderTests {
    private static let tagURL = URL(string: "https://github.com/no1coder/cubby/releases/tag/v0.3.0")!

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "cubby-test-reminder-\(UUID().uuidString)")!
    }

    private func release(_ version: String) throws -> KnownRelease {
        try #require(KnownRelease(version: version, releaseURL: Self.tagURL))
    }

    @Test("默认：没有已知版本、没有「稍后」、没回答过询问")
    func defaults() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.knownRelease == nil)
        #expect(settings.dismissedUpdateVersion == nil)
        #expect(!settings.hasAnsweredUpdatePrompt)
        #expect(settings.updateReminder(currentVersion: "0.2.1") == .none)
    }

    @Test("记住查到的版本与发布页，重启后不联网也能读回（U7）")
    func remembersRelease() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        let known = try release("0.3.0")
        settings.rememberAvailableRelease(known)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.knownRelease == known)
        #expect(reloaded.updateReminder(currentVersion: "0.2.1").showsDot)
    }

    @Test("读回时校验：非法版本号丢弃，不在白名单内的地址换成固定发布页")
    func validatesStoredValues() {
        let defaults = makeDefaults()
        defaults.set("latest", forKey: "latestKnownVersion")
        defaults.set("https://github.com/no1coder/cubby/releases", forKey: "latestKnownReleaseURL")
        defaults.set(42, forKey: "dismissedUpdateVersion")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.knownRelease == nil)
        #expect(settings.dismissedUpdateVersion == nil)

        defaults.set("0.3.0", forKey: "latestKnownVersion")
        defaults.set("https://evil.example/cubby.dmg", forKey: "latestKnownReleaseURL")
        #expect(AppSettings(defaults: defaults).knownRelease?.releaseURL == UpdateReleaseURL.releasesPage)

        defaults.set(7, forKey: "latestKnownReleaseURL")
        #expect(AppSettings(defaults: defaults).knownRelease?.releaseURL == UpdateReleaseURL.releasesPage)
    }

    @Test("忘记已知版本时一并移除持久化的键")
    func forgetsRelease() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.rememberAvailableRelease(try release("0.3.0"))
        settings.forgetKnownRelease()
        #expect(settings.knownRelease == nil)
        #expect(defaults.object(forKey: "latestKnownVersion") == nil)
        #expect(defaults.object(forKey: "latestKnownReleaseURL") == nil)
        #expect(AppSettings(defaults: defaults).knownRelease == nil)
    }

    @Test("「稍后」按版本持久化，重启后仍有效（U6）")
    func dismissPersists() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        settings.checksForUpdatesAutomatically = true
        let known = try release("0.3.0")
        settings.rememberAvailableRelease(known)
        #expect(settings.updateReminder(currentVersion: "0.2.1").banner == .available(known))
        settings.dismissUpdateBanner(for: known)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.dismissedUpdateVersion?.description == "0.3.0")
        let reminder = reloaded.updateReminder(currentVersion: "0.2.1")
        #expect(reminder.banner == nil)
        #expect(reminder.showsDot)
    }

    @Test("升级后清除已知版本与过期的「稍后」（U7）")
    func clearsInstalledRelease() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        let known = try release("0.3.0")
        settings.rememberAvailableRelease(known)
        settings.dismissUpdateBanner(for: known)

        #expect(!settings.clearInstalledRelease(currentVersion: "0.2.1"))
        #expect(settings.knownRelease == known)

        #expect(settings.clearInstalledRelease(currentVersion: "0.3.0"))
        #expect(settings.knownRelease == nil)
        #expect(settings.dismissedUpdateVersion == nil)
        #expect(!settings.updateReminder(currentVersion: "0.3.0").showsDot)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.knownRelease == nil)
        #expect(reloaded.dismissedUpdateVersion == nil)
    }

    @Test("升级到中间版本：已知的更高版本与它的「稍后」都保留")
    func keepsNewerDismissal() throws {
        let settings = AppSettings(defaults: makeDefaults())
        let known = try release("0.4.0")
        settings.rememberAvailableRelease(known)
        settings.dismissUpdateBanner(for: known)
        #expect(!settings.clearInstalledRelease(currentVersion: "0.3.0"))
        #expect(settings.dismissedUpdateVersion?.description == "0.4.0")
    }

    @Test("没有已知版本时，不高于当前版本的「稍后」也被清除")
    func clearsStaleDismissalAlone() throws {
        let settings = AppSettings(defaults: makeDefaults())
        settings.dismissUpdateBanner(for: try release("0.3.0"))
        #expect(!settings.clearInstalledRelease(currentVersion: "garbage"))
        #expect(settings.dismissedUpdateVersion != nil)
        #expect(settings.clearInstalledRelease(currentVersion: "0.3.0"))
        #expect(settings.dismissedUpdateVersion == nil)
    }

    @Test("询问横幅：「提醒我」打开开关，「不用了」保持关闭；都算回答过（U4）")
    func answersPrompt() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        #expect(settings.updateReminder(currentVersion: "0.2.1").banner == .askPermission)

        settings.answerUpdatePrompt(remindMe: false)
        #expect(!settings.checksForUpdatesAutomatically)
        #expect(settings.hasAnsweredUpdatePrompt)
        #expect(settings.updateReminder(currentVersion: "0.2.1").banner == nil)
        #expect(AppSettings(defaults: defaults).hasAnsweredUpdatePrompt)

        settings.answerUpdatePrompt(remindMe: true)
        #expect(settings.checksForUpdatesAutomatically)
    }

    @Test("在设置里改动开关也算回答过：关掉的人不会再被问")
    func togglingCountsAsAnswer() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.hasCompletedOnboarding = true
        settings.checksForUpdatesAutomatically = true
        settings.checksForUpdatesAutomatically = false
        #expect(settings.hasAnsweredUpdatePrompt)
        #expect(settings.updateReminder(currentVersion: "0.2.1").banner == nil)
    }

    @Test("新用户第一次显示欢迎页：默认打开自动检查，只做一次（U3）")
    func firstRunDefault() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.applyFirstRunUpdateDefault())
        #expect(settings.checksForUpdatesAutomatically)
        #expect(settings.hasAnsweredUpdatePrompt)

        // 用户取消勾选后没点「开始使用」就退出：下次启动再显示欢迎页时不再改回
        settings.checksForUpdatesAutomatically = false
        let relaunched = AppSettings(defaults: defaults)
        #expect(!relaunched.applyFirstRunUpdateDefault())
        #expect(!relaunched.checksForUpdatesAutomatically)
    }

    @Test("完成过欢迎页的老用户从菜单重开欢迎页：不改动开关")
    func existingUserUnchanged() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.hasCompletedOnboarding = true
        #expect(!settings.applyFirstRunUpdateDefault())
        #expect(!settings.checksForUpdatesAutomatically)
        #expect(!settings.hasAnsweredUpdatePrompt)
        #expect(settings.updateReminder(currentVersion: "0.2.1").banner == .askPermission)
    }
}
