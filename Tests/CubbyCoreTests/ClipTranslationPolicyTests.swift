import Foundation
import Testing
@testable import CubbyCore

/// 翻译资格（类型、代码、长度、图片尺寸、密钥 × 云端）与复制时自动翻译的策略、调度
@Suite("ClipTranslationEligibilityCheck 翻译资格")
struct ClipTranslationEligibilityTests {
    private func reason(_ item: ClipItem) -> ClipUntranslatableReason? {
        ClipTranslationEligibilityCheck.unsupportedReason(for: item)
    }

    @Test("链接、文件、颜色不支持；普通文本、中文、富文本可以翻译")
    func kinds() {
        #expect(reason(Fixtures.text("https://github.com/no1coder/cubby")) == .link)
        #expect(reason(Fixtures.files(["/tmp/a.txt"])) == .file)
        #expect(reason(Fixtures.text("#5F2EEA")) == .color)
        #expect(reason(Fixtures.text("Hello world")) == nil)
        #expect(reason(Fixtures.text("\u{660E}\u{5929}\u{7684}\u{4F1A}\u{8BAE}")) == nil)
        #expect(reason(Fixtures.text("Rich", formatsName: "a.formats")) == nil)
    }

    @Test("代码片段、没有字母的文本、超过 10 000 字符的文本不支持")
    func textRules() {
        #expect(reason(Fixtures.text("func a() {\n    return 1\n}")) == .code)
        #expect(reason(Fixtures.text("12:30 — 2026-09-27")) == .noText)
        #expect(reason(Fixtures.text("   \n ")) == .noText)
        #expect(reason(Fixtures.text(String(repeating: "a", count: 10_000))) == nil)
        #expect(reason(Fixtures.text(String(repeating: "a", count: 10_001))) == .tooLong)
    }

    @Test("图片：最长边 ≤ 8192 且面积 ≤ 7680×4320 才可翻译")
    func imageSize() {
        #expect(reason(Fixtures.image(name: "a.png", width: 5120, height: 2880)) == nil)
        #expect(reason(Fixtures.image(name: "a.png", width: 7680, height: 4320)) == nil)
        #expect(reason(Fixtures.image(name: "a.png", width: 8193, height: 100)) == .imageTooLarge)
        #expect(reason(Fixtures.image(name: "a.png", width: 7681, height: 4320)) == .imageTooLarge)
        #expect(!ClipTranslationEligibilityCheck.isImageTooLarge(width: 8192, height: 1))
    }
}

@Suite("ClipAutoTranslatePolicy 复制时自动翻译")
struct ClipAutoTranslatePolicyTests {
    private let on = ClipAutoTranslatePolicy.Conditions(isEnabled: true, isPaused: false, isLowPowerMode: false)

    private func skip(
        _ item: ClipItem, target: String = "zh-Hans", _ conditions: ClipAutoTranslatePolicy.Conditions? = nil
    )
        -> ClipAutoTranslatePolicy.Skip?
    {
        ClipAutoTranslatePolicy.skipReason(for: item, target: target, conditions: conditions ?? on)
    }

    @Test("关闭、暂停记录、低电量模式时不运行")
    func conditions() {
        let item = Fixtures.text("The quarterly report is due next Friday.")
        #expect(skip(item) == nil)
        #expect(on.allowsRunning)
        let off = ClipAutoTranslatePolicy.Conditions(isEnabled: false, isPaused: false, isLowPowerMode: false)
        let paused = ClipAutoTranslatePolicy.Conditions(isEnabled: true, isPaused: true, isLowPowerMode: false)
        let lowPower = ClipAutoTranslatePolicy.Conditions(isEnabled: true, isPaused: false, isLowPowerMode: true)
        #expect(skip(item, off) == .disabled)
        #expect(skip(item, paused) == .paused)
        #expect(skip(item, lowPower) == .lowPowerMode)
        #expect(![off, paused, lowPower].contains { $0.allowsRunning })
    }

    @Test("只翻译普通文本：链接、颜色、文件、图片、代码、疑似密钥、已缓存都跳过")
    func contentRules() {
        #expect(skip(Fixtures.text("https://example.com")) == .unsupportedKind)
        #expect(skip(Fixtures.text("#FFFFFF")) == .unsupportedKind)
        #expect(skip(Fixtures.files(["/tmp/a"])) == .unsupportedKind)
        #expect(skip(Fixtures.image(name: "a.png")) == .unsupportedKind)
        #expect(skip(Fixtures.text("let x = 1;\nlet y = 2;")) == .code)
        #expect(skip(Fixtures.text("token " + FakeSecrets.github())) == .secret)
        let cached = Fixtures.text("Hello there").translated(TranslationFixtures.text("zh-Hans"))
        #expect(skip(cached) == .cached)
        #expect(skip(cached, target: "ja") == nil)
    }

    @Test("长度 2…2000 且含字母")
    func lengthRules() {
        #expect(skip(Fixtures.text("a")) == .length)
        #expect(skip(Fixtures.text("ab")) == nil)
        #expect(skip(Fixtures.text(String(repeating: "a", count: 2000))) == nil)
        #expect(skip(Fixtures.text(String(repeating: "a", count: 2001))) == .length)
        #expect(skip(Fixtures.text("12 34")) == .noLetters)
    }

    @Test("源语言：检测不出或置信度 < 0.8 跳过；与目标语言相同跳过（按语言与文字比较）")
    func languageRules() {
        #expect(ClipAutoTranslatePolicy.languageSkipReason(source: "en", confidence: 0.95, target: "zh-Hans") == nil)
        #expect(
            ClipAutoTranslatePolicy.languageSkipReason(source: "en", confidence: 0.79, target: "zh-Hans")
                == .uncertainLanguage)
        #expect(
            ClipAutoTranslatePolicy.languageSkipReason(source: nil, confidence: 1, target: "zh-Hans")
                == .uncertainLanguage)
        #expect(
            ClipAutoTranslatePolicy.languageSkipReason(source: "en-GB", confidence: 0.9, target: "en") == .sameLanguage)
        #expect(
            ClipAutoTranslatePolicy.languageSkipReason(source: "zh-Hant", confidence: 0.9, target: "zh-Hans") == nil)
    }

    @Test("语言比较：补全为最大形式后比较语言与文字；无法识别的一律不同")
    func languageMatch() {
        #expect(ClipLanguageMatch.isSameLanguage("zh", "zh-Hans"))
        #expect(ClipLanguageMatch.isSameLanguage("zh-CN", "zh-Hans"))
        #expect(ClipLanguageMatch.isSameLanguage("zh-TW", "zh-Hant"))
        #expect(!ClipLanguageMatch.isSameLanguage("zh-Hans", "zh-Hant"))
        #expect(ClipLanguageMatch.isSameLanguage("en-US", "en"))
        #expect(!ClipLanguageMatch.isSameLanguage("sr-Latn", "sr"))
        #expect(!ClipLanguageMatch.isSameLanguage("", ""))
        #expect(!ClipLanguageMatch.isSameLanguage("en", "ja"))
    }

    // MARK: - 调度

    private let start = Fixtures.baseDate

    @Test("复制后等 0.5 s 才开始；只留最新一条待办")
    func delayAndKeepLatest() {
        let first = UUID()
        let second = UUID()
        let queue = ClipAutoTranslateQueue.idle.enqueueing(first, copiedAt: start)
        #expect(queue.nextStep(now: start) == .wait(0.5))
        let replaced = queue.enqueueing(second, copiedAt: start.addingTimeInterval(0.25))
        #expect(replaced.pending?.id == second)
        #expect(replaced.nextStep(now: start.addingTimeInterval(0.5)) == .wait(0.25))
        #expect(replaced.nextStep(now: start.addingTimeInterval(0.75)) == .start(second))
        #expect(ClipAutoTranslateQueue.idle.nextStep(now: start) == .idle)
    }

    @Test("串行：进行中时等它结束；两次之间至少间隔 1 s（从上一次结束算起）")
    func serialAndInterval() {
        let first = UUID()
        let second = UUID()
        let running = ClipAutoTranslateQueue.idle.enqueueing(first, copiedAt: start).starting()
        #expect(running.running == first && running.pending == nil)
        let queued = running.enqueueing(second, copiedAt: start.addingTimeInterval(1))
        #expect(queued.nextStep(now: start.addingTimeInterval(5)) == .busy)
        let finished = queued.finishing(at: start.addingTimeInterval(2))
        #expect(finished.running == nil)
        #expect(finished.nextStep(now: start.addingTimeInterval(2.25)) == .wait(0.75))
        #expect(finished.nextStep(now: start.addingTimeInterval(3)) == .start(second))
        // 时钟回拨时等待不超过各自的时长
        #expect(finished.nextStep(now: start.addingTimeInterval(-100)) == .wait(1))
    }

    @Test("关闭或暂停时丢弃排队的条目，进行中的保持到调用方结束它")
    func cancelPending() {
        let id = UUID()
        let queue = ClipAutoTranslateQueue.idle.enqueueing(id, copiedAt: start)
        #expect(queue.cancellingPending() == .idle)
        let running = queue.starting().enqueueing(UUID(), copiedAt: start).cancellingPending()
        #expect(running.running == id && running.pending == nil)
        #expect(ClipAutoTranslateQueue.idle.starting() == .idle)
        #expect(ClipAutoTranslatePolicy.timeout == 10)
    }
}
