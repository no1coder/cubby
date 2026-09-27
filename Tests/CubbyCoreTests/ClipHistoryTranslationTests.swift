import Foundation
import Testing
@testable import CubbyCore

/// ClipHistory.settingTranslation 与 §2.3 的上限：按语言覆盖、每条语言数、单语言 / 总量上限、无效目标
@Suite("ClipHistory 译文 settingTranslation / removingTranslations")
struct ClipHistoryTranslationTests {
    private let text = Fixtures.text("Hello world")
    private let image = Fixtures.image(name: "a.png")

    // MARK: - 写入与覆盖

    @Test("只更新目标条目，返回新实例且不修改原值，顺序与 id 不变")
    func settingIsNonMutating() {
        let other = Fixtures.text("other")
        let history = ClipHistory(items: [other, text])
        let translation = TranslationFixtures.text()

        let updated = history.settingTranslation(translation, for: text.id)

        #expect(history.items.allSatisfy { $0.translations == nil })
        #expect(updated.items.map(\.id) == [other.id, text.id])
        #expect(updated.items[1].translations?.entries == [translation])
        #expect(updated.items[0] == other)
    }

    @Test("同一目标语言再次写入即覆盖（换引擎重译），位置不变；新语言追加在后")
    func sameTargetOverwrites() {
        let first = TranslationFixtures.text("zh-Hans", segments: ["A"], at: 1)
        let japanese = TranslationFixtures.text("ja", segments: ["B"], at: 2)
        let redo = TranslationFixtures.text("zh-Hans", segments: ["C"], at: 3, engine: "DeepSeek", onDevice: false)
        let history = ClipHistory(items: [text])
            .settingTranslation(first, for: text.id)
            .settingTranslation(japanese, for: text.id)
            .settingTranslation(redo, for: text.id)
        #expect(history.items[0].translations?.entries == [redo, japanese])
    }

    @Test("每条最多 3 种语言：再加一种时淘汰 createdAt 最早的（不论位置）")
    func evictsOldestLanguage() {
        let entries = [
            TranslationFixtures.text("zh-Hans", at: 30), TranslationFixtures.text("ja", at: 10),
            TranslationFixtures.text("fr", at: 20),
        ]
        let history = ClipHistory(items: [text.withTranslations(ClipTranslations(entries))])
        let german = TranslationFixtures.text("de", at: 5)

        let updated = history.settingTranslation(german, for: text.id)

        #expect(updated.items[0].translations?.entries.map(\.target) == ["zh-Hans", "fr", "de"])
    }

    @Test("图片条目：译文必须带译后图片；文本条目：不能带")
    func imageAndTextShapes() {
        let history = ClipHistory(items: [text, image])
        let imageTranslation = TranslationFixtures.image(blob: "t.png")
        let textTranslation = TranslationFixtures.text()

        #expect(history.settingTranslation(imageTranslation, for: image.id).items[1].translations != nil)
        #expect(history.settingTranslation(textTranslation, for: image.id) == history)
        #expect(history.settingTranslation(imageTranslation, for: text.id) == history)
    }

    @Test("id 不存在、类型不支持（链接 / 文件 / 颜色）、目标语言为空或值未变时原样返回")
    func ignoresInvalidTargets() {
        let link = Fixtures.text("https://example.com")
        let color = Fixtures.text("#5F2EEA")
        let files = Fixtures.files(["/tmp/a.txt"])
        let translation = TranslationFixtures.text()
        let history = ClipHistory(items: [text.translated(translation), link, color, files])

        #expect(history.settingTranslation(TranslationFixtures.text("ja"), for: UUID()) == history)
        for item in [link, color, files] {
            #expect(history.settingTranslation(translation, for: item.id) == history, "\(item.kind)")
        }
        #expect(history.settingTranslation(TranslationFixtures.text(""), for: text.id) == history)
        #expect(history.settingTranslation(translation, for: text.id) == history)
    }

    // MARK: - 上限

    @Test("标准上限：单语言 30 000、每条 3 种、总量 1 000 000")
    func standardLimits() {
        let limits = ClipTranslationLimits.standard
        #expect(limits.maxStoredLength == 30_000)
        #expect(limits.maxLanguagesPerItem == 3)
        #expect(limits.maxTotalLength == 1_000_000)
        #expect(
            ClipTranslationLimits(maxStoredLength: 1, maxLanguagesPerItem: 0, maxTotalLength: 1).maxLanguagesPerItem
                == 1)
    }

    @Test("单种语言超过上限：不缓存（原样返回）；恰好等于上限可以缓存")
    func perLanguageLimit() {
        let history = ClipHistory(items: [text])
        let limits = ClipTranslationLimits(maxStoredLength: 10, maxLanguagesPerItem: 3, maxTotalLength: 100)
        #expect(
            history.settingTranslation(TranslationFixtures.sized("ja", length: 11), for: text.id, limits: limits)
                == history)
        #expect(
            history.settingTranslation(TranslationFixtures.sized("ja", length: 10), for: text.id, limits: limits)
                .items[0].translations != nil)
        let standard = ClipTranslationLimits.standard.maxStoredLength
        #expect(
            history.settingTranslation(TranslationFixtures.sized("ja", length: standard + 1), for: text.id) == history)
    }

    @Test("总量超限：按 createdAt 淘汰全历史最早的译文，直到不超限；不动条目，不淘汰刚写入的")
    func totalLimitEvictsOldest() {
        let limits = ClipTranslationLimits(maxStoredLength: 100, maxLanguagesPerItem: 3, maxTotalLength: 100)
        let a = Fixtures.text("a").translated(TranslationFixtures.sized("zh-Hans", length: 40, at: 1))
        let b = Fixtures.text("b").translated(
            TranslationFixtures.sized("zh-Hans", length: 30, at: 3), TranslationFixtures.sized("ja", length: 20, at: 2))
        let history = ClipHistory(items: [a, b])

        // 40 + 30 + 20 + 50 = 140：淘汰最早的 a（40）后恰好 100
        let updated = history.settingTranslation(
            TranslationFixtures.sized("fr", length: 50, at: 9), for: b.id, limits: limits)

        #expect(updated.items.map(\.id) == [a.id, b.id])
        #expect(updated.items[0].translations == nil)
        #expect(updated.items[1].translations?.entries.map(\.target) == ["zh-Hans", "ja", "fr"])
        #expect(updated.translationLength == 100)
    }

    @Test("总量超限且新写入的最早：仍保留新写入的，淘汰其余最早的")
    func totalLimitKeepsNewEntry() {
        let limits = ClipTranslationLimits(maxStoredLength: 100, maxLanguagesPerItem: 3, maxTotalLength: 50)
        let a = Fixtures.text("a").translated(TranslationFixtures.sized("ja", length: 30, at: 5))
        let b = Fixtures.text("b").translated(TranslationFixtures.sized("ja", length: 20, at: 6))
        let history = ClipHistory(items: [a, b])

        let updated = history.settingTranslation(
            TranslationFixtures.sized("de", length: 25, at: 0), for: b.id, limits: limits)

        #expect(updated.items[0].translations == nil)
        #expect(updated.items[1].translations?.entries.map(\.target) == ["ja", "de"])
        #expect(updated.translationLength == 45)
    }

    @Test("按 UTF-16 码元计总量：多字节文字不会因 UTF-8 字节数而被提前淘汰")
    func totalLimitCountsUTF16() {
        let limits = ClipTranslationLimits(maxStoredLength: 100, maxLanguagesPerItem: 3, maxTotalLength: 10)
        let a = Fixtures.text("a").translated(
            TranslationFixtures.text("ja", segments: ["\u{4F60}\u{597D}\u{4F60}\u{597D}\u{4F60}"], at: 1))
        let history = ClipHistory(items: [a, text])
        let updated = history.settingTranslation(
            TranslationFixtures.text("ja", segments: ["\u{4E16}\u{754C}\u{4E16}\u{754C}\u{4E16}"], at: 2), for: text.id,
            limits: limits)
        #expect(updated.translationLength == 10)
        #expect(updated.items.allSatisfy { $0.translations != nil })
    }

    // MARK: - 清除与合并

    @Test("removingTranslations 清除全部；本就没有时原样返回")
    func removingAll() {
        let history = ClipHistory(items: [text.translated(TranslationFixtures.text()), image, Fixtures.text("x")])
        let cleared = history.removingTranslations()
        #expect(cleared.items.allSatisfy { $0.translations == nil })
        #expect(cleared.removingTranslations() == cleared)
        #expect(history.items[0].translations != nil)
        #expect(cleared.translationLength == 0)
    }

    @Test("重复记录同一内容：合并后保留已缓存的译文")
    func reinsertKeepsTranslations() {
        let existing = text.translated(TranslationFixtures.text())
        let history = ClipHistory(items: [Fixtures.text("x"), existing])
        let again = Fixtures.text("Hello world", at: Fixtures.baseDate.addingTimeInterval(9))

        let merged = history.inserting(again, limit: 10)

        #expect(merged.items.first?.id == existing.id)
        #expect(merged.items.first?.translations == existing.translations)
    }
}
