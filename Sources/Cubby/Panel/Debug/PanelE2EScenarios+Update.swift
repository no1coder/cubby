#if DEBUG
import AppKit
import CubbyCore

/// 更新提醒（docs/UPDATE-REMINDER-DESIGN.md §2 的面板 E2E 清单）：新版本横幅与「稍后」（重启后仍有效）、
/// Homebrew 变体复制命令且不进历史、询问横幅的两个按钮、升级后清除横幅与蓝点。检查由桩完成，不联网
extension PanelE2EScenarios {
    static var updates: [PanelE2EScenario] {
        [updateBanner, updateHomebrew, updateAskRemind, updateAskDecline, updateUpgraded]
    }

    static var updateBanner: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.isPaused = true
        return PanelE2EScenario(
            name: "update-banner",
            summary: "a found version shows a blue banner before \"paused\"; Not Now hides it for that version, "
                + "also after a relaunch, while the dot stays; a newer version shows it again",
            options: options
        ) { context in
            context.seedUser(checksAutomatically: true)
            context.updateStub.offer("0.3.0")
            context.updates.start()
            await context.eventually("the launch check remembers 0.3.0") {
                context.settings.knownRelease?.version.description == "0.3.0"
            }
            try await context.open()
            try await checkAvailableBanner(context)
            try await context.click("banner.update.action")
            context.checkEqual(
                "View & Download opens the release page", [PanelE2EUpdateStub.releaseURL],
                context.updateStub.openedURLs)
            try await context.click("banner.update.dismiss")
            await context.eventually("Not Now hides the banner") { context.updateBanner == nil }
            context.checkEqual(
                "… remembering the version", "0.3.0", context.settings.dismissedUpdateVersion?.description)
            context.checkStatusItemDot(expectVisible: true)
            try await context.reopen()
            context.check("reopening keeps it hidden", context.updateBanner == nil)
            try await context.relaunch()
            context.check("after a relaunch it stays hidden", context.updateBanner == nil)
            context.check("… the dot is still there", context.updates.reminder.showsDot)
            context.checkEqual("… and nothing went online again", 1, context.updateStub.checkCount)
            context.updateStub.offer("0.3.1")
            await context.updates.check()
            await context.eventually("a newer version shows the banner again") {
                context.updateBanner?.title == UpdateCopy.versionAvailable("0.3.1")
            }
        }
    }

    /// 标题、说明、按钮，以及排在权限类提醒之后、「已暂停」之前（U9）
    private static func checkAvailableBanner(_ context: PanelE2EContext) async throws {
        let banner = try requireBanner(context)
        context.checkEqual("the banner names the new version", UpdateCopy.versionAvailable("0.3.0"), banner.title)
        context.checkEqual("… and the running one", UpdateCopy.runningVersion("0.2.1"), banner.detail)
        context.checkEqual("the button opens the release page", UpdateCopy.viewAndDownload, banner.actionTitle)
        context.check("there is no Release Notes button", banner.secondaryActionTitle == nil)
        let warnings = context.viewModel.visibleWarnings
        let index = warnings.firstIndex(of: banner)
        context.check(
            "the banner sits after problem banners and before \"paused\"",
            warnings.last == .paused && index == warnings.count - 2,
            detail: "\(warnings.map(\.anchorKey))")
        context.check("the Not Now button is on screen", context.hasAnchor("banner.update.dismiss"))
    }

    static var updateHomebrew: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.isHomebrewInstall = true
        return PanelE2EScenario(
            name: "update-homebrew",
            summary: "a Homebrew install copies brew upgrade --cask cubby (marked, kept out of history) "
                + "and Release Notes opens the release page",
            options: options
        ) { context in
            context.seedUser(checksAutomatically: true, checkedRecently: true)
            try context.seedKnownRelease("0.3.0")
            context.updates.start()
            try await context.open()
            let banner = try requireBanner(context)
            context.checkEqual("the banner explains the brew command", UpdateCopy.homebrewHint, banner.detail)
            context.checkEqual("the main button copies it", UpdateCopy.copyUpgradeCommand, banner.actionTitle)
            context.checkEqual("there is a Release Notes button", UpdateCopy.releaseNotes, banner.secondaryActionTitle)
            try await context.click("banner.update.action")
            await context.eventually("the command is on the pasteboard") {
                context.world.pasteboardText == HomebrewInstall.upgradeCommand
            }
            context.check(
                "… marked so the monitor ignores it", PasteboardReader.shouldIgnore(context.world.pasteboard))
            context.check("the panel stays open", context.world.panel.debugIsShown)
            context.checkEqual("the button says Copied", UpdateCopy.copied, context.viewModel.actionTitle(for: banner))
            await context.eventually("… then goes back", timeout: .seconds(4)) {
                context.viewModel.actionTitle(for: banner) == UpdateCopy.copyUpgradeCommand
            }
            try await context.click("banner.update.secondary")
            context.checkEqual(
                "Release Notes opens the release page", [PanelE2EUpdateStub.releaseURL],
                context.updateStub.openedURLs)
            context.check("the banner is still there", context.updateBanner != nil)
        }
    }

    static var updateAskRemind: PanelE2EScenario {
        PanelE2EScenario(
            name: "update-ask-remind",
            summary: "an existing user with the check off is asked once; Remind Me turns it on and checks once"
        ) { context in
            context.seedUser(checksAutomatically: false, answered: false)
            context.updateStub.offer("0.3.0")
            context.updates.start()
            try await context.open()
            context.checkEqual("the panel asks", PanelWarning.updatePermission, context.updateBanner)
            context.checkEqual("… with Remind Me", UpdateCopy.remindMe, context.updateBanner?.actionTitle)
            context.checkEqual("… and No Thanks", UpdateCopy.noThanks, context.updateBanner?.dismissTitle)
            context.checkEqual("nothing went online before answering", 0, context.updateStub.checkCount)
            try await context.click("banner.update-permission.action")
            await context.eventually("Remind Me checks once") { context.updateStub.checkCount == 1 }
            context.check("the automatic check is on", context.settings.checksForUpdatesAutomatically)
            context.check("… and the question is answered", context.settings.hasAnsweredUpdatePrompt)
            await context.eventually("the question gives way to the found version") {
                if case .updateAvailable = context.updateBanner { return true }
                return false
            }
            try await context.relaunch()
            context.check("the answer survives a relaunch", context.settings.hasAnsweredUpdatePrompt)
            context.check("… and so does the automatic check", context.settings.checksForUpdatesAutomatically)
            context.check("it never asks again", context.updateBanner != .updatePermission)
            context.checkEqual("… and checked only once", 1, context.updateStub.checkCount)
        }
    }

    static var updateAskDecline: PanelE2EScenario {
        PanelE2EScenario(
            name: "update-ask-decline",
            summary: "No Thanks keeps the check off and never asks again, also after a relaunch"
        ) { context in
            context.seedUser(checksAutomatically: false, answered: false)
            context.updates.start()
            try await context.open()
            context.checkEqual("the panel asks", PanelWarning.updatePermission, context.updateBanner)
            try await context.click("banner.update-permission.dismiss")
            await context.eventually("No Thanks hides the question") { context.updateBanner == nil }
            context.check("the automatic check stays off", !context.settings.checksForUpdatesAutomatically)
            context.check("… and the question is answered", context.settings.hasAnsweredUpdatePrompt)
            try await context.reopen()
            context.check("reopening doesn't ask again", context.updateBanner == nil)
            try await context.relaunch()
            context.check("after a relaunch it doesn't ask again", context.updateBanner == nil)
            context.check("the answer survives the relaunch", context.settings.hasAnsweredUpdatePrompt)
            // 给可能的检查任务留出运行的机会
            try await context.settle()
            context.checkEqual("nothing went online", 0, context.updateStub.checkCount)
        }
    }

    static var updateUpgraded: PanelE2EScenario {
        PanelE2EScenario(
            name: "update-upgraded",
            summary: "after upgrading to the remembered version the banner, the dot and the remembered release are gone"
        ) { context in
            context.seedUser(checksAutomatically: true, checkedRecently: true)
            try context.seedKnownRelease("0.3.0")
            context.updates.start()
            try await context.open()
            context.check("before upgrading the banner shows", context.updateBanner != nil)
            context.checkStatusItemDot(expectVisible: true)
            try await context.relaunch(currentVersion: "0.3.0")
            context.check("the remembered release is cleared", context.settings.knownRelease == nil)
            context.check("no update banner", context.updateBanner == nil)
            context.check("no dot", !context.updates.reminder.showsDot)
            context.checkStatusItemDot(expectVisible: false)
            context.checkEqual("nothing went online", 0, context.updateStub.checkCount)
        }
    }

    /// 取当前的更新横幅，没有就中止脚本
    private static func requireBanner(_ context: PanelE2EContext) throws -> PanelWarning {
        guard let banner = context.updateBanner else { throw PanelE2EError.missingAnchor("update banner") }
        return banner
    }
}
#endif
