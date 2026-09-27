#if DEBUG
import AppKit
import CubbyCore

/// 流程类脚本：Esc / 右键二次确认、逐层切换、纯净窗口、再按快捷键、暂停记录
extension E2EScenarios {
    /// 三个假窗口共同重叠处：候选栈 = [9001, 9002, 9003, 整屏]
    static let overlap = E2EPoint.at(600, 300)

    /// 画一个矩形（从 adjusting 进入 annotating）
    static var drawRectangle: [E2EStep] {
        [
            .letter("r"), .drag([.at(1100, 200), .at(1250, 300)]),
            .expect("rectangle drawn") { try $0.requireSession().hasAnnotations },
        ]
    }

    static var escapeConfirm: E2EScenario {
        let hint = ScreenshotHint.pressEscapeAgainToDiscard.message
        return E2EScenario(
            name: "esc-confirm",
            summary: "with annotations the first Esc / hovering right-click only arms, the second cancels",
            steps: [.markOutputs] + selectCanvas + drawRectangle + [
                .key(.escape),
                .expect("first Esc arms discard") { try $0.requireSession().isDiscardArmed },
                .expectPresented,
                .expectEqual("overlay shows the discard hint", hint) {
                    $0.world.overlay?.debugScreenViews.compactMap(\.debugHintText).first
                },
                .key(.escape),
                .expectIdle,
                .expectEqual("result is cancel", "cancel") { $0.world.results.last },
                // 右键：有选区时清选区回 hovering（标注保留），hovering 时与 Esc 一样要两次
            ] + selectCanvas + drawRectangle + [
                .rightClick(.at(1500, 500)),
                .expectPhase(.hovering),
                .expect("annotations survive clearing the selection") { try $0.requireSession().hasAnnotations },
                .rightClick(.at(1500, 500)),
                .expect("first hovering right-click arms discard") { try $0.requireSession().isDiscardArmed },
                .expectPresented,
                .expectEqual("hovering right-click shows the same hint", hint) {
                    $0.world.overlay?.debugScreenViews.compactMap(\.debugHintText).first
                },
                .move(.at(1510, 510)),
                .expect("moving the mouse keeps discard armed") { try $0.requireSession().isDiscardArmed },
                .rightClick(.at(1500, 500)),
                .expectIdle,
                // 没有标注时 hovering 右键直接取消
                .start(at: desktop),
                .rightClick(.at(1500, 500)),
                .expectIdle,
                .expectPasteboardUnchanged,
                .expectHistoryDelta(0, settle: .milliseconds(200)),
            ]
        )
    }

    static var hoverCycle: E2EScenario {
        E2EScenario(
            name: "hover-cycle",
            summary: "Tab / shift-Tab and precise / line scrolling walk the window stack one layer at a time",
            steps: [
                .start(at: desktop),
                // 非编辑阶段吞掉所有按键：⌘Q 不能退出 Cubby
                .command("q"),
                .expectPresented,
                .move(overlap),
                .expectEqual("stack under the cursor has 4 layers", 4) { context in
                    WindowHitTester.candidates(at: try context.requireSession().cursor, in: try context.topology())
                        .count
                },
                .expectDepth(0, window: 9001),
                .key(.tab), .expectDepth(1, window: 9002),
                .key(.tab), .expectDepth(2, window: 9003),
                .key(.tab), .expectDepth(3, window: nil),
                .key(.tab), .expectDepth(3, window: nil),
                .key(.tab, .shift), .expectDepth(2, window: 9003),
                .key(.tab, .shift), .expectDepth(1, window: 9002),
                .key(.tab, .shift), .expectDepth(0, window: 9001),
                .key(.tab, .shift), .expectDepth(0, window: 9001),
                // 触控板：累积到阈值才走一层
                .scroll(-25, precise: true, at: overlap), .expectDepth(0, window: 9001),
                .scroll(-25, precise: true, at: overlap), .expectDepth(1, window: 9002),
                // 行式滚轮：一格一层
                .scroll(-1, precise: false, at: overlap), .expectDepth(2, window: 9003),
                // 惯性阶段的事件被忽略
                .scroll(-80, precise: true, momentum: true, at: overlap), .expectDepth(2, window: 9003),
                .scroll(1, precise: false, at: overlap), .expectDepth(1, window: 9002),
                .scroll(45, precise: true, at: overlap), .expectDepth(0, window: 9001),
                // 同一叠内移动保持层深；换到另一叠归零
                .key(.tab), .move(.at(610, 310)), .expectDepth(1, window: 9002),
                .move(editorOnly), .expectDepth(0, window: 9001),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var windowCapture: E2EScenario {
        E2EScenario(
            name: "window-capture",
            summary: "space toggles window mode, click captures the window (fixture source), option drops the shadow",
            steps: [
                .markOutputs,
                .start(at: desktop),
                // 整屏目标上空格无效
                .spaceDown, .spaceUp,
                .expect("space on the desktop does not enter window mode") {
                    !(try $0.requireSession().isWindowCaptureMode)
                },
                .move(overlap),
                .spaceDown, .spaceUp,
                .expect("space on a window enters window mode") { try $0.requireSession().isWindowCaptureMode },
                .expect("magnifier hides in window mode") { !(try $0.requireSession().isMagnifierVisible) },
                .key(.tab),
                .expectDepth(1, window: 9002),
                .expect("Tab keeps window mode on a window target") { try $0.requireSession().isWindowCaptureMode },
                .click(overlap),
                .expectIdle,
                .expectEqual("result is captureWindow(9002, shadow)", "captureWindow(9002, shadow: true)") {
                    $0.world.results.last
                },
                // fixture 带阴影时四周各留 40 pt
                .expectPNG("window PNG includes the shadow margin") { context in
                    CGSize(width: (420 + 80) * context.scale, height: (320 + 80) * context.scale)
                },
                .expectHistoryDelta(1),
                .expectHUD(containing: E2EText.copied),
                .markOutputs,
                .start(at: desktop),
                .move(editorOnly),
                .spaceDown, .spaceUp,
                .expect("space enters window mode on window 9001") { context in
                    let session = try context.requireSession()
                    return session.isWindowCaptureMode && session.hover?.windowID == 9001
                },
                .hold(.option),
                .click(editorOnly),
                .releaseModifiers,
                .expectIdle,
                .expectEqual("option-click drops the shadow", "captureWindow(9001, shadow: false)") {
                    $0.world.results.last
                },
                .expectPNG("window PNG without shadow is the window size") { context in
                    CGSize(width: 460 * context.scale, height: 300 * context.scale)
                },
                .expectHistoryDelta(1),
            ]
        )
    }

    static var windowCaptureFailure: E2EScenario {
        var options = E2EWorld.Options()
        options.windowSource = .failing
        return E2EScenario(
            name: "window-capture-failure",
            summary: "capturing a fake window id fails gracefully: warning HUD, session ends, nothing copied",
            options: options,
            steps: [
                .markOutputs,
                .start(at: desktop),
                .move(editorOnly),
                .spaceDown, .spaceUp,
                .key(.returnKey),
                .expectEqual("Return in window mode captures the window", "captureWindow(9001, shadow: true)") {
                    $0.world.results.last
                },
                .expectIdle,
                .expectHUD(containing: E2EText.localized("Couldn't capture the window")),
                .expectPasteboardUnchanged,
                .expectHistoryDelta(0, settle: .milliseconds(200)),
                // 失败后可以立即开始下一次截图（没有卡在采集状态）
                .start(at: desktop),
                .key(.escape),
                .expectIdle,
            ]
        )
    }

    static var hotKeyAgain: E2EScenario {
        E2EScenario(
            name: "hotkey-again",
            summary: "the screenshot shortcut during a session cancels without annotations, is ignored with them",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .move(editorOnly),
                .hotKeyAgain,
                .expectIdle,
                .expectEqual("hovering without annotations: cancelled", "cancel") { $0.world.results.last },
            ] + selectCanvas + [
                .hotKeyAgain,
                .expectIdle,
                .expectEqual("adjusting without annotations: cancelled", "cancel") { $0.world.results.last },
            ] + selectCanvas + drawRectangle + [
                .hotKeyAgain,
                .expectPresented,
                .expect("annotations are kept") { try $0.requireSession().hasAnnotations },
                // 编辑文字（尚无标注）时同样忽略
                .letter("t"),
                .click(.at(1500, 500)),
                .expectPhase(.editingText),
                .hotKeyAgain,
                .expectPresented,
                .expectPhase(.editingText),
                .key(.escape),
                .key(.escape),
                .key(.escape),
                .expectIdle,
                .expectPasteboardUnchanged,
            ]
        )
    }

    static var paused: E2EScenario {
        var options = E2EWorld.Options()
        options.isPaused = true
        return E2EScenario(
            name: "paused",
            summary: "with recording paused the screenshot is still copied but not added to history",
            options: options,
            steps: [
                .markOutputs,
                .start(at: desktop),
                .click(editorOnly),
                .key(.returnKey),
                .expectIdle,
                .expectPNG("pasteboard still gets the PNG") { $0.pixelSize(of: $0.globalRect(editorFrame)) },
                .expectHistoryDelta(0),
                .expectHUD(containing: E2EText.copied),
            ]
        )
    }
}

extension E2EStep {
    /// 悬停层深与目标窗口（nil = 整屏）
    static func expectDepth(_ depth: Int, window: UInt32?) -> E2EStep {
        expect("depth \(depth) targets \(window.map { "window \($0)" } ?? "the whole screen")") { context in
            let session = try context.requireSession()
            return session.hoverDepth == depth && session.hover?.windowID == window && session.hover != nil
        }
    }
}

extension E2EContext {
    /// 当前会话的拓扑（与覆盖层所用相同的 fixture）
    func topology() throws -> ScreenTopology {
        guard let capture = world.lastCapture else { throw E2EScriptError.unavailable("capture") }
        return capture.topology
    }
}
#endif
