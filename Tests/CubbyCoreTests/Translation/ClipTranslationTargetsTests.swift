import Foundation
import Testing
@testable import CubbyCore

/// 剪贴板翻译的语言对：翻译卡上的选择 > 粘贴目标应用记住的 > 共享目标 > 自动规则
@Suite("剪贴板翻译的目标语言")
struct ClipTranslationTargetsTests {
    private let english = "The quick brown fox jumps over the lazy dog near the river bank."
    private let chinese =
        "\u{4ECA}\u{5929}\u{5929}\u{6C14}\u{5F88}\u{597D}\u{FF0C}\u{6211}\u{4EEC}\u{53BB}\u{516C}\u{56ED}\u{6563}\u{6B65}\u{5427}\u{3002}"

    private func languages(
        explicit: String? = nil, remembered: String? = nil, shared: String? = nil, preferred: [String] = ["zh-Hans"],
        sample: String
    ) -> TranslationLanguages {
        ClipTranslationTargets.languages(
            explicit: explicit, remembered: remembered, shared: shared, preferred: preferred, sample: sample)
    }

    @Test("翻译卡上选定的目标语言优先（规范化），源语言为检测结果")
    func explicitTarget() {
        let result = languages(explicit: "en-US", remembered: "ja", shared: "fr", sample: chinese)
        #expect(result == TranslationLanguages(source: "zh-Hans", target: "en"))
    }

    @Test("粘贴目标应用记住的语言次之；与原文同一语言时不用")
    func rememberedTarget() {
        #expect(languages(remembered: "ja", shared: "fr", sample: english).target == "ja")
        #expect(languages(remembered: "en-GB", shared: "fr", sample: english).target == "fr")
        #expect(languages(remembered: "en", sample: english).target == "zh-Hans")
        // 源语言无法判断（太短）时照用记住的语言
        #expect(languages(remembered: "ja", sample: "OK") == TranslationLanguages(source: nil, target: "ja"))
    }

    @Test("共享目标语言，再次是自动规则")
    func sharedAndAutomatic() {
        #expect(languages(shared: "de", sample: english).target == "de")
        #expect(languages(sample: english) == TranslationLanguages(source: "en", target: "zh-Hans"))
        #expect(languages(sample: chinese) == TranslationLanguages(source: "zh-Hans", target: "en"))
        #expect(languages(explicit: "", remembered: "", shared: "", sample: english).target == "zh-Hans")
    }

    @Test("自动规则找不到不同的语言：目标取源语言（界面显示「原文已是」）；源语言未知时取英语")
    func alreadyInTarget() {
        let same = languages(preferred: ["en-US"], sample: english)
        #expect(same == TranslationLanguages(source: "en", target: "en"))
        #expect(ClipLanguageMatch.isSameLanguage(same.source ?? "", same.target))
        #expect(languages(preferred: [], sample: "").target == "en")
    }

    @Test("取样只用开头部分")
    func sampleLimit() {
        let head = String(repeating: english + " ", count: 70)
        #expect(head.count > ClipTranslationTargets.sampleLimit)
        let sample = head + String(repeating: chinese, count: 2000)
        #expect(languages(sample: sample).source == "en")
    }

    @Test("按应用记住的语言：规范化、丢弃无效项、记住与忘记返回新值")
    func pasteTargetLanguages() {
        let initial = ClipPasteTargetLanguages([
            "com.tinyspeck.slackmacgap": "en-US", " ": "ja", "com.apple.mail": "und", " com.apple.Notes ": "ja",
        ])
        #expect(initial.languages == ["com.tinyspeck.slackmacgap": "en", "com.apple.Notes": "ja"])
        #expect(initial.language(for: "com.tinyspeck.slackmacgap") == "en")
        #expect(initial.language(for: "com.apple.mail") == nil)

        let updated = initial.setting("zh-CN", for: "com.apple.mail").setting(nil, for: "com.apple.Notes")
        #expect(updated.languages == ["com.tinyspeck.slackmacgap": "en", "com.apple.mail": "zh-Hans"])
        #expect(initial.languages.count == 2)
        #expect(updated.sortedEntries.map(\.bundleID) == ["com.apple.mail", "com.tinyspeck.slackmacgap"])
        #expect(updated.setting("", for: "com.apple.mail").language(for: "com.apple.mail") == nil)
    }
}
