import Foundation
import Testing
@testable import CubbyCore

/// 搜索时分类栏的命中数与「只搜第一个词」（Search 画板）
@Suite("搜索命中数与只搜第一个词")
struct SearchHitCountsTests {
    private func item(_ kind: ClipKind, favorite: Bool = false) -> ClipItem {
        let payload: ClipPayload =
            switch kind {
            case .image: .image(ImageRef(name: "x.png", width: 1, height: 1))
            case .file: .files(["/tmp/x"])
            default: .text("x")
            }
        return ClipItem(
            kind: kind, payload: payload, source: nil, createdAt: Date(), isFavorite: favorite,
            contentHash: UUID().uuidString)
    }

    @Test("每个分类的命中数；「全部」为总数，收藏按收藏标记计")
    func counts() {
        let items = [
            item(.text), item(.text, favorite: true), item(.link), item(.image), item(.image), item(.image),
        ]
        let counts = ClipCategory.hitCounts(in: items)
        #expect(counts[.all] == 6)
        #expect(counts[.text] == 2)
        #expect(counts[.link] == 1)
        #expect(counts[.image] == 3)
        #expect(counts[.file] == 0)
        #expect(counts[.color] == 0)
        #expect(counts[.favorite] == 1)
    }

    @Test("每个分类都有计数（含 0）")
    func everyCategoryPresent() {
        let counts = ClipCategory.hitCounts(in: [])
        #expect(Set(counts.keys) == Set(ClipCategory.allCases))
        #expect(counts.values.allSatisfy { $0 == 0 })
    }

    @Test(
        "多个关键词时可退回只搜第一个；一个或没有关键词时没有退路",
        arguments: [
            ("invoice 2024", "invoice"),
            ("  release   notes  draft ", "release"),
            ("single", nil),
            ("   ", nil),
            ("", nil),
        ] as [(String, String?)])
    func firstKeywordFallback(_ text: String, _ expected: String?) {
        #expect(ClipQuery(text: text).firstKeywordFallback == expected)
    }
}
