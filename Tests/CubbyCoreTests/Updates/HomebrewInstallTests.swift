import Foundation
import Testing
@testable import CubbyCore

@Suite("HomebrewInstall Homebrew 安装检测")
struct HomebrewInstallTests {
    @Test("默认检查 Apple 芯片与 Intel 两个 Caskroom 位置")
    func defaultPaths() {
        #expect(HomebrewInstall.caskroomPaths == ["/opt/homebrew/Caskroom/cubby", "/usr/local/Caskroom/cubby"])
        #expect(HomebrewInstall.upgradeCommand == "brew upgrade --cask cubby")
    }

    @Test("任一位置存在即视为用 Homebrew 安装")
    func detectsEitherPath() {
        #expect(HomebrewInstall.isInstalled { $0 == "/opt/homebrew/Caskroom/cubby" })
        #expect(HomebrewInstall.isInstalled { $0 == "/usr/local/Caskroom/cubby" })
        #expect(!HomebrewInstall.isInstalled { _ in false })
    }

    @Test("路径可注入：只检查给定的位置")
    func injectablePaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cubby-brew-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(HomebrewInstall.isInstalled(caskroomPaths: [directory.path]))
        #expect(!HomebrewInstall.isInstalled(caskroomPaths: [directory.appendingPathComponent("missing").path]))
        #expect(!HomebrewInstall.isInstalled(caskroomPaths: []))
    }
}
