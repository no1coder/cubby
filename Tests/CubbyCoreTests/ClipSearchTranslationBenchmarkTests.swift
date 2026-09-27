import Foundation
import Testing
@testable import CubbyCore

/// 译文参与搜索后的逐键耗时与写入译文的耗时（只在设置 CUBBY_BENCH=1 时运行；建议 release：
/// `CUBBY_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter ClipSearchTranslationBenchmark`）。
/// 合成数据：2000 条，其中 500 条各有 3 种语言的译文，译文总量接近 1 M 字符的上限（§3 的最坏情形）
@Suite(
    "ClipSearchTranslationBenchmark 译文搜索与写入", .enabled(if: ProcessInfo.processInfo.environment["CUBBY_BENCH"] != nil),
    .serialized)
@MainActor
struct ClipSearchTranslationBenchmarkTests {
    /// 逐字输入只在译文里出现的词、正文里的词、都没有的词、跨字段的两个词
    private static let queries = [
        "t", "tr", "tran", "translated", "body", "zzqx", "\u{8BD1}\u{6587}", "words body", "item 12 translated",
    ]

    private static func dataset() -> [ClipItem] {
        let paragraph = String(
            repeating: "\u{8FD9}\u{662F}\u{4E00}\u{6BB5}\u{8BD1}\u{6587} translated words ", count: 25)
        return (0..<2000).map { index in
            let item = Fixtures.text(
                "Item \(index) " + String(repeating: "original text body ", count: 30),
                at: Fixtures.baseDate.addingTimeInterval(Double(-index)))
            guard index.isMultiple(of: 4) else { return item }
            return item.translated(
                TranslationFixtures.text("zh-Hans", segments: [paragraph, paragraph], at: Double(index)),
                TranslationFixtures.text("ja", segments: [paragraph], at: Double(index) + 0.1),
                TranslationFixtures.text(
                    "fr", segments: ["**" + paragraph + "**"], at: Double(index) + 0.2, markup: true))
        }
    }

    private func milliseconds(runs: Int = 5, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        body()
        let best = (0..<runs).map { _ in clock.measure(body) }.min() ?? .zero
        return Double(best.components.attoseconds) / 1e15 + Double(best.components.seconds) * 1000
    }

    @Test("逐键耗时：逐条匹配 vs 索引；索引构建；写入一条译文后的增量更新与上限执行")
    func perKeystroke() {
        let items = Self.dataset()
        let history = ClipHistory(items: items)
        var index: ClipSearchIndex?
        let build = milliseconds(runs: 3) { index = ClipSearchIndex(items: items) }
        guard let built = index else { return }
        let fresh = TranslationFixtures.text("de", segments: ["neuer Cache Eintrag"], at: 99_999)
        var updated = history
        let setting = milliseconds { updated = history.settingTranslation(fresh, for: items[1].id) }
        let refold = milliseconds { _ = built.updated(for: updated.items) }
        var lines = [
            String(
                format: "BENCH translation search (%d items, %d chars): build %.1f ms, set %.2f ms, refold %.2f ms",
                items.count, history.translationLength, build, setting, refold)
        ]
        for text in Self.queries {
            let query = ClipQuery(text: text)
            var hits = 0
            let raw = milliseconds(runs: 3) { hits = ClipFilter.apply(items, query: query).count }
            let indexed = milliseconds { _ = ClipFilter.apply(items, query: query, index: built) }
            #expect(ClipFilter.apply(items, query: query, index: built) == ClipFilter.apply(items, query: query))
            lines.append(String(format: "  '%@' %d hits: raw %.1f ms, index %.2f ms", text, hits, raw, indexed))
        }
        print(lines.joined(separator: "\n"))
        #expect(updated.translationLength <= ClipTranslationLimits.standard.maxTotalLength)
    }
}
