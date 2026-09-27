import Foundation
import Testing
@testable import CubbyCore

/// 图片文字索引的调度（纯逻辑）：队列顺序、回填节流、暂停与关闭
@Suite("ImageTextIndexSchedule 调度")
struct ImageTextIndexScheduleTests {
    private let schedule = ImageTextIndexSchedule(startupDelay: 10, backfillInterval: 2)
    private let launch = Fixtures.baseDate

    /// 启动前已有的图片（回填对象）
    private func old(_ name: String, favorite: Bool = false) -> ClipItem {
        Fixtures.image(name: name, favorite: favorite, at: launch.addingTimeInterval(-3600))
    }

    /// 本次运行中新记录的图片
    private func new(_ name: String, after seconds: TimeInterval = 1) -> ClipItem {
        Fixtures.image(name: name, at: launch.addingTimeInterval(seconds))
    }

    private func state(
        enabled: Bool = true,
        paused: Bool = false,
        now offset: TimeInterval = 60,
        lastFinished: TimeInterval? = nil,
        skipping: Set<UUID> = []
    ) -> ImageTextIndexSchedule.State {
        ImageTextIndexSchedule.State(
            isEnabled: enabled,
            isPaused: paused,
            sessionStart: launch,
            now: launch.addingTimeInterval(offset),
            lastFinished: lastFinished.map { launch.addingTimeInterval($0) },
            skipped: skipping
        )
    }

    // MARK: - 关闭与暂停

    @Test("关闭或暂停时停止（即使有待识别图片）")
    func stopsWhenInactive() {
        let items = [new("a.png")]
        #expect(schedule.nextStep(items: items, state: state(enabled: false)) == .stop)
        #expect(schedule.nextStep(items: items, state: state(paused: true)) == .stop)
        #expect(schedule.nextStep(items: items, state: state(enabled: false, paused: true)) == .stop)
    }

    // MARK: - 队列

    @Test("没有待识别的图片时空闲：文本、文件、已识别（含空串）都不需要识别")
    func idleWhenNothingPending() {
        let items = [
            Fixtures.text("t"),
            Fixtures.files(["/tmp/a"]),
            old("a.png").withRecognizedText("done"),
            old("b.png").withRecognizedText(""),
        ]
        #expect(schedule.nextStep(items: items, state: state()) == .idle)
        #expect(schedule.nextStep(items: [], state: state()) == .idle)
    }

    @Test("按历史顺序（最新在前）取第一张未识别的图片，收藏不影响顺序")
    func picksNewestPending() {
        let done = old("done.png").withRecognizedText("x")
        let first = old("first.png", favorite: true)
        let second = old("second.png")
        let items = [Fixtures.text("t"), done, first, second]
        #expect(schedule.nextStep(items: items, state: state()) == .recognize(first))
        #expect(ImageTextIndexSchedule.pending(in: items, skipping: []) == [first, second])
    }

    @Test("本次运行中识别失败的条目跳过，不会反复重试")
    func skipsFailedItems() {
        let broken = old("broken.png")
        let next = old("next.png")
        let items = [broken, next]
        #expect(schedule.nextStep(items: items, state: state(skipping: [broken.id])) == .recognize(next))
        #expect(schedule.nextStep(items: items, state: state(skipping: [broken.id, next.id])) == .idle)
    }

    // MARK: - 新图片与回填节流

    @Test("本次运行中新记录的图片立即识别，不等启动延迟与回填间隔")
    func newImagesAreImmediate() {
        let fresh = new("fresh.png", after: 3)
        let items = [fresh, old("old.png")]
        #expect(schedule.nextStep(items: items, state: state(now: 3.5)) == .recognize(fresh))
        #expect(schedule.nextStep(items: items, state: state(now: 4, lastFinished: 3.9)) == .recognize(fresh))
    }

    @Test("回填先等启动延迟：返回剩余等待时间")
    func backfillWaitsForStartupDelay() {
        let items = [old("old.png")]
        #expect(schedule.nextStep(items: items, state: state(now: 4)) == .wait(6))
        #expect(schedule.nextStep(items: items, state: state(now: 10)) == .recognize(items[0]))
    }

    @Test("回填逐条之间保持间隔")
    func backfillKeepsInterval() {
        let items = [old("a.png"), old("b.png")]
        #expect(schedule.nextStep(items: items, state: state(now: 30, lastFinished: 29.5)) == .wait(1.5))
        #expect(schedule.nextStep(items: items, state: state(now: 31.5, lastFinished: 29.5)) == .recognize(items[0]))
        #expect(schedule.nextStep(items: items, state: state(now: 40, lastFinished: 29.5)) == .recognize(items[0]))
    }

    @Test("新图片排在旧图片之前：新图片识别完后，旧图片继续按间隔回填")
    func newBeforeBackfill() {
        let fresh = new("fresh.png", after: 20)
        let backlog = old("old.png")
        let afterFresh = [fresh.withRecognizedText("x"), backlog]
        #expect(schedule.nextStep(items: [fresh, backlog], state: state(now: 20)) == .recognize(fresh))
        #expect(schedule.nextStep(items: afterFresh, state: state(now: 21, lastFinished: 21)) == .wait(2))
    }

    @Test("时钟回拨（上次完成时间在未来）时最多等待一个间隔")
    func clockSkewIsBounded() {
        let items = [old("a.png")]
        let step = schedule.nextStep(items: items, state: state(now: 30, lastFinished: 3600))
        #expect(step == .wait(2))
    }

    @Test("标准参数：启动后延迟回填，逐条间隔")
    func standardValues() {
        #expect(ImageTextIndexSchedule.standard.startupDelay >= 5)
        #expect(ImageTextIndexSchedule.standard.backfillInterval >= 1)
    }
}
