import AppKit
import CubbyCore

/// 首次启动引导（四步向导）的打开与完成
extension AppDelegate {
    func showOnboarding() {
        presentOnboarding(settings: settings, initialStep: .welcome)
    }

    /// 完成后与以前一样：标记已完成引导（窗口控制器负责），再用 HUD 提示呼出方式
    private func presentOnboarding(settings: AppSettings, initialStep: OnboardingStep) {
        let controller =
            onboardingWindow
            ?? OnboardingWindowController(
                settings: settings,
                initialStep: initialStep,
                onShortcutRecordingChange: { [weak self] in self?.setShortcutRecording($0) },
                onFinish: { [weak self] in
                    self?.onboardingWindow = nil
                    self?.showHotKeyTip()
                }
            )
        onboardingWindow = controller
        controller.show()
    }

    #if DEBUG
    /// 截图走查：引导窗口直接打开在指定步骤。用一份临时偏好设置（首次启动的默认值），
    /// 走查时的选择、勾选与「已完成引导」标记都不会写进真实设置；外观变化照常作用于整个应用
    func showOnboardingScenario(_ step: OnboardingStep) {
        guard let scenarioSettings = OnboardingScenario.makeSettings() else {
            logger.error("Could not create temporary settings for the onboarding scenario")
            return
        }
        observe({ [scenarioSettings] in scenarioSettings.appearance }) { [scenarioSettings] in
            AppearanceApplier.apply(scenarioSettings.appearance)
        }
        presentOnboarding(settings: scenarioSettings, initialStep: step)
        if CommandLine.arguments.contains(DesignBackdrop.argument) {
            onboardingWindow?.raiseAboveDesignBackdrop()
        }
    }
    #endif
}

#if DEBUG
/// 引导相关的调试场景：onboarding（第 1 步）、onboarding:permissions、onboarding:style、onboarding:shortcut
enum OnboardingScenario {
    static func step(for scenario: String) -> OnboardingStep? {
        switch scenario {
        case "onboarding": .welcome
        case "onboarding:permissions": .permissions
        case "onboarding:style": .style
        case "onboarding:shortcut": .shortcut
        default: nil
        }
    }

    /// 临时目录里的独立偏好设置（以绝对路径作为 suite 名，不进 ~/Library/Preferences），每次都从空白开始
    @MainActor
    static func makeSettings() -> AppSettings? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cubby-onboarding-scenario-\(ProcessInfo.processInfo.processIdentifier)")
        let suite = directory.appendingPathComponent("defaults").path
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }
}
#endif
