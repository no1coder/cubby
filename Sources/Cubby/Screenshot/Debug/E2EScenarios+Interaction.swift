#if DEBUG
import AppKit
import CubbyCore

/// 细节交互脚本：工具栏按钮、选区手势（⌘A、拖拽中 Esc、空格平移、⌥ 中心）、标注编辑细节、光标
extension E2EScenarios {
    static var toolbar: E2EScenario {
        E2EScenario(
            name: "toolbar",
            summary: "toolbar buttons clicked with the mouse: tool, undo / redo, pointer, done",
            steps: [.markOutputs] + selectCanvas + [
                .clickToolbar(.tool(.rectangle)),
                .expectPhase(.annotating),
                .expectEqual("toolbar selects the rectangle tool", ScreenshotTool.rectangle) {
                    try $0.requireSession().tool
                },
                .drag([.at(1100, 200), .at(1250, 300)]),
                .clickToolbar(.undo),
                .expectEqual("toolbar undo", 0) { try $0.requireSession().document.annotations.count },
                .clickToolbar(.redo),
                .expectEqual("toolbar redo", 1) { try $0.requireSession().document.annotations.count },
                .clickToolbar(.tool(.pointer)),
                .expectPhase(.adjusting),
                .clickToolbar(.done),
                .expectIdle,
                .expectEqual("done copies", "copy") { $0.world.results.last },
                .expectPNG("PNG has the selection's pixel size") {
                    $0.pixelSize(of: $0.globalRect(CGRect(x: 1050, y: 150, width: 900, height: 500)))
                },
                .expectHistoryDelta(1),
            ]
        )
    }

    static var selectionGestures: E2EScenario {
        E2EScenario(
            name: "selection-gestures",
            summary: "cmd-A, Esc / right-click while dragging, space pans, option drags from the center",
            steps: [
                .start(at: desktop),
                .command("a"),
                .expectPhase(.adjusting),
                .expectSelection("cmd-A selects the whole screen") { $0.world.screen.frame },
                .rightClick(.at(1500, 500)),
                .expectPhase(.hovering),
                // 拖拽中 Esc：没有原选区时回 hovering
                .mouseDown(.at(1100, 200)),
                .mouseDrag(.at(1300, 350)),
                .expectPhase(.selecting),
                .key(.escape),
                .expectPhase(.hovering),
                .expectPresented,
                .mouseUp(.at(1300, 350)),
                .expectPhase(.hovering),
                // 有原选区时 Esc / 右键恢复它
                .drag([.at(1100, 200), .at(1300, 350)]),
                .rememberSelection,
                .mouseDown(.at(1500, 400)),
                .mouseDrag(.at(1700, 550)),
                .expectPhase(.selecting),
                .key(.escape),
                .expectPhase(.adjusting),
                .expectSelection("Esc while dragging restores the previous selection") { try $0.rememberedSelection() },
                .mouseUp(.at(1700, 550)),
                .mouseDown(.at(1500, 400)),
                .mouseDrag(.at(1700, 550)),
                .rightClick(.at(1700, 550)),
                .expectSelection("right-click while dragging restores it too") { try $0.rememberedSelection() },
                .mouseUp(.at(1700, 550)),
                // 按住空格平移正在拖出的选区（尺寸不变）
                .mouseDown(.at(1500, 300)),
                .mouseDrag(.at(1600, 380)),
                .spaceDown,
                .mouseDrag(.at(1650, 400)),
                .spaceUp,
                .mouseUp(.at(1650, 400)),
                .expectSelection("space pans the selection by (50, 20)") {
                    $0.globalRect(CGRect(x: 1550, y: 320, width: 100, height: 80))
                },
                // ⌥：以起点为中心
                .hold(.option),
                .drag([.at(1300, 500), .at(1350, 530)]),
                .releaseModifiers,
                .expectSelection("option drags from the center") {
                    $0.globalRect(CGRect(x: 1250, y: 470, width: 100, height: 60))
                },
                // 滚轮在有选区时无操作
                .rememberSelection,
                .scroll(-3, precise: false, at: .at(1300, 500)),
                .expectSelection("scrolling does nothing with a selection") { try $0.rememberedSelection() },
                .expectPhase(.adjusting),
                // 双击选区内完成
                .markOutputs,
                .click(.at(1300, 500), count: 2),
                .expectIdle,
                .expectEqual("double-click inside the selection copies", "copy") { $0.world.results.last },
                .expectPNG("PNG is the option-drag selection") {
                    $0.pixelSize(of: $0.globalRect(CGRect(x: 1250, y: 470, width: 100, height: 60)))
                },
            ]
        )
    }

    static var annotationDetails: E2EScenario {
        E2EScenario(
            name: "annotation-details",
            summary: "arrow keys nudge the selected annotation, one undo per drag, styles persist, text click-away",
            steps: selectCanvas + [
                .move(.at(1985, 700)),
                .expectEqual("crosshair while adjusting outside the selection", "crosshair") { _ in
                    E2EInspect.cursorName
                },
                .move(.at(1500, 400)),
                .expectEqual("move cursor inside the selection", "move") { _ in E2EInspect.cursorName },
                .letter("r"),
                .drag([.at(1100, 200), .at(1250, 300)]),
                .letter("v"),
                .click(.at(1100, 250)),
                .remember("rectangle") { context in context.annotations["rect"] = try context.lastAnnotation() },
                .key(.rightArrow),
                .key(.downArrow, .shift),
                .expectEqual(
                    "arrow keys move the selected annotation, not the selection",
                    { context in
                        context.annotations["rect"]?.translated(by: CGVector(dx: 1, dy: 10)).shape
                    }
                ) { try $0.lastAnnotation().shape },
                .expectSelection("selection did not move") {
                    $0.globalRect(CGRect(x: 1050, y: 150, width: 900, height: 500))
                },
                .remember("rectangle after nudge") { context in
                    context.annotations["rect"] = try context.lastAnnotation()
                },
                .drag([.at(1101, 260), .at(1141, 260)]),
                .command("z"),
                .expectEqual("one undo reverts the whole drag", { $0.annotations["rect"]?.shape }) {
                    try $0.lastAnnotation().shape
                },
                .click(.at(1101, 260)),
                .clickColor(.green),
                .expectEqual("the recolor is remembered for the tool", AnnotationColor.green) { context in
                    context.world.settings.annotationStyles.style(for: .rectangle).color
                },
                // 编辑文字时点击框外：只提交，这次点击不产生其他效果
                .letter("t"),
                .click(.at(1500, 400)),
                .type("abc"),
                .click(.at(1700, 550)),
                .expectPhase(.annotating),
                .expect("click-away commits exactly one text and opens no new editor") { context in
                    let session = try context.requireSession()
                    let texts = session.document.annotations.filter { $0.tool == .text }
                    return texts.count == 1 && session.textEditing == nil && context.world.overlay?.debugEditor == nil
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
            ]
        )
    }
}
#endif

#if DEBUG
/// 边界情况：采集中取消、整屏、贴边夹紧、手柄最小尺寸、取色时机、没有文字的 OCR
extension E2EScenarios {
    static var edgeCases: E2EScenario {
        let corner = E2EPoint.computed { context in
            let frame = context.world.screen.frame
            return CGPoint(x: frame.maxX - 60, y: frame.maxY - 80)
        }
        let beyond = E2EPoint.computed { context in
            let frame = context.world.screen.frame
            return CGPoint(x: frame.maxX + 140, y: frame.maxY + 120)
        }
        let cornerRect: @MainActor @Sendable (E2EContext) -> CGRect = { context in
            let frame = context.world.screen.frame
            return CGRect(x: frame.maxX - 60, y: frame.maxY - 80, width: 60, height: 80)
        }
        return E2EScenario(
            name: "edge-cases",
            summary: "cancel during capture, whole screen, clamping at the edge, minimum size, color pick timing",
            steps: [
                .markOutputs,
                // 采集中再按快捷键：取消，迟到的帧不再上屏
                .startWithoutWaiting(at: desktop),
                .hotKeyAgain,
                .expectIdle,
                .wait(600),
                .expectEqual("the late capture never shows an overlay", 0) { $0.world.overlays.count },
                // 桌面上 ↩：整屏
                .start(at: desktop),
                .key(.returnKey),
                .expectIdle,
                .expectPNG("Return on the desktop copies the whole screen") { $0.world.screen.pixelSize },
                .expectHistoryDelta(1),
                // 拖出屏幕：夹紧在屏幕内
                .start(at: desktop),
                .drag([corner, beyond]),
                .expectSelection("dragging past the screen edge is clamped", cornerRect),
                .key(.rightArrow, .shift),
                .expectSelection("nudging into the edge keeps it on screen", cornerRect),
                .drag([.handle(.left), .handle(.left, dx: 300)]),
                .expectSelection("the left handle cannot pass the fixed right edge") { context in
                    let rect = cornerRect(context)
                    return CGRect(x: rect.maxX - 4, y: rect.minY, width: 4, height: rect.height)
                },
                // 放大镜不可见时 C 无效；拖手柄时（放大镜可见）C 取色
                .letter("c"),
                .expectPresented,
                .command("a"),
                .markOutputs,
                .mouseDown(.handle(.left)),
                .mouseDrag(.handle(.left, dx: 300)),
                .expect("magnifier shows while dragging a handle") { try $0.requireSession().isMagnifierVisible },
                .letter("c"),
                .expectIdle,
                .expect("C while dragging a handle picks a color") { context in
                    context.world.results.last?.hasPrefix("copyColor(#") == true
                },
                .mouseUp(.at(300, 540)),
                .eventually("the color is on the pasteboard") { $0.world.pasteboardText?.hasPrefix("#") == true },
            ]
        )
    }

    static var extractNoText: E2EScenario {
        E2EScenario(
            name: "ocr-empty",
            summary: "cmd-T on a region without text warns and copies nothing",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([.at(1210, 305), .at(1390, 395)]),
                .command("t"),
                .expectIdle,
                .expectEqual("result is extractText", "extractText") { $0.world.results.last },
                .expectHUD(containing: E2EText.localized("No text found"), timeout: .seconds(20)),
                .expectPasteboardUnchanged,
                .expectHistoryDelta(0, settle: .milliseconds(200)),
            ]
        )
    }
}
#endif

#if DEBUG
/// 其他规格条目：菜单栏 / 程序坞算整屏、⌘C 截悬停目标、窗口模式的退出、移动选区、贴图的 Esc / ⌘W
extension E2EScenarios {
    static var miscellaneous: E2EScenario {
        let pinCenter = E2EPoint.computed { context in
            guard let window = context.world.pinWindows.first else { throw E2EScriptError.unavailable("pin window") }
            return ScreenTopologyProvider.toGlobal(CGPoint(x: window.frame.midX, y: window.frame.midY))
        }
        return E2EScenario(
            name: "misc",
            summary: "menu bar is not a window target, cmd-C in hovering, leaving window mode, moving, pin Esc / cmd-W",
            steps: [
                .start(at: desktop),
                .move(.at(1500, 10)),
                .expectDepth(0, window: nil),
                .move(overlap),
                .spaceDown, .spaceUp,
                .expect("window mode on") { try $0.requireSession().isWindowCaptureMode },
                .key(.tab), .key(.tab), .key(.tab),
                .expectDepth(3, window: nil),
                .expect("reaching the whole screen leaves window mode") {
                    !(try $0.requireSession().isWindowCaptureMode)
                },
                .key(.tab, .shift),
                .spaceDown, .spaceUp,
                .expect("window mode on again") { try $0.requireSession().isWindowCaptureMode },
                .key(.escape),
                .expectIdle,
                .expectEqual("Esc in window mode cancels", "cancel") { $0.world.results.last },
                .markOutputs,
                .start(at: desktop),
                .move(editorOnly),
                .command("c"),
                .expectIdle,
                .expectPNG("cmd-C in hovering copies the hover target") {
                    $0.pixelSize(of: $0.globalRect(editorFrame))
                },
                // 选区内拖动：移动选区，标注留在原处
                .start(at: desktop),
                .drag([.at(1100, 200), .at(1400, 400)]),
                .letter("r"),
                .drag([.at(1150, 250), .at(1200, 300)]),
                .letter("v"),
                .remember("rectangle") { context in context.annotations["rect"] = try context.lastAnnotation() },
                .drag([.at(1300, 350), .at(1350, 380)]),
                .expectSelection("dragging inside moves the selection") {
                    $0.globalRect(CGRect(x: 1150, y: 230, width: 300, height: 200))
                },
                .expectEqual("annotations stay in place", { $0.annotations["rect"]?.shape }) {
                    try $0.lastAnnotation().shape
                },
                .command("p"),
                .expectIdle,
                .eventually("pinned") { $0.world.pinWindows.count == 1 },
                .click(pinCenter),
                .key(.escape),
                .eventually("Esc closes the pin") { $0.world.pinWindows.isEmpty },
                .start(at: desktop),
                .drag([.at(1100, 200), .at(1400, 400)]),
                .command("p"),
                .expectIdle,
                .eventually("pinned again") { $0.world.pinWindows.count == 1 },
                .click(pinCenter),
                .command("w"),
                .eventually("cmd-W closes the pin") { $0.world.pinWindows.isEmpty },
            ]
        )
    }
}
#endif

#if DEBUG
/// 导出相关：双击窗口、右键清选区后重新框选（标注按屏幕坐标保留）、编辑中右键、马赛克
extension E2EScenarios {
    static var annotationExport: E2EScenario {
        let checker = { (dx: CGFloat, dy: CGFloat) in
            E2EPoint.computed { context in
                let frame = context.world.screen.frame
                return CGPoint(x: frame.maxX + dx, y: frame.maxY + dy)
            }
        }
        return E2EScenario(
            name: "annotation-export",
            summary: "double-click a window, reselect keeps annotations, right-click while editing, mosaic export",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .click(editorOnly, count: 2),
                .expectIdle,
                .expectPNG("double-clicking a window copies it") { $0.pixelSize(of: $0.globalRect(editorFrame)) },
            ] + selectCanvas + drawRectangle + [
                .rightClick(.at(1500, 500)),
                .expectPhase(.hovering),
                .drag([.at(1060, 160), .at(1300, 340)]),
                .expectPhase(.adjusting),
                .expect("annotations survive reselecting") { try $0.requireSession().document.annotations.count == 1 },
                .key(.returnKey),
                .expectIdle,
                .expectPNG("PNG is the new selection") {
                    $0.pixelSize(of: $0.globalRect(CGRect(x: 1060, y: 160, width: 240, height: 180)))
                },
                .expectPixel("the kept rectangle is exported", at: .at(1100, 250), near: AnnotationColor.red.rgba),
            ] + selectCanvas + [
                .letter("t"),
                .click(.at(1500, 400)),
                .type("Hi"),
                .rightClick(.at(1600, 500)),
                .expectPhase(.hovering),
                .expect("right-click while editing commits the text first") { context in
                    guard case .text(let text, _, _) = try context.lastAnnotation().shape else { return false }
                    return text == "Hi"
                },
                .key(.escape),
                .key(.escape),
                .expectIdle,
                // 棋盘格（8 pt 黑白格）上的马赛克：导出后是块平均的灰，不再是纯黑或纯白
                .start(at: desktop),
                .drag([checker(-310, -260), checker(-50, -80)]),
                .letter("m"),
                .drag([checker(-280, -170), checker(-100, -170)]),
                .key(.returnKey),
                .expectIdle,
                .expectPixel("mosaic averages the checkerboard", at: checker(-190, -170)) { color in
                    (0.2...0.85).contains(color.red) && abs(color.red - color.green) < 0.05
                        && abs(color.red - color.blue) < 0.05
                },
                .expectPixel("outside the mosaic the checkerboard is intact", at: checker(-290, -245)) { color in
                    color.red < 0.2 || color.red > 0.85
                },
            ]
        )
    }
}
#endif
