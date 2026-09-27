#if DEBUG
import AppKit
import CubbyCore

/// 存储类脚本（设计文档 §9.4）：存储对话框（桩）确认 / 取消、关闭「每次询问」后直接存储、贴图的存储
extension E2EScenarios {
    /// 「Cubby 2026-09-27 08.12.34.png」
    private static func isDefaultName(_ name: String?) -> Bool {
        name?.wholeMatch(of: /Cubby \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}\.png/) != nil
    }

    private static var savedPrefix: String {
        E2EText.localized("Saved to %@").replacingOccurrences(of: " %@", with: "")
    }

    static var save: E2EScenario {
        E2EScenario(
            name: "save",
            summary: "cmd-S asks where to save; confirming writes the chosen file, adds history, remembers the folder",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([smallStart, smallEnd]),
                .replySave { .url($0.world.pickedDirectory.appendingPathComponent("Chosen name.png")) },
                .command("s"),
                .expectIdle,
                .expectEqual("the dialog was asked once", 1) { $0.world.savePrompt.requests.count },
                .expect("suggested name is \"Cubby YYYY-MM-DD HH.MM.SS.png\"") {
                    isDefaultName($0.world.savePrompt.requests.first?.suggestedName)
                },
                .expectEqual("the dialog starts in the save folder from Settings", { $0.world.saveDirectory.path }) {
                    $0.world.savePrompt.requests.first?.directory.path
                },
                .eventually("the chosen file was written") { context in
                    context.world.pickedFiles.map(\.lastPathComponent) == ["Chosen name.png"]
                },
                .expect("the file is a PNG of the selection's pixel size") { context in
                    guard let url = context.world.pickedFiles.first, let data = try? Data(contentsOf: url),
                        let image = E2EImage(png: data)
                    else { return false }
                    let size = context.pixelSize(of: context.globalRect(smallRect))
                    return image.width == Int(size.width) && image.height == Int(size.height)
                },
                .expectEqual("nothing is written to the default folder", 0) { $0.world.savedFiles.count },
                .expectHUD(containing: savedPrefix),
                .expectPasteboardUnchanged,
                .expectHistoryDelta(1),
                .expectEqual("the chosen folder is remembered", { $0.world.pickedDirectory.path }) {
                    $0.world.settings.screenshotSaveDirectory?.path
                },
                // 下一次存储从上次的文件夹开始
                .start(at: desktop),
                .drag([smallStart, smallEnd]),
                .replySave { _ in .cancel },
                .command("s"),
                .eventually("the dialog is asked again") { $0.world.savePrompt.requests.count == 2 },
                .expectEqual("the next dialog opens the folder used last time", { $0.world.pickedDirectory.path }) {
                    $0.world.savePrompt.requests.last?.directory.path
                },
                .eventually("cancelling brings the overlay back") { $0.world.isOverlayPresented },
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var saveCancel: E2EScenario {
        E2EScenario(
            name: "save-cancel",
            summary: "cancelling the save dialog restores the overlay with its annotations and undo history",
            steps: [.markOutputs] + selectCanvas + drawRectangle + [
                .letter("a"),
                .drag([.at(1300, 300), .at(1450, 420)]),
                .command("z"),
                .remember("session before saving") { context in
                    let session = try context.requireSession()
                    context.numbers["annotations"] = session.document.annotations.count
                    context.rects["selection"] = try context.requireSelection()
                    context.strings["phase"] = "\(session.phase)"
                },
                .replySave { _ in .hold },
                .command("s"),
                .eventually("the save dialog is open") { $0.world.savePrompt.isOpen },
                .expect("the overlay is hidden while the dialog is open") { !$0.world.isOverlayPresented },
                .expect("the session is still active") { $0.world.isActive },
                // 对话框打开期间再按截图快捷键：把对话框提到前面，不开始新截图、不取消
                .hotKeyAgain,
                .expectEqual("the shortcut brings the dialog to the front", 1) {
                    $0.world.savePrompt.bringToFrontCount
                },
                .expect("the dialog is still open") { $0.world.savePrompt.isOpen },
                .action("click Cancel in the save dialog") { context in context.world.savePrompt.resolve(nil) },
                .eventually("the overlay comes back") { $0.world.isOverlayPresented },
                .expectEqual("annotations are kept", { $0.numbers["annotations"] }) {
                    try $0.requireSession().document.annotations.count
                },
                .expect("undo and redo history are kept") { context in
                    let document = try context.requireSession().document
                    return document.canUndo && document.canRedo
                },
                .expectSelection("the selection is kept") { try $0.rememberedSelection() },
                .expectEqual("the phase is kept", { $0.strings["phase"] }) { "\(try $0.requireSession().phase)" },
                .expectEqual("no file was written", 0) { $0.world.savedFiles.count + $0.world.pickedFiles.count },
                // 还能继续编辑，并改走其他出口
                .command("z", shift: true),
                .expectEqual("redo still works after resuming", { ($0.numbers["annotations"] ?? 0) + 1 }) {
                    try $0.requireSession().document.annotations.count
                },
                .command("c"),
                .expectIdle,
                .expectPNG("cmd-C finishes the resumed session") { $0.pixelSize(of: $0.globalRect(canvasRect)) },
                .expectEqual("the session ended with a copy", "copy") { $0.world.results.last },
                .expectHistoryDelta(1),
            ]
        )
    }

    /// 回归：暂停态的覆盖层被取消（对话框仍开着）时会话必须结束，之后对话框的回复不能再写文件或复活覆盖层
    static var saveOverlayCancelled: E2EScenario {
        E2EScenario(
            name: "save-overlay-cancelled",
            summary: "cancelling the suspended overlay while the save dialog is open ends the session cleanly",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([smallStart, smallEnd]),
                .replySave { _ in .hold },
                .command("s"),
                .eventually("the save dialog is open") { $0.world.savePrompt.isOpen },
                .action("cancel the suspended overlay") { context in context.world.overlay?.cancel() },
                .expectIdle,
                .action("confirm the dialog afterwards") { context in
                    context.world.savePrompt.resolve(context.world.pickedDirectory.appendingPathComponent("Late.png"))
                },
                .expectIdle,
                .expect("the overlay does not come back") { !$0.world.isOverlayPresented },
                .expectEqual("no file was written", 0) { $0.world.savedFiles.count + $0.world.pickedFiles.count },
                .expectHistoryDelta(0),
                // 协调器没有卡在「存储中」：还能开始新的截图
                .start(at: desktop),
                .expect("a new screenshot can start") { $0.world.isOverlayPresented },
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var saveDirect: E2EScenario {
        var options = E2EWorld.Options()
        options.asksWhereToSave = false
        return E2EScenario(
            name: "save-direct",
            summary: "with \"ask where to save\" off, cmd-S writes straight to the save folder without a dialog",
            options: options,
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([smallStart, smallEnd]),
                .command("s"),
                .expectIdle,
                .eventually("one file in the save folder") { $0.world.savedFiles.count == 1 },
                .expect("file name is \"Cubby YYYY-MM-DD HH.MM.SS.png\"") {
                    isDefaultName($0.world.savedFiles.first?.lastPathComponent)
                },
                .expectEqual("no dialog was shown", 0) { $0.world.savePrompt.requests.count },
                .expectHUD(containing: savedPrefix),
                .expectPasteboardUnchanged,
                .expectHistoryDelta(1),
            ]
        )
    }

    static var pinSave: E2EScenario {
        let pinCenter = E2EPoint.computed { context in
            guard let window = context.world.pinWindows.first else { throw E2EScriptError.unavailable("pin window") }
            return ScreenTopologyProvider.toGlobal(CGPoint(x: window.frame.midX, y: window.frame.midY))
        }
        return E2EScenario(
            name: "pin-save",
            summary: "a pin's Save uses the same save dialog, writes the chosen file and remembers the folder",
            steps: [
                .start(at: desktop),
                .drag([smallStart, smallEnd]),
                .command("p"),
                .expectIdle,
                .eventually("one pin window on screen") { $0.world.pinWindows.count == 1 },
                .click(pinCenter),
                .eventually("clicking the pin makes it key") { $0.world.pinWindows.first?.isKeyWindow == true },
                .markOutputs,
                .replySave { .url($0.world.pickedDirectory.appendingPathComponent("Pinned.png")) },
                .command("s"),
                .eventually("the pin is saved where the dialog pointed") { context in
                    context.world.pickedFiles.map(\.lastPathComponent) == ["Pinned.png"]
                },
                .expect("the pin's dialog suggests the default file name") {
                    isDefaultName($0.world.savePrompt.requests.last?.suggestedName)
                },
                .expectHUD(containing: savedPrefix),
                .expectEqual("the chosen folder is remembered", { $0.world.pickedDirectory.path }) {
                    $0.world.settings.screenshotSaveDirectory?.path
                },
                .expectHistoryDelta(0),
            ]
        )
    }
}

extension E2EStep {
    /// 设定存储对话框（桩）对下一次请求的回复
    static func replySave(_ reply: @escaping @MainActor (E2EContext) -> E2ESavePrompt.Reply) -> E2EStep {
        action("set the save dialog's reply") { context in context.world.savePrompt.reply = reply(context) }
    }
}
#endif
