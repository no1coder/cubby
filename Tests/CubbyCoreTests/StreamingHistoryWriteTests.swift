import Foundation
import Testing
@testable import CubbyCore

/// 流式写入 history.json：与整块编码逐字节等价、往返相等、失败时清理临时文件、全程 0600、映射读取的安全前提
@Suite("history.json 流式写入与映射读取")
struct StreamingHistoryWriteTests {
    private func sampleHistory() -> ClipHistory {
        ClipHistory(items: [
            Fixtures.text("你好 📋 \"引号\" \\ 反斜杠\n换行", favorite: true, source: SourceApp(bundleID: "a.b", name: "备忘录")),
            Fixtures.text("https://example.com/a?b=1&c=%E4%BD%A0"),
            Fixtures.text("富文本", formatsName: "abc.formats"),
            Fixtures.image(name: "abc.png", width: 3, height: 4),
            Fixtures.files(["/tmp/a b.txt", "/tmp/中文.txt"]),
            ClipItem(
                kind: .text, payload: .text("no source"), source: SourceApp(bundleID: nil, name: nil),
                createdAt: Date(timeIntervalSince1970: 0.123456789), contentHash: "text:x"),
        ])
    }

    /// 接近上限的重度历史：2000 条，含 4 条 1–2MB 的长日志与若干 100KB 级长文本
    private func largeHistory() -> ClipHistory {
        let line = "2026-09-27 05:00:00.123 [INFO] request id=42 path=/api/v1/items status=200 耗时 12ms\n"
        let items = (0..<2000).map { index -> ClipItem in
            let date = Fixtures.baseDate.addingTimeInterval(Double(-index))
            switch index % 10 {
            case 0 where index < 40:
                return Fixtures.text(String(repeating: line, count: 12_000 + index * 300), at: date)
            case 1 where index < 200:
                return Fixtures.text("#\(index) " + String(repeating: "段落内容 paragraph ", count: 5_000), at: date)
            case 2:
                return Fixtures.image(name: "img-\(index).png", width: 5120, height: 2880, at: date)
            case 3:
                return Fixtures.files(["/Users/me/Documents/file-\(index).txt"])
            default:
                return Fixtures.text("条目 \(index) item", favorite: index % 7 == 0, at: date)
            }
        }
        return ClipHistory(items: items)
    }

    private func streamed(_ history: ClipHistory, chunkSize: Int = HistoryMigrator.streamingChunkSize) throws -> Data {
        var output = Data()
        try HistoryMigrator.encode(history, chunkSize: chunkSize) { output.append($0) }
        return output
    }

    /// 目录下的全部文件名，包含隐藏的临时文件
    private func allNames(in dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
    }

    // MARK: - 等价性

    @Test("流式编码与整块编码逐字节相同（任意分块大小）", arguments: [1, 64, 4096, HistoryMigrator.streamingChunkSize])
    func streamingMatchesWholeEncoding(chunkSize: Int) throws {
        let history = sampleHistory()
        #expect(try streamed(history, chunkSize: chunkSize) == HistoryMigrator.encode(history))
        #expect(try streamed(.empty, chunkSize: chunkSize) == HistoryMigrator.encode(.empty))
    }

    @Test("按块交给写出方：除最后一块外每块都不小于分块大小")
    func sinkReceivesBoundedChunks() throws {
        let history = sampleHistory()
        var chunks: [Data] = []
        try HistoryMigrator.encode(history, chunkSize: 200) { chunks.append($0) }
        #expect(chunks.count > 1)
        #expect(chunks.dropLast().allSatisfy { $0.count >= 200 })
        #expect(chunks.reduce(Data(), +) == (try HistoryMigrator.encode(history)))
    }

    @Test("与旧编码器（JSONEncoder 默认键序）的输出 JSON 等价，只是键序固定")
    func equivalentToLegacyEncoder() throws {
        let history = sampleHistory()
        let legacyFile = LegacyFile(schemaVersion: HistoryMigrator.currentVersion, items: history.items)
        let legacy = try JSONEncoder().encode(legacyFile)
        let current = try streamed(history)

        let legacyObject = try #require(try JSONSerialization.jsonObject(with: legacy) as? NSDictionary)
        let currentObject = try #require(try JSONSerialization.jsonObject(with: current) as? NSDictionary)
        #expect(legacyObject == currentObject)
        // 键序确定：同一份历史再编码一次字节完全相同
        #expect(try streamed(history) == current)
        #expect(current.starts(with: Data("{\"items\":[".utf8)))
    }

    @Test("保存后文件字节与整块编码相同，读回与原历史相等")
    func savedBytesMatchAndRoundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = sampleHistory()
        try storage.save(history)

        #expect(try Data(contentsOf: fileURL) == HistoryMigrator.encode(history))
        #expect(try storage.load() == history)
        #expect(try HistoryFixtures.schemaVersion(ofFileAt: fileURL) == HistoryMigrator.currentVersion)
    }

    @Test("大数据量（2000 条、含 MB 级长文本）往返相等且与整块编码逐字节相同")
    func largeHistoryRoundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = largeHistory()
        try storage.save(history)

        let written = try Data(contentsOf: fileURL)
        // 确实跨越了大量分块
        #expect(written.count > 20 * HistoryMigrator.streamingChunkSize)
        #expect(written == (try HistoryMigrator.encode(history)))
        #expect(try storage.load() == history)
        #expect(try allNames(in: dir) == ["history.json"])
    }

    // MARK: - 权限

    @Test("写入过程中的临时文件就是 0600，完成后不留临时文件")
    func temporaryFileIsPrivateWhileWriting() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        var observed: [Int] = []
        try StreamingFileWriter.write(to: fileURL) { write in
            try write(Data("{\"items\":[".utf8))
            let temporary = try #require(try allNames(in: dir).first { $0.hasPrefix(".history.json.") })
            observed.append(try TempDirectory.permissions(of: dir.appendingPathComponent(temporary)))
            try write(Data("],\"schemaVersion\":1}".utf8))
        }

        #expect(observed == [0o600])
        #expect(try TempDirectory.permissions(of: fileURL) == 0o600)
        #expect(try allNames(in: dir) == ["history.json"])
        #expect(try JSONHistoryStorage(fileURL: fileURL).load() == .empty)
    }

    @Test("覆盖旧版本遗留的 0644 文件：替换为新的 0600 文件")
    func replacesLooseFileWithPrivateOne() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        try Data("{\"items\":[]}".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let history = sampleHistory()
        try JSONHistoryStorage(fileURL: fileURL).save(history)

        #expect(try TempDirectory.permissions(of: fileURL) == 0o600)
        #expect(try JSONHistoryStorage(fileURL: fileURL).load() == history)
    }

    // MARK: - 失败时清理

    @Test("写出中途失败：删除临时文件，原文件字节不变")
    func failureMidwayRemovesTemporaryFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let original = Data("original".utf8)
        try original.write(to: fileURL)

        #expect(throws: CocoaError.self) {
            try StreamingFileWriter.write(to: fileURL) { write in
                try write(Data(repeating: 0x41, count: 1024))
                throw CocoaError(.fileWriteUnknown)
            }
        }
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(try allNames(in: dir) == ["history.json"])
    }

    @Test("条目编码失败（非法浮点日期）：保存抛错，原历史文件不变，无残留临时文件")
    func encodingFailureKeepsOriginalFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = sampleHistory()
        try storage.save(history)
        let before = try Data(contentsOf: fileURL)

        // JSON 不能表示 NaN：编码到第二条时失败，此前已经写出了一部分
        let invalid = ClipItem(
            kind: .text, payload: .text("bad"), source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: .nan), contentHash: "text:nan")
        let broken = ClipHistory(items: [Fixtures.text("first"), invalid] + history.items)
        #expect(throws: EncodingError.self) {
            try storage.save(broken)
        }

        #expect(try Data(contentsOf: fileURL) == before)
        #expect(try storage.load() == history)
        #expect(try allNames(in: dir) == ["history.json"])
    }

    @Test("替换失败（目标路径是目录）：抛错并删除临时文件，目录保持原样")
    func renameFailureRemovesTemporaryFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: fileURL.appendingPathComponent("inner"))

        #expect(throws: POSIXError.self) {
            try StreamingFileWriter.write(to: fileURL) { write in try write(Data("x".utf8)) }
        }
        #expect(try allNames(in: dir) == ["history.json"])
        #expect(try Data(contentsOf: fileURL.appendingPathComponent("inner")) == Data("keep".utf8))
    }

    @Test("目录不可写：无法创建临时文件时抛错，不产生任何文件")
    func unwritableDirectoryThrows() throws {
        let dir = try TempDirectory.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            TempDirectory.remove(dir)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        var produced = false
        #expect(throws: POSIXError.self) {
            try StreamingFileWriter.write(to: dir.appendingPathComponent("history.json")) { _ in produced = true }
        }
        #expect(!produced)
        #expect(try allNames(in: dir).isEmpty)
    }

    @Test("临时文件名：同目录、隐藏、每次不同")
    func temporaryURLIsHiddenSibling() {
        let target = URL(fileURLWithPath: "/tmp/cubby/history.json")
        let first = StreamingFileWriter.temporaryURL(for: target)
        let second = StreamingFileWriter.temporaryURL(for: target)

        #expect(first.deletingLastPathComponent() == target.deletingLastPathComponent())
        #expect(first.lastPathComponent.hasPrefix(".history.json."))
        #expect(first.pathExtension == "tmp")
        #expect(first != second)
    }

    // MARK: - 遗留临时文件

    @Test("读取时清理写入中途被杀遗留的临时文件；进行中的、不匹配的文件保持不动")
    func loadRemovesStaleTemporaryFiles() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let history = sampleHistory()
        try storage.save(history)

        let stale = StreamingFileWriter.temporaryURL(for: fileURL)
        let fresh = StreamingFileWriter.temporaryURL(for: fileURL)
        let unrelated = [".history.json.not-a-uuid.tmp", ".other.json.\(UUID().uuidString).tmp", "notes.tmp"]
        for url in [stale, fresh] + unrelated.map({ dir.appendingPathComponent($0) }) {
            try Data("partial".utf8).write(to: url)
        }
        let old = Date().addingTimeInterval(-3_600)
        for url in [stale] + unrelated.map({ dir.appendingPathComponent($0) }) {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }

        #expect(try storage.load() == history)
        let names = try allNames(in: dir)
        #expect(!names.contains(stale.lastPathComponent))
        #expect(names.contains(fresh.lastPathComponent))
        #expect(names.isSuperset(of: unrelated))
    }

    @Test("历史文件还不存在时同样清理遗留临时文件；目录不存在时不报错")
    func staleCleanupWithoutHistoryFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let stale = StreamingFileWriter.temporaryURL(for: fileURL)
        try Data("partial".utf8).write(to: stale)
        StreamingFileWriter.removeStaleTemporaryFiles(for: fileURL, now: Date().addingTimeInterval(3_600))
        #expect(try allNames(in: dir).isEmpty)

        let missing = dir.appendingPathComponent("missing/history.json")
        #expect(try JSONHistoryStorage(fileURL: missing).load() == .empty)
    }

    // MARK: - 映射读取

    @Test("映射读取的安全前提：文件被原子替换后，已映射的旧内容仍完整可读")
    func mappedDataSurvivesAtomicReplace() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        let old = sampleHistory()
        try storage.save(old)

        // 与 JSONHistoryStorage.load 相同的读取方式（本地卷上即为内存映射）
        let mapped = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let replacement = ClipHistory(items: [Fixtures.text("new")])
        try storage.save(replacement)

        #expect(try HistoryMigrator.migrate(mapped).history == old)
        #expect(try storage.load() == replacement)
    }

    @Test("映射读取空文件与极小文件：仍按损坏处理并移走备份")
    func mappedReadOfTinyFiles() throws {
        for content in ["", "{"] {
            let dir = try TempDirectory.make()
            defer { TempDirectory.remove(dir) }

            let fileURL = dir.appendingPathComponent("history.json")
            try Data(content.utf8).write(to: fileURL)
            #expect(throws: HistoryStorageError.self) {
                try JSONHistoryStorage(fileURL: fileURL).load()
            }
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }
    }
}

/// 改动前的写法：JSONEncoder 默认配置（键序不确定）
private struct LegacyFile: Encodable {
    let schemaVersion: Int
    let items: [ClipItem]
}
