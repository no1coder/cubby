import AppKit
import os

/// 重新打开 Cubby：先启动一个新实例，成功后再退出当前实例（失败时当前实例保留并提示）。
/// 用于只在启动时生效的改动：授予屏幕录制权限、切换界面语言
@MainActor
enum AppRelauncher {
    /// 重新打开后显示设置窗口（AppDelegate.handleLaunchArguments 处理）
    static let showSettingsArgument = "--show-settings"

    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Relaunch")

    /// 沿用本次启动的上下文，新实例与当前实例行为一致（开发时不会误用真实数据目录）
    private static let dataDirectoryVariable = "CUBBY_DATA_DIR"

    /// 沿用本次的启动参数，extraArguments 追加在后。「显示设置」只作用于紧接着的这一次，不沿用
    static func relaunch(extraArguments: [String] = []) {
        let configuration = NSWorkspace.OpenConfiguration()
        // 默认会激活正在运行的自身而不是启动新实例
        configuration.createsNewApplicationInstance = true
        configuration.arguments =
            CommandLine.arguments.dropFirst().filter { $0 != showSettingsArgument } + extraArguments
        if let dataDirectory = ProcessInfo.processInfo.environment[dataDirectoryVariable] {
            configuration.environment = [dataDirectoryVariable: dataDirectory]
        }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            let description = error.map { String(describing: $0) }
            Task { @MainActor in
                guard let description else {
                    NSApp.terminate(nil)
                    return
                }
                logger.error("Couldn't relaunch: \(description, privacy: .public)")
                showFailure()
            }
        }
    }

    private static func showFailure() {
        guard let anchor = HUDToast.defaultAnchor() else { return }
        HUDToast.show(
            String(
                localized: "Couldn't reopen Cubby. Quit it and open it again.",
                comment: "HUD when relaunching Cubby (after granting Screen Recording or changing the language) fails"
            ),
            symbolName: "exclamationmark.triangle.fill",
            tint: .orange,
            at: anchor
        )
    }
}
