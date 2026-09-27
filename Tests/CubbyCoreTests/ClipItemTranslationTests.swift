import Foundation
import Testing
@testable import CubbyCore

/// ClipItem.translations：不可变更新、各种更新保留译文、blob 名、查询与匹配
@Suite("ClipItem 译文缓存 translations")
struct ClipItemTranslationTests {
    private let item = Fixtures.text("Hello world", favorite: true)
    private let chinese = TranslationFixtures.text("zh-Hans", segments: ["\u{4F60}\u{597D}\u{4E16}\u{754C}"])
    private let japanese = TranslationFixtures.text("ja", segments: ["\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}"])

    // MARK: - 不可变更新

    @Test("默认为 nil；withTranslations 返回新值，其余字段不变且不修改原值")
    func withTranslationsIsNonMutating() {
        #expect(item.translations == nil)
        #expect(!item.hasTranslations)
        let translated = item.translated(chinese)
        #expect(item.translations == nil)
        #expect(translated.translations?.entries == [chinese])
        #expect(translated.hasTranslations)
        #expect(translated.withTranslations(nil) == item)
        #expect(translated.id == item.id && translated.isFavorite && translated.payload == item.payload)
    }

    @Test("收藏、刷新时间、设置格式名、设置识别文字都保留译文")
    func otherUpdatesKeepTranslations() {
        let translated = item.translated(chinese)
        #expect(translated.withFavorite(false).translations == translated.translations)
        #expect(translated.touched(at: Fixtures.baseDate.addingTimeInterval(5)).translations == translated.translations)
        #expect(translated.withFormatsName("f.formats").translations == translated.translations)
        #expect(translated.withRecognizedText("x").translations == translated.translations)
    }

    @Test("replacing：新条目没有译文时沿用旧条目的；新条目自带译文时取新值")
    func replacingInheritsTranslations() {
        let old = item.translated(chinese)
        let fresh = Fixtures.text("Hello world", at: Fixtures.baseDate.addingTimeInterval(60))
        #expect(fresh.replacing(old).translations == old.translations)
        #expect(fresh.translated(japanese).replacing(old).translations?.entries == [japanese])
        #expect(fresh.replacing(item).translations == nil)
    }

    @Test("replacing：富文本格式变了不沿用译文（按段落对齐的译文可能错位），格式相同则沿用")
    func replacingDropsTranslationsWhenFormatsChange() {
        let old = Fixtures.text("Rich", formatsName: "a.formats").translated(chinese)
        let sameFormats = Fixtures.text("Rich", formatsName: "a.formats")
        let otherFormats = Fixtures.text("Rich", formatsName: "b.formats")
        let plain = Fixtures.text("Rich")
        #expect(sameFormats.replacing(old).translations == old.translations)
        #expect(otherFormats.replacing(old).translations == nil)
        #expect(plain.replacing(old).translations == nil)
    }

    // MARK: - blob

    @Test("译后图片并入 blobNames（删除、撤销、清理孤立文件随之覆盖）；文本译文不产生 blob")
    func blobNamesIncludeTranslatedImages() {
        let image = Fixtures.image(name: "i.png").translated(
            TranslationFixtures.image("zh-Hans", blob: "t1.png"), TranslationFixtures.image("ja", blob: "t2.png"))
        #expect(image.blobNames == ["i.png", "t1.png", "t2.png"])
        #expect(image.translatedImageNames == ["t1.png", "t2.png"])
        #expect(Set(image.storedBlobNames) == ["i.png", "t1.png", "t2.png", ImageThumbnail.name(forImage: "i.png")])
        #expect(item.translated(chinese).blobNames.isEmpty)
        #expect(ClipHistory(items: [image]).blobNames == ["i.png", "t1.png", "t2.png"])
    }

    // MARK: - 查询与匹配

    @Test("translation(for:) 按目标语言取；搜索文字按语言换行拼接，富文本译文去掉行内标记")
    func lookupAndSearchText() {
        let rich = TranslationFixtures.text(
            "fr", segments: ["**Bonjour** [monde](https://a.b)", nil, "`x`"], markup: true)
        let translated = item.translated(chinese, rich)
        #expect(translated.translation(for: "fr") == rich)
        #expect(translated.translation(for: "de") == nil)
        #expect(translated.translationSearchText == "\u{4F60}\u{597D}\u{4E16}\u{754C}\nBonjour monde\nx")
        #expect(item.translationSearchText == nil)
        let empty = item.translated(TranslationFixtures.text("de", segments: [nil]))
        #expect(empty.translationSearchText == nil)
    }

    @Test("matches(keyword:) 与 translationMatches 命中译文，忽略大小写与变音符")
    func matchesTranslation() {
        let translated = item.translated(TranslationFixtures.text("fr", segments: ["Caf\u{00E9} cr\u{00E8}me"]))
        #expect(translated.matches(keyword: "CAFE"))
        #expect(translated.translationMatches("creme"))
        #expect(!translated.translationMatches("hello"))
        #expect(!item.matches(keyword: "cafe"))
    }

    @Test("translationMatch：只有借助译文才能命中时给出补上关键词的第一种语言，原文已命中时为 nil")
    func translationMatchPicksLanguage() {
        let translated = item.translated(chinese, japanese)
        #expect(translated.translationMatch(keywords: ["hello"]) == nil)
        #expect(translated.translationMatch(keywords: ["\u{4E16}\u{754C}"]) == chinese)
        #expect(translated.translationMatch(keywords: ["hello", "\u{3053}\u{3093}"]) == japanese)
        #expect(translated.translationMatch(keywords: ["\u{4E16}\u{754C}", "\u{3053}\u{3093}"]) == chinese)
        #expect(translated.translationMatch(keywords: ["zzz"]) == nil)
        #expect(translated.translationMatch(keywords: ["\u{4E16}\u{754C}", "zzz"]) == nil)
        #expect(item.translationMatch(keywords: ["\u{4E16}\u{754C}"]) == nil)
    }

    @Test("图片识别文字能命中的关键词不需要译文")
    func translationMatchConsidersImageText() {
        let image = Fixtures.image(name: "a.png").withRecognizedText("Invoice")
            .translated(TranslationFixtures.image(blob: "t.png", segments: ["\u{53D1}\u{7968}"]))
        #expect(image.translationMatch(keywords: ["invoice"]) == nil)
        #expect(image.translationMatch(keywords: ["\u{53D1}\u{7968}"])?.imageName == "t.png")
    }

    // MARK: - 派生值

    @Test("length 按 UTF-16 码元计各段之和，未翻译的段不计；withImageName 只换文件名")
    func derivedValues() {
        let translation = TranslationFixtures.text(segments: ["ab", nil, "\u{4F60}", "\u{1F600}"])
        #expect(translation.length == 5)
        let named = translation.withImageName("x.png")
        #expect(named.imageName == "x.png")
        #expect(named.withImageName(nil) == translation)
    }
}
