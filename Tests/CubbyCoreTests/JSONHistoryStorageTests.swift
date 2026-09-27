import Foundation
import Testing
@testable import CubbyCore

@Suite("JSONHistoryStorage 读写与损坏恢复")
struct JSONHistoryStorageTests {
    private func sampleHistory() -> ClipHistory {
        ClipHistory(items: [
            Fixtures.text("你好 📋", favorite: true, source: SourceApp(bundleID: "com.apple.Notes", name: "备忘录")),
            Fixtures.text("https://example.com"),
            Fixtures.text("富文本", formatsName: "abc.formats"),
            Fixtures.image(name: "abc.png", width: 3, height: 4),
            Fixtures.files(["/tmp/a b.txt", "/tmp/c.txt"]),
            ClipItem(
                kind: .text, payload: .text("no source"), source: SourceApp(bundleID: nil, name: nil),
                createdAt: Date(timeIntervalSince1970: 0.123456789), contentHash: "text:x"),
        ])
    }

    @Test("文件不存在时返回空历史")
    func missingFileReturnsEmpty() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        #expect(try storage.load() == .empty)
    }

    @Test("保存后读取得到相同历史")
    func roundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        let history = sampleHistory()
        try storage.save(history)
        #expect(try storage.load() == history)
    }

    @Test("保存时自动创建多级父目录")
    func saveCreatesIntermediateDirectories() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("a/b/c/history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        try storage.save(sampleHistory())
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("再次保存覆盖旧内容")
    func saveOverwrites() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        try storage.save(sampleHistory())
        let smaller = ClipHistory(items: [Fixtures.text("only")])
        try storage.save(smaller)
        #expect(try storage.load() == smaller)
    }

    @Test("空历史可往返")
    func emptyRoundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        try storage.save(.empty)
        #expect(try storage.load() == .empty)
    }

    @Test(
        "损坏文件抛出 corrupted，原文件被移走并保留备份",
        arguments: ["{not json", "", "{\"foo\": 1}", "{\"items\": [{\"id\": \"bad\"}]}"]
    )
    func corruptedFileIsBackedUp(_ content: String) throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let original = Data(content.utf8)
        try original.write(to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        let error = #expect(throws: HistoryStorageError.self) {
            try storage.load()
        }
        guard case .corrupted(let backupURL) = error else {
            Issue.record("应当抛出 corrupted 错误")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(backupURL.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        #expect(backupURL.lastPathComponent.hasPrefix("history.corrupt-"))
        #expect(backupURL.pathExtension == "json")
        #expect(try Data(contentsOf: backupURL) == original)

        // 移走后再次读取视为全新开始
        #expect(try storage.load() == .empty)
    }

    @Test("同一秒内连续两次损坏：仍抛 corrupted，两份备份互不覆盖")
    func repeatedCorruptionWithinSameSecond() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        let storage = JSONHistoryStorage(fileURL: fileURL)
        var backups: [URL] = []

        for content in ["bad-1", "bad-2"] {
            try Data(content.utf8).write(to: fileURL)
            let error = #expect(throws: HistoryStorageError.self) {
                try storage.load()
            }
            guard case .corrupted(let backupURL) = error else {
                Issue.record("第 \(backups.count + 1) 次损坏应抛出 corrupted")
                return
            }
            backups.append(backupURL)
        }

        #expect(Set(backups).count == 2)
        #expect(try backups.map { try String(contentsOf: $0, encoding: .utf8) } == ["bad-1", "bad-2"])
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("损坏恢复后可以正常写入新历史")
    func canSaveAfterCorruption() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let fileURL = dir.appendingPathComponent("history.json")
        try Data("garbage".utf8).write(to: fileURL)
        let storage = JSONHistoryStorage(fileURL: fileURL)
        _ = try? storage.load()

        let history = ClipHistory(items: [Fixtures.text("fresh")])
        try storage.save(history)
        #expect(try storage.load() == history)
    }

    @Test("读取不可读路径（目录）抛出普通错误而非 corrupted")
    func unreadablePathThrowsGenericError() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        // 以目录占据历史文件路径，模拟无法读取
        let fileURL = dir.appendingPathComponent("history.json", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let storage = JSONHistoryStorage(fileURL: fileURL)

        #expect {
            try storage.load()
        } throws: { error in
            !(error is HistoryStorageError)
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("富文本格式名随历史往返")
    func formatsNameRoundTrip() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let storage = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        try storage.save(ClipHistory(items: [Fixtures.text("x", formatsName: "f.formats"), Fixtures.text("y")]))
        #expect(try storage.load().items.map(\.formatsName) == ["f.formats", nil])
    }

    @Test("旧版本（无 formatsName 字段）的历史文件可正常读取")
    func legacyJSONWithoutFormatsName() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }

        let id = UUID()
        let legacy = """
            {"items":[{"id":"\(id.uuidString)","kind":"text","payload":{"text":{"_0":"旧条目"}},\
            "createdAt":0,"isFavorite":true,"contentHash":"text:old"}]}
            """
        let fileURL = dir.appendingPathComponent("history.json")
        try Data(legacy.utf8).write(to: fileURL)

        let item = try #require(try JSONHistoryStorage(fileURL: fileURL).load().items.first)
        #expect(item.id == id)
        #expect(item.text == "旧条目")
        #expect(item.isFavorite)
        #expect(item.source == nil)
        #expect(item.formatsName == nil)
    }
}
