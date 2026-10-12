import Foundation
import Testing
@testable import CubbyCore

/// 绳上的条目（docs/UI-UPGRADE-PLAN.md 第 5 节）：顺序、去重、容量 12、取下与随历史清理
@Suite("Clothesline 绳上条目")
struct ClotheslineTests {
    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    @Test("空绳")
    func empty() {
        let line = Clothesline()
        #expect(line.isEmpty)
        #expect(line.count == 0)
        #expect(!line.contains(UUID()))
    }

    @Test("容量为 12")
    func capacity() {
        #expect(Clothesline.capacity == 12)
    }

    @Test("初始化时去重，保留第一次出现的位置")
    func initDeduplicates() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        #expect(Clothesline(itemIDs: [a, b, a, c, b]).itemIDs == [a, b, c])
    }

    @Test("初始化时超过容量只保留最右端（最新）的 12 个")
    func initKeepsNewest() {
        let all = ids(15)
        let line = Clothesline(itemIDs: all)
        #expect(line.itemIDs == Array(all.suffix(12)))
    }

    @Test("挂上的条目在最右端，不取下任何条目")
    func hangingAppends() {
        let (a, b) = (UUID(), UUID())
        let result = Clothesline(itemIDs: [a]).hanging(b)
        #expect(result.line.itemIDs == [a, b])
        #expect(result.dropped.isEmpty)
        #expect(result.line.contains(b))
    }

    @Test("已在绳上的再挂一次移到最右端，数量不变")
    func rehangingMovesToEnd() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let result = Clothesline(itemIDs: [a, b, c]).hanging(a)
        #expect(result.line.itemIDs == [b, c, a])
        #expect(result.dropped.isEmpty)
    }

    @Test("挂满后再挂：取下最左端（最早挂上）的那张")
    func hangingOverflowDropsOldest() {
        let full = ids(12)
        let newcomer = UUID()
        let result = Clothesline(itemIDs: full).hanging(newcomer)
        #expect(result.line.count == 12)
        #expect(result.line.itemIDs.last == newcomer)
        #expect(result.dropped == [full[0]])
        #expect(!result.line.contains(full[0]))
    }

    @Test("挂满后把已在绳上的再挂一次：只调整顺序，不取下")
    func rehangingWhenFull() {
        let full = ids(12)
        let result = Clothesline(itemIDs: full).hanging(full[3])
        #expect(result.line.count == 12)
        #expect(result.line.itemIDs.last == full[3])
        #expect(result.dropped.isEmpty)
    }

    @Test("取下指定条目，其余顺序不变；取下不在绳上的条目无影响")
    func removing() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let line = Clothesline(itemIDs: [a, b, c])
        #expect(line.removing(b).itemIDs == [a, c])
        #expect(line.removing(UUID()) == line)
    }

    @Test("只保留仍在历史中的条目")
    func retaining() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let line = Clothesline(itemIDs: [a, b, c])
        #expect(line.retaining([c, a, UUID()]).itemIDs == [a, c])
        #expect(line.retaining([]).isEmpty)
    }
}
