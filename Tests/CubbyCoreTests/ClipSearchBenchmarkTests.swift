import Foundation
import Testing
@testable import CubbyCore

/// 搜索性能与折叠语义的重型校验（只在设置 CUBBY_BENCH=1 时运行；建议 release：
/// `CUBBY_BENCH=1 swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG --filter ClipSearchBenchmark`）。
/// 数据集用 PerfDataGen 生成的 /tmp/cubby-perf-2000（重度）与 /tmp/cubby-perf-2000light（典型），不存在时跳过
@Suite(
    "ClipSearchBenchmark 逐键搜索", .enabled(if: ProcessInfo.processInfo.environment["CUBBY_BENCH"] != nil),
    .serialized)
@MainActor
struct ClipSearchBenchmarkTests {
    private static let datasets = ["2000", "2000light"]
    /// 逐字输入与几种典型查询
    private static let typing = ["c", "ca", "cac", "cach", "cache"]
    private static let queries = [
        "zzqx", "\u{6027}\u{80FD}", "error timeout", "Safari", "https", "\u{7B2C} 5", "invoice",
    ]

    private func load(_ name: String) -> [ClipItem]? {
        let url = URL(fileURLWithPath: "/tmp/cubby-perf-\(name)/history.json")
        return (try? Data(contentsOf: url)).flatMap { try? HistoryMigrator.migrate($0).history.items }
    }

    private func milliseconds(runs: Int = 5, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        body()
        var best = Duration.seconds(1000)
        for _ in 0..<runs {
            let start = clock.now
            body()
            best = min(best, clock.now - start)
        }
        return Double(best.components.attoseconds) / 1e15 + Double(best.components.seconds) * 1000
    }

    @Test("每键耗时：逐条匹配 vs 索引 vs 索引 + 逐键收窄；索引构建与增量更新")
    func perKeystroke() async throws {
        for name in Self.datasets {
            guard let items = load(name) else { continue }
            var index: ClipSearchIndex?
            let build = milliseconds(runs: 3) { index = ClipSearchIndex(items: items) }
            let built = try #require(index)
            let fresh = Fixtures.text("fresh cache entry")
            let update = milliseconds { _ = built.updated(for: [fresh] + items) }
            var lines = [
                String(
                    format: "BENCH %@ (%d items): build %.1f ms, update +1 %.2f ms", name, items.count, build, update)
            ]
            for text in Self.typing + Self.queries {
                let query = ClipQuery(text: text)
                var hits = 0
                let raw = milliseconds(runs: 3) { hits = ClipFilter.apply(items, query: query).count }
                let indexed = milliseconds { _ = ClipFilter.apply(items, query: query, index: built) }
                #expect(ClipFilter.apply(items, query: query, index: built) == ClipFilter.apply(items, query: query))
                lines.append(String(format: "  '%@' %d hits: raw %.1f ms, index %.2f ms", text, hits, raw, indexed))
            }
            let typed = try await typingTotals(items)
            lines.append(
                String(
                    format: "  typing 'cache' total: raw %.1f ms, session (index + narrowing) %.2f ms", typed.raw,
                    typed.session))
            print(lines.joined(separator: "\n"))
        }
    }

    /// 连续输入 "cache" 五个键的总耗时（会话含索引与收窄）
    private func typingTotals(_ items: [ClipItem]) async throws -> (raw: Double, session: Double) {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let storage = InMemoryHistoryStorage(initial: ClipHistory(items: items))
        let store = StoreFactory.make(dir: dir, storage: storage, limit: 5000)
        await store.waitForSearchIndex()
        let raw = milliseconds(runs: 3) {
            for text in Self.typing { _ = ClipFilter.apply(items, query: ClipQuery(text: text)) }
        }
        let session = milliseconds(runs: 3) {
            var search = ClipSearchSession()
            for text in Self.typing { _ = search.results(for: ClipQuery(text: text), in: store) }
        }
        return (raw, session)
    }

    @Test("逐字符穷举：折叠语义不一致的字符都已被条目标记或查询回退覆盖")
    func exhaustiveScalarAudit() {
        let probes = Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
        var entryMissed: [UInt32] = []
        var queryMissed: [UInt32] = []
        for value in UInt32(0xA0)...UInt32(0x2FFFF) {
            guard let scalar = Unicode.Scalar(value), Self.isAssigned(scalar) else { continue }
            let character = String(Character(scalar))
            let index = ClipSearchIndex(items: [Fixtures.text(character)])
            let entryDiverges = probes.contains { probe in
                let query = ClipQuery(text: probe)
                return ClipFilter.apply([Fixtures.text(character)], query: query, index: index).count
                    != ClipFilter.apply([Fixtures.text(character)], query: query).count
            }
            if entryDiverges { entryMissed.append(value) }
            let asciiItems =
                probes.map { Fixtures.text($0) } + [
                    Fixtures.text(character.folding(options: SearchFolding.options, locale: .current))
                ]
            let asciiIndex = ClipSearchIndex(items: asciiItems)
            let query = ClipQuery(text: character)
            if ClipFilter.apply(asciiItems, query: query, index: asciiIndex)
                != ClipFilter.apply(asciiItems, query: query)
            {
                queryMissed.append(value)
            }
        }
        print("BENCH scalar audit: entry-side misses \(entryMissed.count), query-side misses \(queryMissed.count)")
        #expect(entryMissed.isEmpty, "\(entryMissed.prefix(20).map { String(format: "U+%04X", $0) })")
        #expect(queryMissed.isEmpty, "\(queryMissed.prefix(20).map { String(format: "U+%04X", $0) })")
    }

    private static func isAssigned(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .unassigned, .control, .surrogate, .privateUse, .format: false
        default: true
        }
    }
}
