#if DEBUG
import AppKit
import CubbyCore

/// 更新横幅的走查截图（docs/UPDATE-REMINDER-DESIGN.md U4、U5、U8、U9）：`Cubby --panel-e2e update-shots,update-shots-brew`
/// （CUBBY_SHOTS_DIR 指定输出目录）。只在点名时运行
extension PanelE2EShots {
    static var updateShots: [PanelE2EScenario] {
        [askAndAvailableShots, homebrewShots]
    }

    /// 询问横幅；之后查到新版本，与「已暂停」横幅一起出现（看排序与两种颜色）
    private static var askAndAvailableShots: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.isPaused = true
        return PanelE2EScenario(
            name: "update-shots", summary: "walkthrough screenshots of the ask and new-version banners",
            options: options
        ) { context in
            applyRequestedAppearance()
            context.seedUser(checksAutomatically: false, answered: false)
            context.updates.start()
            try await context.open()
            try await shot(context, "update-ask")
            context.world.panel.hide(animated: false)
            // 打开开关会触发一次检查：让桩也返回同一个版本
            context.updateStub.offer("0.3.0")
            context.settings.answerUpdatePrompt(remindMe: true)
            try context.seedKnownRelease("0.3.0")
            try await context.open()
            try await shot(context, "update-available-paused")
        }
    }

    private static var homebrewShots: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.isHomebrewInstall = true
        return PanelE2EScenario(
            name: "update-shots-brew", summary: "walkthrough screenshots of the Homebrew new-version banner",
            options: options
        ) { context in
            applyRequestedAppearance()
            context.seedUser(checksAutomatically: true, checkedRecently: true)
            try context.seedKnownRelease("0.3.0")
            context.updates.start()
            try await context.open()
            try await shot(context, "update-brew")
            try await context.click("banner.update.action")
            try await shot(context, "update-brew-copied")
        }
    }

    private static func applyRequestedAppearance() {
        if ProcessInfo.processInfo.environment["CUBBY_SHOTS_APPEARANCE"] == "light" {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
    }
}
#endif
