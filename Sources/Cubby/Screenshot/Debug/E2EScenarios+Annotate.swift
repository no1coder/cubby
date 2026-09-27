#if DEBUG
import AppKit
import CubbyCore

/// 标注与文字脚本
extension E2EScenarios {
    static var annotate: E2EScenario {
        E2EScenario(
            name: "annotate",
            summary: "every tool draws once, undo / redo, select-drag-recolor-delete, colors land in the PNG",
            steps: [.markOutputs] + selectCanvas + [
                .expectEqual("adjusting starts with the pointer tool", ScreenshotTool.pointer) {
                    try $0.requireSession().tool
                }
            ]
                + draw(.rectangle, key: "r", [.at(1100, 200), .at(1250, 300)])
                + draw(.ellipse, key: "o", [.at(1300, 200), .at(1450, 300)])
                + draw(.arrow, key: "a", [.at(1500, 300), .at(1650, 200)])
                + draw(.pen, key: "p", [.at(1100, 400), .at(1150, 380), .at(1200, 420), .at(1250, 390)])
                + draw(.highlighter, key: "h", [.at(1300, 400), .at(1450, 400)])
                + draw(.mosaic, key: "m", [.at(1500, 380), .at(1650, 420)])
                + [
                    .letter("t"),
                    .click(.at(1100, 500)),
                    .expectPhase(.editingText),
                    .type("Hi"),
                    .key(.escape),
                    .expectPhase(.annotating),
                    .expectEqual("text annotation holds \"Hi\"", "Hi") { context in
                        guard case .text(let text, _, _) = try context.lastAnnotation().shape else { return nil }
                        return text
                    },
                ]
                + draw(.number, key: "n", click: .at(1400, 520))
                + undoRedoSteps + editSteps + exportSteps
        )
    }

    /// 选工具、画一个标注，检查它进入文档；记录到 context.annotations[tool]
    private static func draw(
        _ tool: ScreenshotTool, key: Character, _ path: [E2EPoint] = [], click: E2EPoint? = nil
    ) -> [E2EStep] {
        [
            .remember("annotation count") { context in
                context.numbers["count"] = try context.requireSession().document.annotations.count
            },
            .letter(key),
            .expectEqual("key \(key) selects \(tool)", tool) { try $0.requireSession().tool },
            click.map { .click($0) } ?? .drag(path),
            .expect("\(tool) annotation added") { context in
                let annotations = try context.requireSession().document.annotations
                return annotations.count == (context.numbers["count"] ?? 0) + 1 && annotations.last?.tool == tool
            },
            .remember("\(tool)") { context in context.annotations["\(tool)"] = try context.lastAnnotation() },
        ]
    }

    private static var undoRedoSteps: [E2EStep] {
        [
            .command("z"),
            .expectEqual("undo removes the number", 7) { try $0.requireSession().document.annotations.count },
            .command("z", shift: true),
            .expectEqual("redo restores it", 8) { try $0.requireSession().document.annotations.count },
        ]
    }

    /// 回到指针：单击选中矩形、拖动、改色；再选中椭圆并删除
    private static var editSteps: [E2EStep] {
        [
            .letter("v"),
            .expectPhase(.adjusting),
            .click(.at(1100, 250)),
            .expectEqual("clicking the rectangle's edge selects it", { $0.annotations["rectangle"]?.id }) {
                try $0.requireSession().selectedAnnotation
            },
            .drag([.at(1100, 250), .at(1130, 270)]),
            .expectEqual(
                "dragging moves the rectangle by (30, 20)",
                { context in
                    context.annotations["rectangle"]?.translated(by: CGVector(dx: 30, dy: 20)).shape
                }
            ) { context in
                try context.requireSession().document.annotations.first { $0.tool == .rectangle }?.shape
            },
            .clickColor(.blue),
            .expectEqual("the style bar recolors the selected rectangle", AnnotationColor.blue) { context in
                try context.requireSession().document.annotations.first { $0.tool == .rectangle }?.style.color
            },
            .click(.at(1300, 250)),
            .expectEqual("clicking the ellipse's edge selects it", { $0.annotations["ellipse"]?.id }) {
                try $0.requireSession().selectedAnnotation
            },
            .key(.delete),
            .expect("Delete removes the ellipse") { context in
                let document = try context.requireSession().document
                return document.annotations.count == 7 && !document.annotations.contains { $0.tool == .ellipse }
            },
        ]
    }

    /// 完成后在 PNG 中采样：标注颜色落在对应位置，删掉的椭圆不在
    private static var exportSteps: [E2EStep] {
        let red = AnnotationColor.red.rgba
        return [
            .key(.returnKey),
            .expectIdle,
            .expectPNG("PNG has the selection's pixel size") { $0.pixelSize(of: $0.globalRect(canvasRect)) },
            .expectPixel("moved rectangle edge is blue", at: .at(1130, 290), near: AnnotationColor.blue.rgba),
            .expectPixel("arrow shaft is red", at: .at(1575, 250), near: red),
            .expectPixel("pen stroke is red", at: .at(1150, 380), near: red),
            .expectPixel("number badge is red", at: .at(1392, 520), near: red),
            // 桌面底色偏蓝；荧光笔 multiply 之后蓝色明显低于红色（y 避开 400 的网格线）
            .expectPixel("highlighter tints the desktop yellow", at: .at(1375, 406)) { $0.blue < $0.red - 0.1 },
            .expectPixel("deleted ellipse left no red", at: .at(1300, 250)) { $0.distance(to: red) > 0.3 },
            .expectPixel("original rectangle position is clear", at: .at(1100, 250)) { $0.distance(to: red) > 0.3 },
            .expectHistoryDelta(1),
        ]
    }

    static let canvasRect = CGRect(x: 1050, y: 150, width: 900, height: 500)

    static var text: E2EScenario {
        // "你好"：输入法提交的文字（转义写法，源码中不出现汉字）
        let hanzi = "\u{4F60}\u{597D}"
        let origin = E2EPoint.at(1100, 300)
        return E2EScenario(
            name: "text",
            summary: "ASCII typing, pinyin composition passes keys to the IME, Esc commits, click re-edits",
            steps: selectCanvas + [
                .letter("t"),
                .click(origin),
                .expectPhase(.editingText),
                .expect("editor is focused") { context in
                    guard let editor = context.world.overlay?.debugEditor else { return false }
                    return editor.window?.firstResponder === editor.textView
                },
                .type("Hello"),
                .expectEqual("typed ASCII reaches the session", "Hello") { try $0.requireSession().textEditing?.text },
                // 编辑类 ⌘ 组合交给文本视图（⌘C / ⌘X / ⌘V 会碰系统剪贴板，这里不测）
                .command("a"),
                .type("Hey"),
                .expectEqual("cmd-A selects all, typing replaces it", "Hey") {
                    try $0.requireSession().textEditing?.text
                },
                .command("z"),
                .expectEqual("cmd-Z undoes inside the editor", "Hello") { try $0.requireSession().textEditing?.text },
                // 撤销后 "Hello" 处于选中状态：→ 把插入点移到末尾（方向键在编辑时交给文本视图）
                .key(.rightArrow),
                // 其余 ⌘ 组合（⌘Q、⌘W）不能落到 Cubby 的菜单上
                .command("q"),
                .command("w"),
                .expectPresented,
                .expectPhase(.editingText),
                .compose("nihao"),
                .expect("editor reports marked text") { $0.world.overlay?.debugEditor?.hasMarkedText == true },
                // 组字中按 Esc：交给输入法，不提交文字
                .key(.escape),
                .expectPhase(.editingText),
                .expect("Esc while composing does not commit") { !(try $0.requireSession().hasAnnotations) },
                .compose("nihao"),
                .commitComposition(hanzi, label: "ni hao"),
                .expect("composition committed, no marked text") {
                    $0.world.overlay?.debugEditor?.hasMarkedText == false
                },
                .expectEqual("session text includes the committed Hanzi", "Hello" + hanzi) {
                    try $0.requireSession().textEditing?.text
                },
                .key(.escape),
                .expectPhase(.annotating),
                .expectEqual("Esc commits the text annotation", "Hello" + hanzi) { context in
                    guard case .text(let text, _, _) = try context.lastAnnotation().shape else { return nil }
                    return text
                },
                .remember("text annotation") { context in context.annotations["text"] = try context.lastAnnotation() },
                // 文字工具单击已有文字：重新编辑
                .click(.at(1110, 310)),
                .expectPhase(.editingText),
                .expectEqual("clicking the text re-opens it", { $0.annotations["text"]?.id }) {
                    try $0.requireSession().textEditing?.existing
                },
                .expectEqual("editor shows the existing text", "Hello" + hanzi) {
                    $0.world.overlay?.debugEditor?.textView.string
                },
                .type("!"),
                .key(.returnKey, .command),
                .expectPhase(.annotating),
                .expect("re-edit replaces the text in place") { context in
                    let annotations = try context.requireSession().document.annotations
                    guard annotations.count == 1, let annotation = annotations.first,
                        case .text(let text, _, _) = annotation.shape
                    else { return false }
                    return annotation.id == context.annotations["text"]?.id && text == "Hello" + hanzi + "!"
                },
                .key(.escape),
                .expect("first Esc with annotations only arms discard") { try $0.requireSession().isDiscardArmed },
                .key(.escape),
                .expectIdle,
            ]
        )
    }
}

extension E2EStep {
    /// 在剪贴板 PNG 中采样全局点 point 处的颜色（按最终选区换算到像素）
    static func expectPixel(
        _ title: String, at point: E2EPoint, _ predicate: @escaping @MainActor (RGBAColor) -> Bool
    ) -> E2EStep {
        E2EStep(title: title, kind: .check) { context in
            do {
                let color = try context.pixel(at: point.resolve(context))
                context.record(title, predicate(color), detail: "got \(color.hexDescription)")
            } catch {
                context.record(title, false, detail: "\(error)")
            }
        }
    }

    static func expectPixel(_ title: String, at point: E2EPoint, near expected: RGBAColor) -> E2EStep {
        expectPixel("\(title) (\(expected.hexDescription))", at: point) { $0.distance(to: expected) < 0.16 }
    }
}

extension E2EContext {
    /// 剪贴板 PNG 中对应全局点的像素
    func pixel(at point: CGPoint) throws -> RGBAColor {
        guard let image = pasteboardImage else { throw E2EScriptError.unavailable("pasteboard PNG") }
        let pixels = world.screen.pixelRect(try requireSelection())
        let local = world.screen.localPoint(point)
        let x = Int((local.x * scale).rounded(.down) - pixels.minX)
        let y = Int((local.y * scale).rounded(.down) - pixels.minY)
        guard let color = image.color(x: x, y: y) else { throw E2EScriptError.unavailable("pixel (\(x), \(y))") }
        return color
    }
}
#endif
