#if DEBUG
import AppKit
import CubbyCore

/// 出口类脚本：贴图、提取文字、取色（存储见 E2EScenarios+Save.swift）
extension E2EScenarios {
    static let smallStart = E2EPoint.at(1050, 150)
    static let smallEnd = E2EPoint.at(1350, 350)
    static let smallRect = CGRect(x: 1050, y: 150, width: 300, height: 200)

    static var pin: E2EScenario {
        let pinCenter = E2EPoint.computed { context in
            guard let window = context.world.pinWindows.first else { throw E2EScriptError.unavailable("pin window") }
            return ScreenTopologyProvider.toGlobal(CGPoint(x: window.frame.midX, y: window.frame.midY))
        }
        return E2EScenario(
            name: "pin",
            summary: "cmd-P pins the selection in place; cmd-C copies the pin; double-click closes it",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([smallStart, smallEnd]),
                .command("p"),
                .expectIdle,
                .eventually("one pin window on screen") { $0.world.pinWindows.count == 1 },
                .expectEqual(
                    "pin sits exactly on the selection", { ScreenTopologyProvider.toAppKit($0.globalRect(smallRect)) }
                ) {
                    $0.world.pinWindows.first?.frame
                },
                .expectPasteboardUnchanged,
                .expectHistoryDelta(1),
                .click(pinCenter),
                .eventually("clicking the pin makes it key") { $0.world.pinWindows.first?.isKeyWindow == true },
                .markHUD,
                .command("c"),
                .expectPNG("cmd-C copies the pin to the (private) pasteboard") {
                    $0.pixelSize(of: $0.globalRect(smallRect))
                },
                .expectHUD(containing: E2EText.copied),
                .click(pinCenter, count: 2),
                .eventually("double-click closes the pin") { $0.world.pinWindows.isEmpty && $0.world.pins.count == 0 },
            ]
        )
    }

    static var extractText: E2EScenario {
        E2EScenario(
            name: "ocr",
            summary: "cmd-T recognizes the fixture's pangram and copies it as text",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([.fromBottom(12, 214), .fromBottom(560, 160)]),
                .command("t"),
                .expectIdle,
                .expectHUD(containing: E2EText.localized("Recognizing text\u{2026}")),
                .eventually("pasteboard text contains the pangram", timeout: .seconds(20)) { context in
                    guard let text = context.world.pasteboardText?.lowercased() else { return false }
                    return ["quick", "brown", "fox", "lazy", "0123456789"].allSatisfy(text.contains)
                } detail: {
                    "pasteboard text: \($0.world.pasteboardText ?? "none")"
                },
                .expectHUD(containing: E2EText.localized("Text copied")),
                .expectHistoryDelta(1),
                .expect("history item is text") { $0.world.history.first?.kind == .text },
            ]
        )
    }

    static var colorPick: E2EScenario {
        let red = E2EPoint.fromBottom(44, 130)
        return E2EScenario(
            name: "color-pick",
            summary: "C copies the magnifier color as HEX (a color item), shift gives rgb()",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .move(red),
                .letter("c"),
                .expectIdle,
                .eventually("pasteboard has #FF3B30") { $0.world.pasteboardText == AnnotationColor.red.hex },
                .expectHistoryDelta(1),
                .expect("history recognizes it as a color") { $0.world.history.first?.kind == .color },
                .expectHUD(containing: AnnotationColor.red.hex),
                .markOutputs,
                .start(at: desktop),
                .move(red),
                .hold(.shift),
                .expectEqual("shift switches the magnifier to rgb", ColorFormat.rgb) {
                    try $0.requireSession().colorFormat
                },
                .key(.character("c")),
                .releaseModifiers,
                .expectIdle,
                .eventually("pasteboard has rgb(255, 59, 48)") { $0.world.pasteboardText == "rgb(255, 59, 48)" },
                .expectHistoryDelta(1),
                .expect("rgb() is a color item too") { $0.world.history.first?.kind == .color },
            ]
        )
    }
}
#endif
