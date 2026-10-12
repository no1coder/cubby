import Foundation
import Testing
@testable import CubbyCore

@Suite("安全记录读写")
struct SecurityLogStoreTests {
    /// ISO-8601 只保存到秒，测试用整秒时间
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func sampleLog() -> SecurityLog {
        SecurityLog(entries: [
            SecurityLogEntry(
                date: date, event: .tampered, kind: .bitcoin, summary: "1A1zP1\u{2026}DivfNa", appName: "Wallet",
                tamperedItemID: UUID()),
            SecurityLogEntry(
                date: date.addingTimeInterval(-60), event: .pasteVerified, kind: .bankCard, summary: "4111\u{2026}1111",
                appName: nil),
            SecurityLogEntry(
                date: date.addingTimeInterval(-90), event: .dismissed, kind: .ethereum, summary: "0x5aAe\u{2026}eAed",
                appName: "Safari", relatedEntryID: UUID()),
        ])
    }

    @Test("文件位于数据目录下的 security-log.json")
    func url() {
        let directory = URL(fileURLWithPath: "/tmp/cubby-data", isDirectory: true)
        #expect(SecurityLogStore(directory: directory).url.lastPathComponent == "security-log.json")
        #expect(SecurityLogStore(directory: directory).url.deletingLastPathComponent().path == directory.path)
    }

    @Test("保存后读回一致，自动创建目录，文件仅本人可读写")
    func roundTrip() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = SecurityLogStore(directory: root.appendingPathComponent("nested/data", isDirectory: true))
        let log = sampleLog()

        try store.save(log)

        #expect(store.load() == log)
        #expect(try TempDirectory.permissions(of: store.url) == PrivateFiles.filePermissions)
    }

    @Test("日期以 ISO-8601 字符串保存")
    func iso8601() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = SecurityLogStore(directory: root)
        try store.save(sampleLog())
        let json = try String(contentsOf: store.url, encoding: .utf8)
        #expect(json.contains("\"2026-09-21T"))
    }

    @Test("覆盖保存")
    func overwrites() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = SecurityLogStore(directory: root)
        try store.save(sampleLog())
        try store.save(SecurityLog())
        #expect(store.load() == SecurityLog())
    }

    @Test("文件不存在或损坏时读到空记录")
    func missingOrCorrupt() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = SecurityLogStore(directory: root)
        #expect(store.load().entries.isEmpty)
        try Data("not json".utf8).write(to: store.url)
        #expect(store.load().entries.isEmpty)
    }

    @Test("目录位置被文件占用时保存抛错")
    func saveFails() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let blocker = root.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        #expect(throws: (any Error).self) {
            try SecurityLogStore(directory: blocker).save(sampleLog())
        }
    }

    @Test("旧版本写入的记录没有 relatedEntryID：按 nil 读出")
    func decodesOlderEntries() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = SecurityLogStore(directory: root)
        let json = """
            {"entries":[{"appName":"Wallet","date":"2026-09-21T12:53:20Z","event":"dismissed",\
            "id":"5EC0E0D0-0000-4000-8000-000000000009","kind":"tron","summary":"TLa2f6...YjU7"}]}
            """
        try Data(json.utf8).write(to: store.url)
        let entry = try #require(store.load().entries.first)
        #expect(entry.event == .dismissed)
        #expect(entry.relatedEntryID == nil)
        #expect(entry.tamperedItemID == nil)
    }
}
