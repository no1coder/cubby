import AppKit
import CubbyCore

/// 菜单栏「检查更新…」：以对话框告知结果（结果同样记进设置，蓝点与横幅随之更新）
extension UpdateCoordinator {
    func checkInteractively() {
        Task {
            let result = await check()
            present(result)
        }
    }

    private static var okTitle: String {
        String(localized: "OK", comment: "Button")
    }

    private static func runningVersion(_ version: String) -> String {
        String(localized: "You're running version \(version).", comment: "Update alert message")
    }

    func present(_ result: UpdateChecker.Result) {
        NSApp.activate()
        let alert = NSAlert()
        switch result {
        case .upToDate(let current):
            alert.messageText = String(localized: "Cubby is up to date", comment: "Update alert title")
            alert.informativeText = Self.runningVersion(current)
            alert.addButton(withTitle: Self.okTitle)
        case .available(let version, let url):
            guard let release = KnownRelease(version: version, releaseURL: url) else {
                // 检查器只返回能解析的版本号，走不到这里；万一走到也只记日志，不弹空对话框
                logger.error("Unparseable update version \(version, privacy: .public)")
                return
            }
            presentAvailable(alert, release: release)
            return
        case .failed(let reason):
            alert.messageText = String(localized: "Couldn't check for updates", comment: "Update alert title")
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: Self.okTitle)
        }
        alert.runModal()
    }

    /// 与面板横幅同一套按钮：Homebrew 安装复制升级命令，其余打开发布页；「稍后」同样只隐藏这个版本的横幅（U6）
    private func presentAvailable(_ alert: NSAlert, release: KnownRelease) {
        alert.messageText = UpdateCopy.versionAvailable(release.version.description)
        let running = Self.runningVersion(currentVersion)
        alert.informativeText = isHomebrewInstall ? running + "\n\n" + UpdateCopy.homebrewHint : running
        alert.addButton(withTitle: isHomebrewInstall ? UpdateCopy.copyUpgradeCommand : UpdateCopy.viewAndDownload)
        alert.addButton(withTitle: String(localized: "Not Now", comment: "Button"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if isHomebrewInstall { _ = copyUpgradeCommand() } else { openRelease(release) }
        default:
            dismissBanner(for: release)
        }
    }
}
