import Foundation
import Testing
@testable import CubbyCore

/// 复制时自动翻译的判定：状态与内容的初筛 → 检测源语言 → 定目标语言 → 置信度、同一语言与缓存
@Suite("复制时自动翻译的判定")
struct ClipAutoTranslateDecisionTests {
    private typealias Conditions = ClipAutoTranslatePolicy.Conditions

    private let on = Conditions(isEnabled: true, isPaused: false, isLowPowerMode: false)
    private let english = "Please review the attached proposal before our meeting on Thursday afternoon."
    private let chinese =
        "\u{8BF7}\u{5728}\u{5468}\u{56DB}\u{4E0B}\u{5348}\u{5F00}\u{4F1A}\u{524D}\u{770B}\u{4E00}\u{4E0B}\u{9644}\u{4EF6}\u{91CC}\u{7684}\u{65B9}\u{6848}\u{3002}"

    private func decide(
        _ item: ClipItem, shared: String? = nil, preferred: [String] = ["zh-Hans", "en"], conditions: Conditions? = nil
    ) -> ClipAutoTranslateDecision {
        ClipAutoTranslateDecision.decide(for: item, shared: shared, preferred: preferred, conditions: conditions ?? on)
    }

    @Test("外文按自动规则译为首选语言；中文译为英语")
    func translates() {
        #expect(
            decide(Fixtures.text(english)) == .translate(TranslationLanguages(source: "en", target: "zh-Hans")))
        #expect(decide(Fixtures.text(chinese)) == .translate(TranslationLanguages(source: "zh-Hans", target: "en")))
        #expect(
            decide(Fixtures.text(english), shared: "ja")
                == .translate(TranslationLanguages(source: "en", target: "ja")))
    }

    @Test("状态：关闭、暂停记录、低电量模式都跳过")
    func conditions() {
        let item = Fixtures.text(english)
        #expect(
            decide(item, conditions: Conditions(isEnabled: false, isPaused: false, isLowPowerMode: false))
                == .skip(.disabled))
        #expect(
            decide(item, conditions: Conditions(isEnabled: true, isPaused: true, isLowPowerMode: false))
                == .skip(.paused))
        #expect(
            decide(item, conditions: Conditions(isEnabled: true, isPaused: false, isLowPowerMode: true))
                == .skip(.lowPowerMode))
    }

    @Test("内容：链接、代码、疑似密钥、过短与没有字母的都跳过")
    func contentRules() {
        #expect(decide(Fixtures.text("https://example.com/a")) == .skip(.unsupportedKind))
        #expect(decide(Fixtures.image(name: "a.png")) == .skip(.unsupportedKind))
        #expect(decide(Fixtures.text("func a() {\n    return 1\n}")) == .skip(.code))
        #expect(decide(Fixtures.text("token " + FakeSecrets.github())) == .skip(.secret))
        #expect(decide(Fixtures.text("a")) == .skip(.length))
        #expect(decide(Fixtures.text("12 + 34 = 46")) == .skip(.noLetters))
    }

    @Test("语言：无法判断、已是目标语言、自动规则找不到不同语言都跳过")
    func languageRules() {
        #expect(decide(Fixtures.text("OK ok")) == .skip(.uncertainLanguage))
        #expect(decide(Fixtures.text(english), shared: "en-US") == .skip(.sameLanguage))
        #expect(decide(Fixtures.text(english), preferred: ["en"]) == .skip(.sameLanguage))
    }

    @Test("缓存：已有该目标语言的译文时跳过；只有其他语言的译文时照常翻译")
    func cache() {
        let cached = Fixtures.text(english).translated(TranslationFixtures.text("zh-Hans"))
        #expect(decide(cached) == .skip(.cached))
        let other = Fixtures.text(english).translated(TranslationFixtures.text("ja"))
        #expect(decide(other) == .translate(TranslationLanguages(source: "en", target: "zh-Hans")))
    }

    @Test("初筛不检测语言、不查缓存：合格条目为 nil，其余给出原因")
    func precheck() {
        let cached = Fixtures.text(english).translated(TranslationFixtures.text("zh-Hans"))
        #expect(ClipAutoTranslateDecision.precheck(cached, conditions: on) == nil)
        #expect(ClipAutoTranslateDecision.precheck(Fixtures.text("OK ok"), conditions: on) == nil)
        #expect(ClipAutoTranslateDecision.precheck(Fixtures.text("https://a.b/c"), conditions: on) == .unsupportedKind)
        let paused = Conditions(isEnabled: true, isPaused: true, isLowPowerMode: false)
        #expect(ClipAutoTranslateDecision.precheck(Fixtures.text(english), conditions: paused) == .paused)
    }
}
