import Foundation
import Testing
@testable import CubbyCore

@Suite("安全记录")
struct SecurityLogTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86_400

    private func entry(
        _ event: SecurityLogEntry.Event, daysAgo: Double = 0, item: UUID? = nil, id: UUID = UUID()
    ) -> SecurityLogEntry {
        SecurityLogEntry(
            id: id, date: now.addingTimeInterval(-daysAgo * day), event: event, kind: .ethereum,
            summary: "0x5aAe\u{2026}eAed", appName: "Wallet", tamperedItemID: item)
    }

    @Test("常量：保留 90 天、最多 500 条")
    func constants() {
        #expect(SecurityLog.retention == 90 * day)
        #expect(SecurityLog.capacity == 500)
        #expect(SecurityLog().entries.isEmpty)
    }

    @Test("新记录插到最前面，原记录不变")
    func appendsAtFront() {
        let first = entry(.tampered, daysAgo: 1)
        let second = entry(.restored)
        let log = SecurityLog().appending(first, now: now)
        let updated = log.appending(second, now: now)
        #expect(updated.entries == [second, first])
        #expect(log.entries == [first])
    }

    @Test("超过保留期的记录被丢弃，恰好在边界上的保留")
    func dropsExpired() {
        let old = entry(.tampered, daysAgo: 90.01)
        let edge = entry(.dismissed, daysAgo: 90)
        let log = SecurityLog(entries: [edge, old]).appending(entry(.pasteVerified), now: now)
        #expect(log.entries.count == 2)
        #expect(log.entries.last == edge)
    }

    @Test("超过容量时丢掉最旧的")
    func capacity() {
        let entries = (0..<SecurityLog.capacity).map { entry(.pasteVerified, daysAgo: Double($0) / 100) }
        let newest = entry(.tampered)
        let log = SecurityLog(entries: entries).appending(newest, now: now)
        #expect(log.entries.count == SecurityLog.capacity)
        #expect(log.entries.first == newest)
        #expect(log.entries.last == entries[SecurityLog.capacity - 2])
    }

    @Test("关联到历史条目：生成新记录，id 不变，其他记录不动")
    func linking() {
        let target = entry(.tampered)
        let other = entry(.restored)
        let itemID = UUID()
        let log = SecurityLog(entries: [other, target])
        let linked = log.linking(entryID: target.id, toItem: itemID)
        #expect(linked.entries[0] == other)
        #expect(linked.entries[1].id == target.id)
        #expect(linked.entries[1].tamperedItemID == itemID)
        #expect(linked.entries[1].date == target.date)
        #expect(linked.entries[1].summary == target.summary)
        #expect(log.entries[1].tamperedItemID == nil)
        #expect(log.linking(entryID: UUID(), toItem: itemID) == log)
    }

    @Test("被替换的条目：恢复后仍禁止，「是我自己换的」后解除")
    func tamperedItemIDs() {
        let restoredItem = UUID()
        let dismissedItem = UUID()
        let pending = UUID()
        let log = SecurityLog(entries: [
            entry(.dismissed, item: dismissedItem),
            entry(.restored, item: restoredItem),
            entry(.tampered, item: restoredItem),
            entry(.tampered, item: dismissedItem),
            entry(.tampered, item: pending),
            entry(.tampered),
            entry(.pasteVerified, item: UUID()),
        ])
        #expect(log.tamperedItemIDs == [restoredItem, pending])
    }

    @Test("近 N 天统计只算被替换与粘贴核对")
    func summary() {
        let log = SecurityLog(entries: [
            entry(.tampered),
            entry(.tampered, daysAgo: 30),
            entry(.tampered, daysAgo: 30.01),
            entry(.pasteVerified, daysAgo: 2),
            entry(.pasteVerified, daysAgo: 40),
            entry(.restored),
            entry(.dismissed),
        ])
        #expect(log.summary(now: now) == SecurityLog.Summary(tampered: 2, verifiedPastes: 1))
        #expect(log.summary(days: 7, now: now) == SecurityLog.Summary(tampered: 1, verifiedPastes: 1))
        #expect(log.summary(days: 90, now: now) == SecurityLog.Summary(tampered: 3, verifiedPastes: 2))
        #expect(SecurityLog().summary(now: now) == SecurityLog.Summary(tampered: 0, verifiedPastes: 0))
    }

    @Test("仍在禁止中的 tampered 记录不会因容量被裁掉，其余从最旧的开始丢")
    func keepsBlockedTamperOverCapacity() {
        let item = UUID()
        let tampered = entry(.tampered, daysAgo: 10, item: item)
        let filler = (0..<SecurityLog.capacity).map { entry(.pasteVerified, daysAgo: Double($0) / 100) }
        let log = SecurityLog(entries: filler + [tampered]).appending(entry(.pasteVerified), now: now)
        #expect(log.entries.count == SecurityLog.capacity)
        #expect(log.entries.last == tampered)
        #expect(log.tamperedItemIDs == [item])
        #expect(!log.entries.contains(filler[SecurityLog.capacity - 1]))
    }

    @Test("仍在禁止中的 tampered 记录超过保留期也保留；解除后按期丢弃")
    func keepsBlockedTamperOverRetention() {
        let item = UUID()
        let tampered = entry(.tampered, daysAgo: 200, item: item)
        let kept = SecurityLog(entries: [tampered]).appending(entry(.pasteVerified), now: now)
        #expect(kept.entries.contains(tampered))
        #expect(kept.tamperedItemIDs == [item])

        let dismissed = entry(.dismissed, item: item)
        let released = SecurityLog(entries: [tampered]).appending(dismissed, now: now)
        #expect(released.entries == [dismissed])
        #expect(released.tamperedItemIDs.isEmpty)
    }

    @Test("没有关联条目的 tampered 记录照常按期丢弃")
    func unlinkedTamperExpires() {
        let tampered = entry(.tampered, daysAgo: 200)
        let log = SecurityLog(entries: [tampered]).appending(entry(.restored), now: now)
        #expect(!log.entries.contains(tampered))
    }

    @Test("「是我自己换的」早于入历史：关联条目时一并补上，条目不被禁止")
    func dismissedBeforeLink() {
        let tamperedID = UUID()
        let item = UUID()
        let tampered = entry(.tampered, id: tamperedID)
        let dismissed = SecurityLogEntry(
            date: now, event: .dismissed, kind: .ethereum, summary: "x", appName: nil, relatedEntryID: tamperedID)
        let log = SecurityLog(entries: [dismissed, tampered]).linking(entryID: tamperedID, toItem: item)
        #expect(log.entries.allSatisfy { $0.tamperedItemID == item })
        #expect(log.entries.first?.relatedEntryID == tamperedID)
        #expect(log.tamperedItemIDs.isEmpty)
    }
}
