import Foundation
import Testing
@testable import CubbyCore

@Suite("翻译语言：规范化与语言表")
struct TranslationLanguageCatalogTests {
    @Test(
        "BCP-47 规范化：中文按文字区分简繁，其他语言只保留语言代码",
        arguments: [
            ("zh-Hans-CN", "zh-Hans"), ("zh-CN", "zh-Hans"), ("zh", "zh-Hans"), ("zh-SG", "zh-Hans"),
            ("zh-Hant", "zh-Hant"), ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-MO", "zh-Hant"),
            ("zh-Hant-TW", "zh-Hant"), ("zh_TW", "zh-Hant"), ("en-US", "en"), ("en-GB", "en"), ("EN", "en"),
            ("pt-BR", "pt"), ("ja-JP", "ja"), ("sr-Latn", "sr"), (" fr ", "fr"),
        ])
    func normalizes(_ input: String, _ expected: String) {
        #expect(TranslationLanguageCatalog.normalize(input) == expected)
    }

    @Test("空串、未定语言无法规范化", arguments: ["", "   ", "und"])
    func rejectsUnknown(_ input: String) {
        #expect(TranslationLanguageCatalog.normalize(input) == nil)
    }

    @Test("语言表共 15 种，规范顺序以简体中文开头、阿拉伯语结尾")
    func supportedList() {
        let list = TranslationLanguageCatalog.supported
        #expect(list.count == 15)
        #expect(list.first == "zh-Hans")
        #expect(list.last == "ar")
        #expect(Set(list).count == list.count)
    }

    @Test("选单顺序：首选语言按系统顺序排在最前，其余保持规范顺序")
    func selectableOrder() {
        let list = TranslationLanguageCatalog.selectable(preferred: ["ja-JP", "en-US", "zh-Hant-TW", "en-GB"])
        #expect(Array(list.prefix(3)) == ["ja", "en", "zh-Hant"])
        #expect(Array(list.dropFirst(3).prefix(2)) == ["zh-Hans", "ko"])
        #expect(list.count == 15)
    }

    @Test("不在语言表中的首选语言被忽略")
    func selectableIgnoresUnsupported() {
        let list = TranslationLanguageCatalog.selectable(preferred: ["sv-SE", "", "fr-CA"])
        #expect(list.first == "fr")
        #expect(list == ["fr"] + TranslationLanguageCatalog.supported.filter { $0 != "fr" })
    }

    @Test("本名：用该语言书写自己的名字")
    func nativeNames() {
        #expect(TranslationLanguageCatalog.nativeName(of: "ja") == "日本語")
        #expect(TranslationLanguageCatalog.nativeName(of: "zh-Hans") == "简体中文")
        #expect(TranslationLanguageCatalog.nativeName(of: "zh-Hant") == "繁體中文")
        #expect(TranslationLanguageCatalog.nativeName(of: "en") == "English")
    }

    @Test("按界面语言显示语言名")
    func localizedNames() {
        #expect(TranslationLanguageCatalog.localizedName(of: "ja", locale: Locale(identifier: "en")) == "Japanese")
        #expect(TranslationLanguageCatalog.localizedName(of: "ja", locale: Locale(identifier: "zh-Hans")) == "日语")
    }
}

@Suite("翻译语言：源语言检测与目标解析")
struct TranslationTargetResolverTests {
    private let english = "Save your changes before closing the window. Your settings will be synced to all devices."
    private let simplified = "关闭窗口前请保存更改，你的设置会同步到所有设备上。"
    private let traditional = "關閉視窗前請儲存變更，你的設定會同步到所有裝置上。"

    @Test("能检测出英语、简体中文、繁体中文")
    func detectsSource() {
        #expect(TranslationTargetResolver.detectSource(english) == "en")
        #expect(TranslationTargetResolver.detectSource(simplified) == "zh-Hans")
        #expect(TranslationTargetResolver.detectSource(traditional) == "zh-Hant")
    }

    @Test("无字母或过短无法判断时为 nil", arguments: ["", "12:30 ¥99", "Hi"])
    func undeterminedSource(_ sample: String) {
        #expect(TranslationTargetResolver.detectSource(sample) == nil)
    }

    @Test("候选按置信度排序、规范化且不重复；maximum 为 0 时为空")
    func candidates() {
        let candidates = TranslationTargetResolver.sourceCandidates(english, maximum: 3)
        #expect(candidates.first?.language == "en")
        #expect(candidates.map(\.confidence) == candidates.map(\.confidence).sorted(by: >))
        #expect(Set(candidates.map(\.language)).count == candidates.count)
        #expect(TranslationTargetResolver.sourceCandidates(english, maximum: 0).isEmpty)
    }

    @Test("用户选定的目标优先（规范化后返回），并附带检测到的源语言")
    func chosenTarget() {
        let languages = TranslationTargetResolver.languages(chosen: "ja-JP", preferred: ["zh-Hans-CN"], sample: english)
        #expect(languages == TranslationLanguages(source: "en", target: "ja"))
    }

    @Test("选定值无效时按自动处理")
    func invalidChosenFallsBackToAutomatic() {
        let languages = TranslationTargetResolver.languages(chosen: "", preferred: ["zh-Hans-CN"], sample: english)
        #expect(languages == TranslationLanguages(source: "en", target: "zh-Hans"))
    }

    @Test("自动：首选语言中第一个与源语言不同的")
    func automaticPicksFirstDifferentPreferred() {
        let languages = TranslationTargetResolver.languages(
            chosen: nil, preferred: ["zh-Hans-CN", "en-US"], sample: simplified)
        #expect(languages == TranslationLanguages(source: "zh-Hans", target: "en"))

        let fromEnglish = TranslationTargetResolver.languages(
            chosen: nil, preferred: ["en-US", "ja-JP"], sample: english)
        #expect(fromEnglish == TranslationLanguages(source: "en", target: "ja"))
    }

    @Test("自动：首选语言都与源语言相同时译为英语")
    func automaticFallsBackToEnglish() {
        let languages = TranslationTargetResolver.languages(chosen: nil, preferred: ["zh-Hans-CN"], sample: simplified)
        #expect(languages == TranslationLanguages(source: "zh-Hans", target: "en"))
    }

    @Test("自动：原文是英语且首选语言全是英语时返回 nil")
    func automaticReturnsNilForAllEnglish() {
        #expect(
            TranslationTargetResolver.languages(chosen: nil, preferred: ["en-US", "en-GB"], sample: english) == nil)
        #expect(TranslationTargetResolver.languages(chosen: nil, preferred: [], sample: english) == nil)
    }

    @Test("自动：简繁视为不同语言")
    func automaticDistinguishesScripts() {
        let languages = TranslationTargetResolver.languages(chosen: nil, preferred: ["zh-Hant-TW"], sample: simplified)
        #expect(languages == TranslationLanguages(source: "zh-Hans", target: "zh-Hant"))
    }

    @Test("源语言无法判断时：目标取第一个首选语言，没有首选语言时为英语")
    func automaticWithUnknownSource() {
        #expect(
            TranslationTargetResolver.languages(chosen: nil, preferred: ["de-DE"], sample: "OK")
                == TranslationLanguages(source: nil, target: "de"))
        #expect(
            TranslationTargetResolver.languages(chosen: nil, preferred: [], sample: "OK")
                == TranslationLanguages(source: nil, target: "en"))
    }
}
