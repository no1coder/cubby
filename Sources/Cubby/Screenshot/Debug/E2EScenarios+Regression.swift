#if DEBUG
import AppKit
import CubbyCore

/// 覆盖层审查问题的回归脚本
extension E2EScenarios {
    /// 导出进行中（覆盖层已隐藏）再按快捷键：已确认的复制不能被丢掉
    static var finishingHotKey: E2EScenario {
        var options = E2EWorld.Options()
        options.exportDelay = .milliseconds(800)
        return E2EScenario(
            name: "finishing-hotkey",
            summary: "shortcut pressed while the export is still running must not drop the confirmed copy",
            options: options,
            steps: [
                .markOutputs,
                .start(at: desktop),
                .click(editorOnly),
                .key(.returnKey),
                .expect("overlay hidden while the export runs") { context in
                    context.world.overlay?.debugIsFinished == true && context.world.isActive
                },
                .hotKeyAgain,
                .expectIdle,
                .expectEqual("result is still copy", "copy") { $0.world.results.last },
                .expectPNG("the PNG reaches the pasteboard") { $0.pixelSize(of: $0.globalRect(editorFrame)) },
                .expectHUD(containing: E2EText.copied),
                .expectHistoryDelta(1),
            ]
        )
    }

    /// 修饰键 / 空格的松开落在别处，或焦点被抢走后才回来：会话里不能残留按下状态
    static var keyboardState: E2EScenario {
        let inside = E2EPoint.at(1500, 400)
        return E2EScenario(
            name: "keyboard-state",
            summary: "shift / space released outside the overlay, or while focus was stolen, do not stick",
            steps: selectCanvas + [
                .hold(.shift),
                .expect("shift reaches the session") { try $0.requireSession().modifiers.contains(.shift) },
                .stealFocus,
                .action("release shift in the other window") { context in
                    try await context.driver.setModifiers([], window: context.focusThief)
                },
                .expect("shift released elsewhere is cleared") {
                    !(try $0.requireSession().modifiers.contains(.shift))
                },
                .expectEqual("color format back to hex", ColorFormat.hex) { try $0.requireSession().colorFormat },
                .click(inside),
                .expect("clicking the overlay makes it key again") {
                    $0.world.overlay?.debugWindows.first?.isKeyWindow == true
                },
                .spaceDown,
                .expect("space reaches the session") { try $0.requireSession().modifiers.contains(.space) },
                .stealFocus,
                .action("release space in the other window") { context in
                    try await context.driver.keyUp(.space, window: context.focusThief)
                },
                .expect("space released elsewhere is cleared") {
                    !(try $0.requireSession().modifiers.contains(.space))
                },
                // 焦点被抢走期间松开（事件根本到不了 Cubby），回到覆盖层时按真实键盘状态重置
                .click(inside),
                .hold(.shift),
                .expect("shift held again") { try $0.requireSession().modifiers.contains(.shift) },
                .stealFocus,
                .action("shift released in another app (no event)") { context in context.driver.forgetModifiers() },
                .click(inside),
                .expect("regaining focus resets stale modifiers") {
                    !(try $0.requireSession().modifiers.contains(.shift))
                },
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    /// 编辑文字时编辑框上是 I 形光标，框外是箭头
    static var textCursor: E2EScenario {
        E2EScenario(
            name: "text-cursor",
            summary: "the I-beam cursor over the text editor is not overridden by the arrow",
            steps: selectCanvas + [
                .letter("t"),
                .click(.at(1100, 300)),
                .type("Hello"),
                .move(.at(1112, 310)),
                .expectEqual("I-beam entering the editor", "iBeam") { _ in E2EInspect.cursorName },
                .move(.at(1116, 312)),
                .expectEqual("I-beam while moving inside the editor", "iBeam") { _ in E2EInspect.cursorName },
                .hold(.shift),
                .releaseModifiers,
                .expectEqual("I-beam after a modifier change over the editor", "iBeam") { _ in E2EInspect.cursorName },
                .move(.at(1600, 500)),
                .expectEqual("arrow outside the editor", "arrow") { _ in E2EInspect.cursorName },
                .key(.escape),
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }
}

extension E2EStep {
    /// 另一个窗口成为 key（模拟系统弹窗抢走焦点）
    static var stealFocus: E2EStep {
        action("another window takes the key focus") { context in
            let thief = context.focusThief ?? E2EFocusThief.make(on: context.world.screen)
            context.focusThief = thief
            thief.orderFrontRegardless()
            thief.makeKey()
            try await context.driver.flush()
            guard thief.isKeyWindow else { throw E2EScriptError.unavailable("focus thief key status") }
        }
    }
}

/// 抢焦点用的小面板：不激活应用、可成为 key，放在屏幕左下角
@MainActor
enum E2EFocusThief {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    static func make(on screen: CaptureScreen) -> NSWindow {
        let frame = ScreenTopologyProvider.toAppKit(
            CGRect(x: screen.frame.minX + 40, y: screen.frame.maxY - 160, width: 160, height: 100))
        let panel = Panel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .systemGray
        panel.isReleasedWhenClosed = false
        return panel
    }
}
#endif
