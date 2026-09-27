import AppKit
import CubbyCore

/// 检查更新的统一入口：关于页、菜单栏与每周自动检查共用，保证行为一致
@MainActor
final class UpdateCoordinator {
    private let settings: AppSettings
    /// 发现新版本时通知（菜单栏显示提示项）
    var onUpdateAvailable: ((String, URL) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func check() async -> UpdateChecker.Result {
        let result = await UpdateChecker.check()
        settings.lastUpdateCheck = Date()
        if case .available(let version, let url) = result {
            onUpdateAvailable?(version, url)
        }
        return result
    }

    /// 启动时：开启了每周自动检查且已到期才联网，结果只在菜单栏静默提示
    func checkAutomaticallyIfDue() {
        guard settings.isAutomaticUpdateCheckDue() else { return }
        Task { _ = await check() }
    }

    /// 菜单栏「检查更新…」：以对话框告知结果
    func checkInteractively() {
        Task {
            let result = await check()
            present(result)
        }
    }

    private static var okTitle: String {
        String(localized: "OK", comment: "Button")
    }

    func present(_ result: UpdateChecker.Result) {
        NSApp.activate()
        let alert = NSAlert()
        switch result {
        case .upToDate(let current):
            alert.messageText = String(localized: "Cubby is up to date", comment: "Update alert title")
            alert.informativeText = String(
                localized: "You're running version \(current).",
                comment: "Update alert message"
            )
            alert.addButton(withTitle: Self.okTitle)
        case .available(let version, let url):
            alert.messageText = String(localized: "Version \(version) is available", comment: "Update alert title")
            alert.informativeText = String(
                localized: """
                    You're running version \(UpdateChecker.currentVersion). \
                    If you installed Cubby with Homebrew, run: brew upgrade --cask cubby
                    """,
                comment: "Update alert message"
            )
            alert.addButton(withTitle: String(localized: "Download", comment: "Button: open the release page"))
            alert.addButton(withTitle: String(localized: "Not Now", comment: "Button"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
            return
        case .failed(let reason):
            alert.messageText = String(localized: "Couldn't check for updates", comment: "Update alert title")
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: Self.okTitle)
        }
        alert.runModal()
    }
}
