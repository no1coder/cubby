import CryptoKit
import Foundation
import Testing
@testable import CubbyCore

/// 启动流程：密钥解析、E8 ② 改名保留与自动还原、E8 ③、迁移
@Suite("VaultLaunch 与 VaultRecovery", .timeLimit(.minutes(1)))
struct VaultLaunchTests {
    private func launch(
        _ environment: VaultEnvironment, provider: InMemoryHistoryKeyProvider, destructive: Bool = true
    ) throws -> VaultLaunch.Outcome {
        try VaultLaunch(
            dataDirectory: environment.root, provider: provider, historyLimit: 100,
            allowsDestructiveSteps: destructive
        ).run()
    }

    private func session(_ outcome: VaultLaunch.Outcome) throws -> VaultLaunch.Session {
        guard case .ready(let session) = outcome else {
            Issue.record("expected a ready vault, got \(outcome)")
            throw SimulatedCrash()
        }
        return session
    }

    private var day: Date {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 10, 13, 12)
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    @Test("新安装：生成并保存新密钥，Vault 就绪")
    func freshInstall() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let provider = InMemoryHistoryKeyProvider()
        let ready = try session(try launch(environment, provider: provider))
        let stored = try #require(provider.storedKey)
        #expect(ready.keys == (try HistoryKeys(masterKey: stored)))
        #expect(ready.quarantinedFolder == nil && !ready.migrationFailed)
    }

    @Test("钥匙串已锁定：.locked，什么都不改")
    func locked() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try environment.storage.save(ClipHistory(items: [Fixtures.text("x")]))
        let provider = InMemoryHistoryKeyProvider()
        provider.setLocked(true)
        #expect(try launch(environment, provider: provider) == .locked)
        #expect(provider.addAttempts == 0)
        #expect(FileManager.default.fileExists(atPath: environment.storage.fileURL.path))
    }

    @Test("E8 ②：密钥找不到而 Vault 有数据——改名保留、生成新密钥、从空 Vault 开始")
    func missingKeyQuarantines() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try environment.storage.save(ClipHistory(items: [Fixtures.text("old")]))
        let provider = InMemoryHistoryKeyProvider()

        let ready = try session(try launch(environment, provider: provider))
        let folder = try #require(ready.quarantinedFolder)
        #expect(folder.lastPathComponent.hasPrefix("Vault-unreadable-"))
        #expect(VaultRecovery.keyID(ofVaultAt: folder) == environment.keys.keyID)
        #expect(ready.keys != environment.keys)
        #expect(!FileManager.default.fileExists(atPath: environment.storage.fileURL.path))
    }

    @Test("E8 ③：Vault 不存在但密钥存在——直接使用已有密钥，不改名、不生成")
    func keyWithoutVault() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey())
        let ready = try session(try launch(environment, provider: provider))
        #expect(ready.keys == environment.keys)
        #expect(ready.quarantinedFolder == nil)
        #expect(provider.addAttempts == 0)
        #expect(VaultRecovery(dataDirectory: environment.root).unreadableFolders().isEmpty)
    }

    @Test("历史文件的密钥 ID 与当前密钥不符：按 E8 ② 改名保留，不当作损坏")
    func keyMismatchQuarantines() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try EncryptedHistoryStorage(vaultDirectory: environment.vault.url, keys: try VaultFixtures.keys(0x01))
            .save(ClipHistory(items: [Fixtures.text("other")]))
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey())

        let ready = try session(try launch(environment, provider: provider))
        #expect(ready.keys == environment.keys)
        #expect(ready.quarantinedFolder != nil)
        #expect(TempDirectory.fileNames(in: environment.vault.backupsDirectory).isEmpty)
    }

    @Test("临时密钥（DEBUG）：不改名、不迁移，按锁定处理")
    func ephemeralKeyIsNonDestructive() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try environment.storage.save(ClipHistory(items: [Fixtures.text("real")]))
        #expect(try launch(environment, provider: InMemoryHistoryKeyProvider(), destructive: false) == .locked)
        #expect(FileManager.default.fileExists(atPath: environment.storage.fileURL.path))

        let fresh = try VaultEnvironment()
        defer { fresh.remove() }
        _ = try PlaintextMigrationTests.writeLegacy(in: fresh)
        _ = try session(try launch(fresh, provider: InMemoryHistoryKeyProvider(), destructive: false))
        #expect(FileManager.default.fileExists(atPath: fresh.plain.historyURL.path))
    }

    @Test("有明文时启动即迁移；残留的 .migrated-plain/ 先删除")
    func migratesOnLaunch() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let legacy = try PlaintextMigrationTests.writeLegacy(in: environment)
        try FileManager.default.createDirectory(
            at: environment.plain.leftoverDirectory, withIntermediateDirectories: true)
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey())

        let ready = try session(try launch(environment, provider: provider))
        #expect(!ready.migrationFailed)
        try PlaintextMigrationTests.verifyMigrated(environment, legacy: legacy)
    }

    @Test("迁移失败：Vault 照常就绪，明文保留，报告失败")
    func migrationFailureIsReported() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        _ = try HistoryFixtures.write(HistoryFixtures.v99JSON, to: environment.plain.historyURL)
        let ready = try session(try launch(environment, provider: InMemoryHistoryKeyProvider()))
        #expect(ready.migrationFailed)
        #expect(FileManager.default.fileExists(atPath: environment.plain.historyURL.path))
    }

    @Test("改名保留：同一天再次发生时加 -2、-3")
    func quarantineNames() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let recovery = VaultRecovery(dataDirectory: environment.root)
        var names: [String] = []
        for _ in 0..<3 {
            try FileManager.default.createDirectory(at: environment.vault.url, withIntermediateDirectories: true)
            names.append(try recovery.quarantine(now: day).lastPathComponent)
        }
        #expect(
            names == ["Vault-unreadable-2026-10-13", "Vault-unreadable-2026-10-13-2", "Vault-unreadable-2026-10-13-3"])
        #expect(recovery.unreadableFolders().count == 3)
    }

    @Test("钥匙串恢复了旧密钥：保留目录合并回当前 Vault（含图片、备份与安全记录），校验后删除目录")
    func restoresMatchingFolder() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let image = environment.blobs.name(kind: .image, contentHash: "img")
        try environment.blobs.write(Data("png".utf8), name: image)
        let old = Fixtures.image(name: image, at: Fixtures.baseDate)
        try environment.storage.save(ClipHistory(items: [old]))
        try PrivateFiles.createDirectory(at: environment.vault.backupsDirectory)
        try Data("b".utf8).write(to: environment.vault.backupsDirectory.appendingPathComponent("history.v1.bak.cubby"))
        let entry = SecurityLogEntry(
            date: Fixtures.baseDate, event: .pasteVerified, kind: .bitcoin, summary: "s", appName: nil)
        try SecurityLogStore(dataDirectory: environment.root, vault: environment.vault, keys: environment.keys)
            .save(SecurityLog(entries: [entry]))
        let recovery = VaultRecovery(dataDirectory: environment.root)
        let folder = try recovery.quarantine(now: day)
        let newer = Fixtures.text("after reset", at: Fixtures.baseDate.addingTimeInterval(60))
        try environment.storage.save(ClipHistory(items: [newer]))

        #expect(recovery.restoreFolders(matching: environment.keys, historyLimit: 100) == [folder])
        #expect(try environment.storage.load().items.map(\.id) == [newer.id, old.id])
        #expect(try environment.blobs.data(image) == Data("png".utf8))
        #expect(TempDirectory.fileNames(in: environment.vault.backupsDirectory) == ["history.v1.bak.cubby"])
        let log = SecurityLogStore(dataDirectory: environment.root, vault: environment.vault, keys: environment.keys)
        #expect(log.load().log.entries.map(\.id) == [entry.id])
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("密钥 ID 不符或没有历史文件的保留目录：原样保留")
    func keepsForeignFolders() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try EncryptedHistoryStorage(vaultDirectory: environment.vault.url, keys: try VaultFixtures.keys(0x01))
            .save(ClipHistory(items: [Fixtures.text("other")]))
        let recovery = VaultRecovery(dataDirectory: environment.root)
        let foreign = try recovery.quarantine(now: day)
        try FileManager.default.createDirectory(at: environment.vault.url, withIntermediateDirectories: true)
        let empty = try recovery.quarantine(now: day)

        #expect(recovery.restoreFolders(matching: environment.keys, historyLimit: 100).isEmpty)
        #expect(FileManager.default.fileExists(atPath: foreign.path))
        #expect(FileManager.default.fileExists(atPath: empty.path))
        #expect(VaultRecovery.keyID(ofVaultAt: empty) == nil)
    }

    @Test("启动时自动还原：E8 ② 之后钥匙串又找回了旧密钥")
    func launchRestoresWhenKeyReturns() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try environment.storage.save(ClipHistory(items: [Fixtures.text("old")]))
        _ = try VaultRecovery(dataDirectory: environment.root).quarantine(now: day)
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey())

        let ready = try session(try launch(environment, provider: provider))
        #expect(ready.quarantinedFolder == nil)
        #expect(try environment.storage.load().items.map(\.text) == ["old"])
        #expect(VaultRecovery(dataDirectory: environment.root).unreadableFolders().isEmpty)
    }
}
