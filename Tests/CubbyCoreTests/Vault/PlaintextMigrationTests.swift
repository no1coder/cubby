import Foundation
import Testing
@testable import CubbyCore

/// 模拟进程在检查点崩溃
struct SimulatedCrash: Error {}

/// 明文 → 加密 Vault 的迁移（E6）与降级后再升级的合并（E7）
@Suite("PlaintextMigration", .timeLimit(.minutes(1)))
struct PlaintextMigrationTests {
    /// 旧版本留下的一份典型明文数据：文本、收藏、富文本、带缩略图的大图、带译后图片的小图
    struct LegacyData {
        let history: ClipHistory
        /// 每个图片条目的原图内容（按条目 id）
        let images: [UUID: Data]
        let translatedPNG: Data
    }

    static func writeLegacy(in environment: VaultEnvironment) throws -> LegacyData {
        let blobs = environment.legacyBlobs
        let big = LargeImageFixtures.png(width: 2400, height: 1300)
        let bigName = ContentHasher.sha256(big) + ".png"
        try blobs.write(big, name: bigName)
        let thumbnail = try #require(ImageThumbnail.make(fromImageData: big, width: 2400, height: 1300))
        try blobs.write(thumbnail, name: ImageThumbnail.legacyName(forImage: bigName))
        let small = Data("small-png".utf8)
        let smallName = ContentHasher.sha256(small) + ".png"
        try blobs.write(small, name: smallName)
        let translated = Data("translated-png".utf8)
        let translatedName = ContentHasher.sha256(translated) + ".png"
        try blobs.write(translated, name: translatedName)
        let formats = try RichFormats.encode(Fixtures.richFormats(for: "rich"))
        let formatsName = ContentHasher.sha256(formats) + ".formats"
        try blobs.write(formats, name: formatsName)

        let bigItem = imageItem(big, name: bigName, width: 2400, height: 1300, at: date(1))
        let smallItem = imageItem(small, name: smallName, width: 8, height: 6, at: date(2))
            .translated(TranslationFixtures.image(blob: translatedName))
        let items = [
            Fixtures.text("note", at: date(5)),
            Fixtures.text("starred", favorite: true, at: date(4)),
            Fixtures.text("rich", at: date(3), formatsName: formatsName),
            smallItem, bigItem,
        ]
        let history = ClipHistory(items: items)
        try JSONHistoryStorage(fileURL: environment.plain.historyURL).save(history)
        return LegacyData(
            history: history, images: [bigItem.id: big, smallItem.id: small], translatedPNG: translated)
    }

    /// 内容哈希与真实记录相同的图片条目（迁移后再次复制同一张图能去重）
    static func imageItem(_ png: Data, name: String, width: Int, height: Int, at date: Date) -> ClipItem {
        ClipItem(
            kind: .image, payload: .image(ImageRef(name: name, width: width, height: height)), source: nil,
            createdAt: date, contentHash: ContentHasher.hash(imageDigest: ContentHasher.sha256(png)))
    }

    static func date(_ minutes: Double) -> Date {
        Fixtures.baseDate.addingTimeInterval(minutes * 60)
    }

    private func migration(_ environment: VaultEnvironment) -> PlaintextMigration {
        PlaintextMigration(dataDirectory: environment.root, vault: environment.vault, keys: environment.keys)
    }

    /// 迁移后的加密数据与原明文一一对应：条目数、顺序、id、每张图片与译后图片都能解密且内容相同
    static func verifyMigrated(_ environment: VaultEnvironment, legacy: LegacyData) throws {
        let migrated = try environment.storage.load()
        #expect(migrated.items.map(\.id) == legacy.history.items.map(\.id))
        let blobs = environment.blobs
        for item in migrated.items {
            if let image = item.image {
                #expect(InMemoryClipBlobStore.parse(image.name) == nil && !image.name.contains("."))
                #expect(try blobs.data(image.name) == legacy.images[item.id])
            }
            for name in item.translatedImageNames {
                #expect(try blobs.data(name) == legacy.translatedPNG)
            }
            if let formatsName = item.formatsName {
                #expect(try RichFormats.decode(blobs.data(formatsName)) == Fixtures.richFormats(for: "rich"))
            }
        }
        #expect(migrated.items.first { $0.text == "starred" }?.isFavorite == true)
        #expect(!environment.plain.containsPlaintext)
        #expect(!FileManager.default.fileExists(atPath: environment.plain.leftoverDirectory.path))
    }

    @Test("完整迁移：全部条目与文件加密进 Vault（含缩略图），明文全部删除，进度按条目报告")
    func migratesEverything() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let legacy = try Self.writeLegacy(in: environment)
        var reports: [(Int, Int)] = []

        let report = try migration(environment).run { reports.append(($0, $1)) }

        #expect(report == PlaintextMigration.Report(legacyItems: 5, resultItems: 5, droppedItems: 0))
        #expect(reports.first! == (0, 5) && reports.last! == (5, 5) && reports.count == 6)
        try Self.verifyMigrated(environment, legacy: legacy)
        // 原图、缩略图、小图、译后图、富文本格式
        #expect(environment.encryptedFileNames.count == 5)
        let big = try #require(try environment.storage.load().items.last?.image?.name)
        #expect(environment.blobs.exists(environment.blobs.thumbnailName(forImage: big)))
    }

    @Test("迁移后再记录同一张图：按内容去重，文件名相同")
    @MainActor
    func dedupesWithNewRecordings() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let legacy = try Self.writeLegacy(in: environment)
        try migration(environment).run()

        let store = ClipStore(storage: environment.storage, blobs: environment.blobs, limit: 100)
        let png = try #require(legacy.images.values.first { $0 == Data("small-png".utf8) })
        let item = try #require(store.record(.image(png: png, width: 8, height: 6), source: nil))
        #expect(store.history.items.count == 5)
        #expect(item.translations != nil)
    }

    @Test("原图缺失的条目丢弃；富文本格式缺失退化为纯文本；读不到明文不算错误")
    func dropsMissingFiles() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let history = ClipHistory(items: [
            Fixtures.image(name: "gone.png"),
            Fixtures.text("lost formats", formatsName: "gone.formats"),
            Fixtures.image(name: "../evil.png"),
        ])
        try JSONHistoryStorage(fileURL: environment.plain.historyURL).save(history)

        let report = try migration(environment).run()
        #expect(report.droppedItems == 2)
        let migrated = try environment.storage.load()
        #expect(migrated.items.map(\.text) == ["lost formats"])
        #expect(migrated.items.first?.formatsName == nil)
    }

    @Test("只有 Images/ 与备份（history.json 已迁走或从未存在）：直接移走，不写历史")
    func onlyLeftoverPlaintext() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try environment.legacyBlobs.write(Data("x".utf8), name: "x.png")
        try Data("{}".utf8).write(to: environment.root.appendingPathComponent("history.v1.bak.json"))
        #expect(environment.plain.containsPlaintext)

        try migration(environment).run()
        #expect(!environment.plain.containsPlaintext)
        #expect(!FileManager.default.fileExists(atPath: environment.storage.fileURL.path))
    }

    @Test("旧格式的明文历史：先在内存中升级再迁移，留下的明文备份一并删除")
    func migratesOldFormat() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        _ = try HistoryFixtures.write(HistoryFixtures.v0JSON, to: environment.plain.historyURL)

        try migration(environment).run()
        #expect(try !environment.storage.load().items.isEmpty)
        #expect(!environment.plain.containsPlaintext)
    }

    @Test("明文历史损坏：损坏备份加密进 Vault/Backups，明文删除；已有的明文损坏备份同样处理")
    func encryptsCorruptBackups() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try Data("{not json".utf8).write(to: environment.plain.historyURL)
        let older = environment.root.appendingPathComponent("history.corrupt-1-abcd.json")
        try Data("older corrupt".utf8).write(to: older)

        try migration(environment).run()

        #expect(!environment.plain.containsPlaintext)
        let backups = TempDirectory.fileNames(in: environment.vault.backupsDirectory)
        #expect(backups.count == 2)
        #expect(backups.contains("history.corrupt-1-abcd.cubby"))
        let encrypted = try Data(
            contentsOf: environment.vault.backupsDirectory.appendingPathComponent("history.corrupt-1-abcd.cubby"))
        let role = PlaintextMigration.backupRole("history.corrupt-1-abcd.cubby")
        #expect(
            try EncryptedFileFormat.decrypt(encrypted, keys: environment.keys, role: role) == Data("older corrupt".utf8)
        )
    }

    @Test("明文历史来自更新版本：不迁移，明文原样保留")
    func newerLegacyIsUntouched() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        _ = try HistoryFixtures.write(HistoryFixtures.v99JSON, to: environment.plain.historyURL)
        #expect(throws: PlaintextMigration.MigrationError.legacyHistoryFromNewerVersion(99)) {
            try migration(environment).run()
        }
        #expect(FileManager.default.fileExists(atPath: environment.plain.historyURL.path))
    }

    @Test("已有加密历史属于另一把密钥：中止，明文保留")
    func existingVaultWithOtherKey() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        _ = try Self.writeLegacy(in: environment)
        try EncryptedHistoryStorage(vaultDirectory: environment.vault.url, keys: try VaultFixtures.keys(0x01))
            .save(ClipHistory(items: [Fixtures.text("other")]))
        #expect(throws: PlaintextMigration.MigrationError.encryptedHistoryUnusable) {
            try migration(environment).run()
        }
        #expect(FileManager.default.fileExists(atPath: environment.plain.historyURL.path))
    }

    @Test("已有加密历史损坏：移入 Backups，按空历史继续迁移")
    func existingCorruptVault() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let legacy = try Self.writeLegacy(in: environment)
        try PrivateFiles.createDirectory(at: environment.vault.url)
        var file = try EncryptedFileFormat.encrypt(Data("{}".utf8), keys: environment.keys, role: "history")
        file[file.count - 1] ^= 0xFF
        try file.write(to: environment.storage.fileURL)

        try migration(environment).run()
        try Self.verifyMigrated(environment, legacy: legacy)
        #expect(TempDirectory.fileNames(in: environment.vault.backupsDirectory).count == 1)
    }

    @Test("降级后再升级（E7）：与已有加密历史合并——去重、较新时间、收藏并集、加密历史的译文为准、按时间排序，不裁剪")
    func mergesWithExistingVault() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let kept = TranslationFixtures.text("zh-Hans", segments: ["vault"])
        let existing = ClipHistory(items: [
            Fixtures.text("note", at: Self.date(0)).translated(kept),
            Fixtures.text("vault only", at: Self.date(10)),
            Fixtures.text("old", at: Self.date(-100)),
        ])
        try environment.storage.save(existing)
        let legacy = ClipHistory(items: [
            Fixtures.text("note", favorite: true, at: Self.date(20))
                .translated(TranslationFixtures.text("zh-Hans", segments: ["plain"])),
            Fixtures.text("plain only", at: Self.date(15)),
        ])
        try JSONHistoryStorage(fileURL: environment.plain.historyURL).save(legacy)

        // 合并不按上限裁剪（H1）：全部保留，按时间排序
        try migration(environment).run()

        let merged = try environment.storage.load()
        #expect(merged.items.map(\.text) == ["note", "plain only", "vault only", "old"])
        let note = try #require(merged.items.first)
        #expect(note.id == existing.items[0].id && note.isFavorite && note.createdAt == Self.date(20))
        #expect(note.translations == ClipTranslations([kept]))
        #expect(!environment.plain.containsPlaintext)
    }

    @Test("读回校验失败：明文一个都不动")
    func verificationFailureKeepsPlaintext() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        _ = try Self.writeLegacy(in: environment)
        var crashing = migration(environment)
        // 写入之后、校验之前把文件换成另一份合法的加密历史：读回不一致
        crashing.checkpoint = { checkpoint in
            guard checkpoint == .historyWritten else { return }
            try environment.storage.save(ClipHistory(items: [Fixtures.text("tampered")]))
        }
        #expect(throws: PlaintextMigration.MigrationError.verificationFailed) { try crashing.run() }
        #expect(FileManager.default.fileExists(atPath: environment.plain.historyURL.path))
        #expect(FileManager.default.fileExists(atPath: environment.plain.imagesDirectory.path))
    }

    @Test("在任一步之后崩溃：下次启动续做完成且不丢数据；校验通过之前明文完好", arguments: PlaintextMigration.Checkpoint.allCases)
    func resumesAfterCrash(_ point: PlaintextMigration.Checkpoint) throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let legacy = try Self.writeLegacy(in: environment)
        var crashing = migration(environment)
        crashing.checkpoint = { if $0 == point { throw SimulatedCrash() } }

        #expect(throws: SimulatedCrash.self) { try crashing.run() }
        let beforeVerified: [PlaintextMigration.Checkpoint] = [.blobsEncrypted, .historyWritten]
        if beforeVerified.contains(point) {
            #expect(try JSONHistoryStorage(fileURL: environment.plain.historyURL).load() == legacy.history)
            #expect(TempDirectory.fileNames(in: environment.plain.imagesDirectory).count == 5)
        }

        let resumed = try migration(environment).run()
        #expect(resumed.droppedItems == 0)
        try Self.verifyMigrated(environment, legacy: legacy)
    }

    @Test("H2：校验通过之后崩溃、下次续做：与已写入的加密历史合并时不按上限裁剪，全部条目保留")
    func resumeAfterVerifyKeepsEverything() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let legacy = try Self.writeLegacy(in: environment)
        var crashing = migration(environment)
        crashing.checkpoint = { if $0 == .historyVerified { throw SimulatedCrash() } }
        #expect(throws: SimulatedCrash.self) { try crashing.run() }

        try migration(environment).run()
        try Self.verifyMigrated(environment, legacy: legacy)
    }

    @Test("H3：已有的加密历史损坏：迁移照常完成，并在报告中给出损坏备份的位置")
    func reportsCorruptedExistingHistory() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        _ = try Self.writeLegacy(in: environment)
        try PrivateFiles.createDirectory(at: environment.vault.url)
        var file = try EncryptedFileFormat.encrypt(Data("{}".utf8), keys: environment.keys, role: "history")
        file[file.count - 1] ^= 0xFF
        try file.write(to: environment.storage.fileURL)

        let report = try migration(environment).run()
        let backup = try #require(report.corruptedHistoryBackup)
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test("残留的 .migrated-plain/ 在下次运行开始时删除")
    func removesLeftovers() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let leftover = environment.plain.leftoverDirectory.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover.appendingPathComponent("a.png"))

        try environment.plain.removeLeftovers()
        #expect(!FileManager.default.fileExists(atPath: environment.plain.leftoverDirectory.path))
        try environment.plain.removeLeftovers()
    }

    @Test("没有明文：isNeeded 为 false")
    func nothingToMigrate() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        #expect(!migration(environment).isNeeded)
        #expect(PlaintextMigration.legacyContentHash("abc.png") == "abc")
        #expect(PlaintextMigration.legacyContentHash("noext") == "noext")
    }
}
