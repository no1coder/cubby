import Foundation
import Testing
@testable import CubbyCore

@Suite("UpdateReminder 蓝点与横幅的判断")
struct UpdateReminderTests {
    private static let tagURL = URL(string: "https://github.com/no1coder/cubby/releases/tag/v0.3.0")

    private func release(_ version: String) throws -> KnownRelease {
        try #require(KnownRelease(version: version, releaseURL: Self.tagURL))
    }

    /// 已完成欢迎页、开启自动检查、回答过询问的用户
    private func inputs(
        known: KnownRelease? = nil,
        dismissed: String? = nil,
        checks: Bool = true,
        answered: Bool = true,
        onboarded: Bool = true
    ) -> UpdateReminder.Inputs {
        UpdateReminder.Inputs(
            checksAutomatically: checks,
            hasAnsweredPrompt: answered,
            hasCompletedOnboarding: onboarded,
            knownRelease: known,
            dismissedVersion: dismissed.flatMap(SemanticVersion.init)
        )
    }

    @Test("没有已知的新版本：无蓝点、无横幅")
    func nothingKnown() {
        let reminder = UpdateReminder(inputs(), currentVersion: "0.2.1")
        #expect(!reminder.showsDot)
        #expect(reminder.availableRelease == nil)
        #expect(reminder.banner == nil)
        #expect(reminder == .none)
    }

    @Test("已知更新的版本：蓝点 + 新版本横幅（U5）")
    func availableShowsDotAndBanner() throws {
        let known = try release("0.3.0")
        let reminder = UpdateReminder(inputs(known: known), currentVersion: "0.2.1")
        #expect(reminder.showsDot)
        #expect(reminder.availableRelease == known)
        #expect(reminder.banner == .available(known))
    }

    @Test("「稍后」只隐藏这个版本的横幅，蓝点保留（U6）")
    func dismissedVersionHidesBannerOnly() throws {
        let known = try release("0.3.0")
        let reminder = UpdateReminder(inputs(known: known, dismissed: "0.3.0"), currentVersion: "0.2.1")
        #expect(reminder.showsDot)
        #expect(reminder.banner == nil)
    }

    @Test("出现更新的版本时再提醒（U6）")
    func newerVersionRemindsAgain() throws {
        let known = try release("0.3.1")
        let reminder = UpdateReminder(inputs(known: known, dismissed: "0.3.0"), currentVersion: "0.2.1")
        #expect(reminder.banner == .available(known))
    }

    @Test(
        "当前版本不低于已知版本（已升级）或无法解析时不提醒（U7）",
        arguments: ["0.3.0", "0.3.1", "1.0.0", "development"])
    func installedOrUnknownCurrent(_ current: String) throws {
        let reminder = UpdateReminder(inputs(known: try release("0.3.0")), currentVersion: current)
        #expect(!reminder.showsDot)
        #expect(reminder.banner == nil)
    }

    @Test("预发布的当前版本低于同号正式版：仍提醒")
    func prereleaseCurrent() throws {
        let reminder = UpdateReminder(inputs(known: try release("0.3.0")), currentVersion: "0.3.0-beta.2")
        #expect(reminder.showsDot)
    }

    @Test("老用户（完成过欢迎页、自动检查关、没回答过）问一次（U4）")
    func asksExistingUsers() {
        let reminder = UpdateReminder(inputs(checks: false, answered: false), currentVersion: "0.2.1")
        #expect(reminder.banner == .askPermission)
        #expect(!reminder.showsDot)
    }

    @Test(
        "回答过、开着自动检查或还没完成欢迎页时不问",
        arguments: [(false, true, true), (true, false, true), (false, false, false)])
    func doesNotAsk(_ checks: Bool, _ answered: Bool, _ onboarded: Bool) {
        let reminder = UpdateReminder(
            inputs(checks: checks, answered: answered, onboarded: onboarded), currentVersion: "0.2.1")
        #expect(reminder.banner == nil)
    }

    @Test("新版本横幅优先于询问；新版本横幅收起后才问")
    func availableBeforeAsk() throws {
        let known = try release("0.3.0")
        let first = UpdateReminder(inputs(known: known, checks: false, answered: false), currentVersion: "0.2.1")
        #expect(first.banner == .available(known))
        let dismissed = UpdateReminder(
            inputs(known: known, dismissed: "0.3.0", checks: false, answered: false), currentVersion: "0.2.1")
        #expect(dismissed.banner == .askPermission)
        #expect(dismissed.showsDot)
    }

    @Test("isInstalled：当前版本不低于已知版本即已安装")
    func isInstalled() throws {
        let known = try release("0.3.0")
        #expect(UpdateReminder.isInstalled(known, currentVersion: "0.3.0"))
        #expect(UpdateReminder.isInstalled(known, currentVersion: "v0.4.0"))
        #expect(!UpdateReminder.isInstalled(known, currentVersion: "0.2.9"))
        #expect(!UpdateReminder.isInstalled(known, currentVersion: "0.3.0-rc.1"))
        #expect(!UpdateReminder.isInstalled(known, currentVersion: "garbage"))
    }
}

@Suite("KnownRelease 已知的新版本")
struct KnownReleaseTests {
    @Test("解析版本号并规范化；非法版本号返回 nil")
    func parsesVersion() throws {
        let url = URL(string: "https://github.com/no1coder/cubby/releases/tag/v0.3.0")
        let release = try #require(KnownRelease(version: "v0.3.0", releaseURL: url))
        #expect(release.version.description == "0.3.0")
        #expect(release.releaseURL == url)
        #expect(KnownRelease(version: "latest", releaseURL: url) == nil)
    }

    @Test("发布页不在白名单内时换成固定的发布页")
    func sanitizesURL() throws {
        let release = try #require(KnownRelease(version: "0.3.0", releaseURL: URL(string: "http://evil.example")))
        #expect(release.releaseURL == UpdateReleaseURL.releasesPage)
        let missing = try #require(KnownRelease(version: "0.3.0", releaseURL: nil))
        #expect(missing.releaseURL == UpdateReleaseURL.releasesPage)
    }
}

@Suite("UpdateCheckSchedule 每天检查一次")
struct UpdateCheckScheduleTests {
    private let now = Date(timeIntervalSinceReferenceDate: 900_000_000)

    @Test("间隔为一天；失败后一小时内不重试；每小时判断时留 10 分钟余量")
    func intervals() {
        #expect(UpdateCheckSchedule.interval == 24 * 60 * 60)
        #expect(UpdateCheckSchedule.retryAfterFailure == 60 * 60)
        #expect(UpdateCheckSchedule.slack == 10 * 60)
    }

    @Test("从未检查过即到期；不足一天不到期；满一天到期（U1）")
    func dueAfterOneDay() {
        #expect(UpdateCheckSchedule.isDue(lastCheck: nil, lastFailure: nil, now: now))
        let halfDay = now.addingTimeInterval(-UpdateCheckSchedule.interval / 2)
        #expect(!UpdateCheckSchedule.isDue(lastCheck: halfDay, lastFailure: nil, now: now))
        let exactly = now.addingTimeInterval(-UpdateCheckSchedule.interval)
        #expect(UpdateCheckSchedule.isDue(lastCheck: exactly, lastFailure: nil, now: now))
    }

    @Test("每小时的判断稍早于满一天（请求耗时、定时器误差）也算到期，不拖到下一小时")
    func slackAroundOneDay() {
        let withinSlack = now.addingTimeInterval(-UpdateCheckSchedule.interval + UpdateCheckSchedule.slack)
        #expect(UpdateCheckSchedule.isDue(lastCheck: withinSlack, lastFailure: nil, now: now))
        let beforeSlack = now.addingTimeInterval(-UpdateCheckSchedule.interval + UpdateCheckSchedule.slack + 60)
        #expect(!UpdateCheckSchedule.isDue(lastCheck: beforeSlack, lastFailure: nil, now: now))
        let retryWithinSlack = now.addingTimeInterval(
            -UpdateCheckSchedule.retryAfterFailure + UpdateCheckSchedule.slack)
        #expect(UpdateCheckSchedule.isDue(lastCheck: nil, lastFailure: retryWithinSlack, now: now))
    }

    @Test("上次检查时间在未来（时钟被调回）视为到期，免得再也不检查")
    func futureTimestampIsDue() {
        #expect(UpdateCheckSchedule.isDue(lastCheck: now.addingTimeInterval(3600), lastFailure: nil, now: now))
    }

    @Test("最近失败过：一小时内不重试，之后重试")
    func failureBackoff() {
        let recent = now.addingTimeInterval(-60)
        #expect(!UpdateCheckSchedule.isDue(lastCheck: nil, lastFailure: recent, now: now))
        let old = now.addingTimeInterval(-UpdateCheckSchedule.retryAfterFailure)
        #expect(UpdateCheckSchedule.isDue(lastCheck: nil, lastFailure: old, now: now))
        // 失败时间在未来（时钟被调回）不阻止检查
        #expect(UpdateCheckSchedule.isDue(lastCheck: nil, lastFailure: now.addingTimeInterval(60), now: now))
    }
}
