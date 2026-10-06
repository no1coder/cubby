#if DEBUG
import AppKit
import CubbyCore

/// 面板 E2E 的更新检查桩（docs/UPDATE-REMINDER-DESIGN.md）：不联网，返回脚本给定的结果；
/// 记录检查次数与「打开」的网址，不真的打开浏览器
@MainActor
final class PanelE2EUpdateStub {
    static let releaseURL = URL(string: "https://github.com/no1coder/cubby/releases/tag/v0.3.0")!

    /// 下一次检查返回的结果
    var result: UpdateChecker.Result = .upToDate(current: "0.2.1")
    private(set) var checkCount = 0
    private(set) var openedURLs: [URL] = []

    func check() async -> UpdateChecker.Result {
        checkCount += 1
        return result
    }

    func open(_ url: URL) {
        openedURLs.append(url)
    }

    /// 让下一次检查查到这个版本
    func offer(_ version: String) {
        result = .available(version: version, releaseURL: Self.releaseURL)
    }
}
#endif
