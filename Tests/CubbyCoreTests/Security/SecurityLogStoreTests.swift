import Foundation
import Testing
@testable import CubbyCore

@Suite("安全记录读写（加密）")
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

    private func store(_ root: URL, keyByte: UInt8 = 0x42) throws -> SecurityLogStore {
        let vault = VaultDirectory(url: root.appendingPathComponent("Vault", isDirectory: true))
        return SecurityLogStore(dataDirectory: root, vault: vault, keys: try VaultFixtures.keys(keyByte))
    }

    private func writeLegacy(_ log: SecurityLog, to store: SecurityLogStore) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(log).write(to: store.legacyURL)
    }

    @Test("加密文件位于 Vault/security-log.cubby；旧明文为数据目录下的 security-log.json")
    func locations() throws {
        let root = URL(fileURLWithPath: "/tmp/cubby-data", isDirectory: true)
        let store = try store(root)
        #expect(store.url.path == "/tmp/cubby-data/Vault/security-log.cubby")
        #expect(store.legacyURL.path == "/tmp/cubby-data/security-log.json")
    }

    @Test("保存后读回一致，文件是密文、仅本人可读写")
    func roundTrip() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        let log = sampleLog()

        try store.save(log)

        #expect(store.load() == SecurityLogStore.Loaded(log: log, allowsSaving: true))
        #expect(try TempDirectory.permissions(of: store.url) == PrivateFiles.filePermissions)
        let raw = try Data(contentsOf: store.url)
        #expect(raw.starts(with: Data("CBYV".utf8)))
        #expect(raw.range(of: Data("Wallet".utf8)) == nil)
    }

    @Test("覆盖保存")
    func overwrites() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        try store.save(sampleLog())
        try store.save(SecurityLog())
        #expect(store.load().log == SecurityLog())
    }

    @Test("文件不存在：空记录，允许保存")
    func missing() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        #expect(try store(root).load() == SecurityLogStore.Loaded(log: SecurityLog(), allowsSaving: true))
    }

    @Test("损坏或密钥不对：空记录，本次运行不允许保存，文件原样保留")
    func unreadableDisablesSaving() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        try store(root, keyByte: 0x01).save(sampleLog())
        let original = try Data(contentsOf: try store(root).url)

        let mismatched = try store(root).load()
        #expect(mismatched == SecurityLogStore.Loaded(log: SecurityLog(), allowsSaving: false))

        var tampered = original
        tampered[tampered.count - 1] ^= 0xFF
        try tampered.write(to: try store(root, keyByte: 0x01).url)
        #expect(try store(root, keyByte: 0x01).load().allowsSaving == false)
        #expect(try Data(contentsOf: try store(root).url) == tampered)
    }

    @Test("旧明文记录：加密保存后删除明文")
    func migratesLegacyFile() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        let log = sampleLog()
        try writeLegacy(log, to: store)

        #expect(store.load() == SecurityLogStore.Loaded(log: log, allowsSaving: true))
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL.path))
        #expect(FileManager.default.fileExists(atPath: store.url.path))
        #expect(store.load().log == log)
    }

    @Test("旧明文记录损坏：不保存、不删除明文")
    func corruptLegacyFileIsKept() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        try Data("not json".utf8).write(to: store.legacyURL)

        #expect(store.load() == SecurityLogStore.Loaded(log: SecurityLog(), allowsSaving: false))
        #expect(FileManager.default.fileExists(atPath: store.legacyURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test("加密文件与明文同时存在（降级期间又写了明文）：合并、保存，删除明文")
    func mergesLegacyWrittenAfterDowngrade() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        let entries = sampleLog().entries
        try store.save(SecurityLog(entries: [entries[0]]))
        try writeLegacy(SecurityLog(entries: [entries[1], entries[2]]), to: store)

        #expect(store.load().log.entries.map(\.id) == entries.map(\.id))
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL.path))
        #expect(store.load().log.entries.count == 3)
    }

    @Test("加密文件与损坏的明文同时存在：读加密文件，明文保留")
    func keepsCorruptLegacyBesideEncrypted() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        let log = sampleLog()
        try store.save(log)
        try Data("not json".utf8).write(to: store.legacyURL)

        #expect(store.load() == SecurityLogStore.Loaded(log: log, allowsSaving: true))
        #expect(FileManager.default.fileExists(atPath: store.legacyURL.path))
    }

    @Test("Vault 位置被文件占用时保存抛错")
    func saveFails() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        try Data("x".utf8).write(to: root.appendingPathComponent("Vault"))
        #expect(throws: (any Error).self) {
            try store(root).save(sampleLog())
        }
    }

    @Test("旧版本写入的记录没有 relatedEntryID：按 nil 读出")
    func decodesOlderEntries() throws {
        let root = try TempDirectory.make()
        defer { TempDirectory.remove(root) }
        let store = try store(root)
        let json = """
            {"entries":[{"appName":"Wallet","date":"2026-09-21T12:53:20Z","event":"dismissed",\
            "id":"5EC0E0D0-0000-4000-8000-000000000009","kind":"tron","summary":"TLa2f6...YjU7"}]}
            """
        try Data(json.utf8).write(to: store.legacyURL)
        let entry = try #require(store.load().log.entries.first)
        #expect(entry.event == .dismissed)
        #expect(entry.relatedEntryID == nil)
        #expect(entry.tamperedItemID == nil)
    }

    @Test("合并：按 id 去重（以自身为准），按时间从新到旧")
    func merging() {
        let entries = sampleLog().entries
        let mine = SecurityLog(entries: [entries[2], entries[0]])
        let other = SecurityLog(entries: [entries[1], entries[0]])
        #expect(mine.merging(other).entries.map(\.id) == entries.map(\.id))
        #expect(SecurityLog().merging(SecurityLog()).entries.isEmpty)
    }
}
