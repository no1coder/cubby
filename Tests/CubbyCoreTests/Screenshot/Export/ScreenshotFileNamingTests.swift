import Foundation
import Testing
@testable import CubbyCore

@Suite("ScreenshotFileNaming 文件名与去重")
struct ScreenshotFileNamingTests {
    /// 2026-09-27 01:23:45 UTC
    private let date = Date(timeIntervalSince1970: 1_790_472_225)
    private let utc = TimeZone(identifier: "UTC")!

    @Test("固定日期 → 精确文件名")
    func exactName() {
        #expect(ScreenshotFileNaming.fileName(date: date, timeZone: utc) == "Cubby 2026-09-27 01.23.45.png")
    }

    @Test("时区注入：同一时刻在 UTC+8 为 09 点")
    func timeZoneInjection() {
        let beijing = TimeZone(secondsFromGMT: 8 * 3600)!
        #expect(ScreenshotFileNaming.fileName(date: date, timeZone: beijing) == "Cubby 2026-09-27 09.23.45.png")
    }

    @Test("24 小时制：下午不出现 PM，零点为 00")
    func twentyFourHour() {
        let afternoon = date.addingTimeInterval(12 * 3600)
        #expect(ScreenshotFileNaming.fileName(date: afternoon, timeZone: utc) == "Cubby 2026-09-27 13.23.45.png")
        let midnight = Date(timeIntervalSince1970: 1_790_380_800)
        #expect(ScreenshotFileNaming.fileName(date: midnight, timeZone: utc) == "Cubby 2026-09-26 00.00.00.png")
    }

    @Test("跨年边界与时区换日")
    func dayRollover() {
        // 2026-12-31 23:59:59 UTC → UTC+1 为次年 1 月 1 日
        let newYearEve = Date(timeIntervalSince1970: 1_798_761_599)
        let plusOne = TimeZone(secondsFromGMT: 3600)!
        #expect(ScreenshotFileNaming.fileName(date: newYearEve, timeZone: utc) == "Cubby 2026-12-31 23.59.59.png")
        #expect(ScreenshotFileNaming.fileName(date: newYearEve, timeZone: plusOne) == "Cubby 2027-01-01 00.59.59.png")
    }

    @Test("文件名只含 ASCII 数字与固定分隔符（不随地区的数字 / 历法变化）")
    func asciiOnly() {
        let name = ScreenshotFileNaming.fileName(date: date)
        #expect(name.unicodeScalars.allSatisfy { $0.isASCII })
        #expect(name.hasPrefix("Cubby 2026-09-2"))
        #expect(name.hasSuffix(".png"))
    }

    @Test("不存在冲突时原样返回")
    func noConflict() {
        let directory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let url = ScreenshotFileNaming.uniqueURL(in: directory, fileName: "Cubby a.png") { _ in false }
        #expect(url.path == "/tmp/shots/Cubby a.png")
    }

    @Test("冲突 1 次追加 \" 2\"")
    func oneConflict() {
        let directory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let url = ScreenshotFileNaming.uniqueURL(in: directory, fileName: "Cubby a.png") {
            $0.lastPathComponent == "Cubby a.png"
        }
        #expect(url.lastPathComponent == "Cubby a 2.png")
    }

    @Test("冲突 3 次追加 \" 4\"")
    func threeConflicts() {
        let directory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let taken: Set<String> = ["Cubby a.png", "Cubby a 2.png", "Cubby a 3.png"]
        let url = ScreenshotFileNaming.uniqueURL(in: directory, fileName: "Cubby a.png") {
            taken.contains($0.lastPathComponent)
        }
        #expect(url.lastPathComponent == "Cubby a 4.png")
        #expect(url.deletingLastPathComponent().path == "/tmp/shots")
    }

    @Test("无扩展名的文件名同样去重")
    func noExtension() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let url = ScreenshotFileNaming.uniqueURL(in: directory, fileName: "shot") { $0.lastPathComponent == "shot" }
        #expect(url.lastPathComponent == "shot 2")
    }

    @Test("真实目录：已存在的文件不会被覆盖")
    func realDirectory() throws {
        let directory = try TempDirectory.make()
        defer { TempDirectory.remove(directory) }
        let name = ScreenshotFileNaming.fileName(date: date, timeZone: utc)
        try Data([1]).write(to: directory.appendingPathComponent(name))
        let url = ScreenshotFileNaming.uniqueURL(in: directory, fileName: name) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        #expect(url.lastPathComponent == "Cubby 2026-09-27 01.23.45 2.png")
    }

    @Test("冲突过多时退化为带 UUID 的名字，保证终止")
    func exhaustedFallsBackToUUID() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let url = ScreenshotFileNaming.uniqueURL(in: directory, fileName: "x.png") {
            !$0.lastPathComponent.contains("-")
        }
        #expect(url.lastPathComponent.hasPrefix("x "))
        #expect(url.pathExtension == "png")
        #expect(url.lastPathComponent.contains("-"))
    }
}

@Suite("ScreenshotSaveLocation 保存目录解析")
@MainActor
struct ScreenshotSaveLocationTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test("preferred 优先")
    func preferredWins() {
        withIsolatedDefaults { defaults in
            defaults.set("~/Pictures", forKey: "location")
            let preferred = URL(fileURLWithPath: "/Volumes/Shots", isDirectory: true)
            let resolved = ScreenshotSaveLocation.resolve(
                preferred: preferred, systemDefaults: defaults, homeDirectory: home)
            #expect(resolved == preferred)
        }
    }

    @Test(
        "系统 defaults 的 location：~ 展开到注入的 home",
        arguments: [
            ("~/Pictures/Screenshots", "/Users/tester/Pictures/Screenshots"),
            ("~", "/Users/tester"),
            ("~/", "/Users/tester"),
            ("/Volumes/External/Shots", "/Volumes/External/Shots"),
            ("  /tmp/padded  ", "/tmp/padded"),
        ]
    )
    func systemLocation(value: String, expected: String) {
        withIsolatedDefaults { defaults in
            defaults.set(value, forKey: "location")
            let resolved = ScreenshotSaveLocation.resolve(
                preferred: nil, systemDefaults: defaults, homeDirectory: home, directoryExists: { _ in true })
            #expect(resolved.path == expected)
            #expect(resolved.hasDirectoryPath)
        }
    }

    @Test("系统 defaults 的 location 指向不存在的目录：回退桌面（任何进程都能改写该设置，不据此建目录）")
    func missingSystemLocationFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set("/Users/tester/Library/LaunchAgents/Evil", forKey: "location")
            let destination = ScreenshotSaveLocation.destination(
                preferred: nil, systemDefaults: defaults, homeDirectory: home, directoryExists: { _ in false })
            #expect(destination.directory.path == "/Users/tester/Desktop")
            #expect(!destination.createsIfMissing)
        }
    }

    @Test("来源决定是否允许创建：用户选择的目录允许，系统位置与桌面不允许")
    func destinationCreationPolicy() {
        withIsolatedDefaults { defaults in
            defaults.set("/Volumes/Shots", forKey: "location")
            let preferred = URL(fileURLWithPath: "/Users/tester/Chosen", isDirectory: true)
            let chosen = ScreenshotSaveLocation.destination(
                preferred: preferred, systemDefaults: defaults, homeDirectory: home, directoryExists: { _ in false })
            #expect(chosen == .init(directory: preferred, createsIfMissing: true))

            let system = ScreenshotSaveLocation.destination(
                preferred: nil, systemDefaults: defaults, homeDirectory: home, directoryExists: { _ in true })
            #expect(system.directory.path == "/Volumes/Shots")
            #expect(!system.createsIfMissing)
        }
        let desktop = ScreenshotSaveLocation.destination(preferred: nil, systemDefaults: nil, homeDirectory: home)
        #expect(desktop.directory.path == "/Users/tester/Desktop")
        #expect(!desktop.createsIfMissing)
    }

    @Test("默认的存在性检查：只有已存在的目录算数（普通文件不算）")
    func existingDirectoryCheck() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let file = dir.appendingPathComponent("file")
        try Data().write(to: file)
        #expect(ScreenshotSaveLocation.isExistingDirectory(dir))
        #expect(!ScreenshotSaveLocation.isExistingDirectory(file))
        #expect(!ScreenshotSaveLocation.isExistingDirectory(dir.appendingPathComponent("missing")))
    }

    @Test("location 为空、相对路径或非字符串时回退桌面", arguments: ["", "   ", "Pictures", "~other/x"])
    func invalidLocationFallsBack(value: String) {
        withIsolatedDefaults { defaults in
            defaults.set(value, forKey: "location")
            let resolved = ScreenshotSaveLocation.resolve(preferred: nil, systemDefaults: defaults, homeDirectory: home)
            #expect(resolved.path == "/Users/tester/Desktop")
        }
    }

    @Test("defaults 无 location 或为 nil 时回退 home/Desktop")
    func fallsBackToDesktop() {
        withIsolatedDefaults { defaults in
            defaults.set(42, forKey: "other")
            #expect(
                ScreenshotSaveLocation.resolve(preferred: nil, systemDefaults: defaults, homeDirectory: home).path
                    == "/Users/tester/Desktop"
            )
        }
        let resolved = ScreenshotSaveLocation.resolve(preferred: nil, systemDefaults: nil, homeDirectory: home)
        #expect(resolved.path == "/Users/tester/Desktop")
        #expect(resolved.hasDirectoryPath)
    }
}
