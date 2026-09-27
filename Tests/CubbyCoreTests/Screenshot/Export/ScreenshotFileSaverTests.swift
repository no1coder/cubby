import Darwin
import Foundation
import Testing
@testable import CubbyCore

@Suite("ScreenshotFileSaver 截图写文件")
struct ScreenshotFileSaverTests {
    private let png = Data("png-bytes".utf8)
    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    private func hasScreenCaptureMark(_ url: URL) -> Bool {
        getxattr(url.path, Self.screenCaptureAttribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    private func temporaryNames(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix(ScreenshotFileSaver.temporaryPrefix) }
    }

    /// 按固定文件名去重（与 ScreenshotOutputService 的用法一致）
    private func uniqueFile(_ name: String) -> (URL) -> URL {
        { directory in
            ScreenshotFileNaming.uniqueURL(in: directory, fileName: name) {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
    }

    // MARK: - write

    @Test("写入数据并标记为屏幕截图，不留临时文件")
    func writesAndMarks() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let url = dir.appendingPathComponent("a.png")

        #expect(try ScreenshotFileSaver.write(png, to: url) == url)
        #expect(try Data(contentsOf: url) == png)
        #expect(hasScreenCaptureMark(url))
        #expect(temporaryNames(in: dir).isEmpty)
    }

    @Test("目录不存在：默认不创建，抛 directoryUnavailable")
    func missingDirectoryNotCreated() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let missing = dir.appendingPathComponent("missing", isDirectory: true)

        #expect(throws: ScreenshotFileSaver.SaveError.self) {
            try ScreenshotFileSaver.write(png, to: missing.appendingPathComponent("a.png"))
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("允许创建时：连同中间目录一起创建")
    func createsDirectoryWhenAllowed() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let url = dir.appendingPathComponent("x/y/a.png")

        try ScreenshotFileSaver.write(png, to: url, createsDirectory: true)
        #expect(try Data(contentsOf: url) == png)
    }

    @Test("目标已存在：原子地拒绝覆盖（RENAME_EXCL），原内容不变、无临时文件残留")
    func refusesToOverwrite() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let url = dir.appendingPathComponent("a.png")
        try Data("old".utf8).write(to: url)

        #expect(throws: ScreenshotFileSaver.SaveError.fileExists(url)) {
            try ScreenshotFileSaver.write(png, to: url)
        }
        #expect(try Data(contentsOf: url) == Data("old".utf8))
        #expect(temporaryNames(in: dir).isEmpty)
    }

    @Test("允许覆盖时替换原文件")
    func overwritesWhenAllowed() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let url = dir.appendingPathComponent("a.png")
        try Data("old".utf8).write(to: url)

        try ScreenshotFileSaver.write(png, to: url, overwrite: true)
        #expect(try Data(contentsOf: url) == png)
    }

    @Test("目标是符号链接：不覆盖、也不写入链接指向的文件")
    func symlinkDestinationIsNotFollowed() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let target = dir.appendingPathComponent("target.txt")
        try Data("secret".utf8).write(to: target)
        let link = dir.appendingPathComponent("a.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: ScreenshotFileSaver.SaveError.fileExists(link)) {
            try ScreenshotFileSaver.write(png, to: link)
        }
        try ScreenshotFileSaver.write(png, to: link, overwrite: true)

        #expect(try Data(contentsOf: target) == Data("secret".utf8))
        let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
        #expect(!hasScreenCaptureMark(target))
    }

    @Test("截图标记不跟随符号链接")
    func markDoesNotFollowSymlinks() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let target = dir.appendingPathComponent("target.png")
        try png.write(to: target)
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        _ = ScreenshotFileSaver.markAsScreenCapture(link)
        #expect(!hasScreenCaptureMark(target))
    }

    @Test("写入被拒绝（目录只读）：抛 permissionDenied")
    func permissionDenied() throws {
        let dir = try TempDirectory.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            TempDirectory.remove(dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let url = dir.appendingPathComponent("a.png")

        #expect(throws: ScreenshotFileSaver.SaveError.permissionDenied(url)) {
            try ScreenshotFileSaver.write(png, to: url)
        }
    }

    @Test("父路径是普通文件：即使允许创建也报 directoryUnavailable")
    func cannotCreateUnderFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let file = dir.appendingPathComponent("file")
        try Data().write(to: file)
        let url = file.appendingPathComponent("sub/a.png")

        #expect(throws: ScreenshotFileSaver.SaveError.self) {
            try ScreenshotFileSaver.write(png, to: url, createsDirectory: true)
        }
    }

    @Test("目标位置是目录：不覆盖时报 fileExists，覆盖时报 writeFailed（附 errno）")
    func destinationIsDirectory() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let target = dir.appendingPathComponent("taken.png", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data().write(to: target.appendingPathComponent("inner"))
        let url = dir.appendingPathComponent("taken.png")

        #expect(throws: ScreenshotFileSaver.SaveError.fileExists(url)) {
            try ScreenshotFileSaver.write(png, to: url)
        }
        do {
            try ScreenshotFileSaver.write(png, to: url, overwrite: true)
            Issue.record("应当失败")
        } catch {
            guard case .writeFailed(_, let code) = error else {
                Issue.record("期望 writeFailed，实际 \(error)")
                return
            }
            #expect(code != 0)
        }
        #expect(temporaryNames(in: dir).isEmpty)
    }

    @Test("文件不存在时标记失败，返回 false")
    func markMissingFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        #expect(!ScreenshotFileSaver.markAsScreenCapture(dir.appendingPathComponent("missing.png")))
    }

    @Test("清理同一前缀、超过时限的临时文件；新的与无关文件保留")
    func removesStaleTemporaryFiles() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let prefix = ScreenshotFileSaver.temporaryPrefix
        let stale = dir.appendingPathComponent("\(prefix)OLD.tmp")
        let fresh = dir.appendingPathComponent("\(prefix)NEW.tmp")
        let unrelated = dir.appendingPathComponent(".other.tmp")
        for url in [stale, fresh, unrelated] {
            try Data("x".utf8).write(to: url)
        }
        let old = fixedDate.addingTimeInterval(-ScreenshotFileSaver.staleTemporaryAge - 60)
        for url in [stale, unrelated] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: fresh.path)

        try ScreenshotFileSaver.write(png, to: dir.appendingPathComponent("a.png"), now: fixedDate)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("错误的日志描述不含路径")
    func logDescriptionHasNoPath() {
        let url = URL(fileURLWithPath: "/Users/secret/Pictures/a.png")
        let errors: [ScreenshotFileSaver.SaveError] = [
            .directoryUnavailable(url), .permissionDenied(url), .fileExists(url), .writeFailed(url, errno: 28),
        ]
        #expect(errors.allSatisfy { !$0.logDescription.contains("secret") })
        #expect(ScreenshotFileSaver.SaveError.writeFailed(url, errno: 28).logDescription.contains("28"))
    }

    // MARK: - save

    @Test("重名时追加序号，不覆盖已有截图")
    func uniqueNames() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let destination = ScreenshotSaveLocation.Destination(directory: dir, createsIfMissing: false)

        let first = try ScreenshotFileSaver.save(png, to: destination, fallback: nil, fileURL: uniqueFile("Shot.png"))
        let second = try ScreenshotFileSaver.save(png, to: destination, fallback: nil, fileURL: uniqueFile("Shot.png"))
        #expect(first.url.lastPathComponent == "Shot.png")
        #expect(second.url.lastPathComponent == "Shot 2.png")
        #expect(!first.usedFallback && !second.usedFallback)
    }

    @Test("首选目录是普通文件：回退到备用目录")
    func fallsBackWhenDirectoryIsFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blocked = dir.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let fallback = dir.appendingPathComponent("fallback", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)

        let outcome = try ScreenshotFileSaver.save(
            png, to: .init(directory: blocked, createsIfMissing: true), fallback: fallback,
            fileURL: uniqueFile("Shot.png"))
        #expect(outcome.usedFallback)
        #expect(outcome.url.deletingLastPathComponent().standardizedFileURL == fallback.standardizedFileURL)
    }

    @Test("首选目录拒绝写入（EACCES / EPERM）：同样回退")
    func fallsBackWhenPermissionDenied() throws {
        let dir = try TempDirectory.make()
        let readOnly = dir.appendingPathComponent("readonly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
            TempDirectory.remove(dir)
        }

        let outcome = try ScreenshotFileSaver.save(
            png, to: .init(directory: readOnly, createsIfMissing: false), fallback: dir, fileURL: uniqueFile("S.png"))
        #expect(outcome.usedFallback)
        #expect(try Data(contentsOf: outcome.url) == png)

        #expect(throws: ScreenshotFileSaver.SaveError.self) {
            try ScreenshotFileSaver.save(
                png, to: .init(directory: readOnly, createsIfMissing: false), fallback: nil,
                fileURL: uniqueFile("S.png"))
        }
    }

    @Test("系统截图位置不存在时不创建（回退）；用户亲自选择的目录允许创建")
    func createsOnlyUserChosenDirectories() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let fallback = dir.appendingPathComponent("desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        let systemMissing = dir.appendingPathComponent("system", isDirectory: true)
        let chosenMissing = dir.appendingPathComponent("chosen", isDirectory: true)

        let system = try ScreenshotFileSaver.save(
            png, to: .init(directory: systemMissing, createsIfMissing: false), fallback: fallback,
            fileURL: uniqueFile("S.png"))
        #expect(system.usedFallback)
        #expect(!FileManager.default.fileExists(atPath: systemMissing.path))

        let chosen = try ScreenshotFileSaver.save(
            png, to: .init(directory: chosenMissing, createsIfMissing: true), fallback: fallback,
            fileURL: uniqueFile("S.png"))
        #expect(!chosen.usedFallback)
        #expect(FileManager.default.fileExists(atPath: chosen.url.path))
    }

    @Test("备用目录与首选相同或没有备用：直接抛错")
    func noUsableFallback() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let missing = dir.appendingPathComponent("missing", isDirectory: true)

        #expect(throws: ScreenshotFileSaver.SaveError.self) {
            try ScreenshotFileSaver.save(
                png, to: .init(directory: missing, createsIfMissing: false), fallback: missing,
                fileURL: uniqueFile("S.png"))
        }
    }
}
