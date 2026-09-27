#if DEBUG
import AppKit
import CubbyCore

/// 步骤工厂：脚本以声明式的数组写成，例如 `[.start(at: .at(400, 450)), .click(.at(400, 450)), .key(.returnKey)]`
extension E2EStep {
    static func action(_ title: String, _ body: @escaping @MainActor (E2EContext) async throws -> Void) -> E2EStep {
        E2EStep(title: title, kind: .action, body: body)
    }

    // MARK: - 会话

    /// 开始一次截图会话（合成桌面），光标在 point；等覆盖层上屏
    static func start(at point: E2EPoint) -> E2EStep {
        action("start session") { context in
            let cursor = try point.resolve(context)
            context.world.start(cursor: cursor)
            try await waitForOverlay(context)
            try await primeMouseTracking(context, near: cursor)
        }
    }

    /// 开始采集但不等覆盖层（用于「采集中再按快捷键」）
    static func startWithoutWaiting(at point: E2EPoint) -> E2EStep {
        action("start session (not waiting)") { context in context.world.start(cursor: try point.resolve(context)) }
    }

    /// 会话进行中再按截图快捷键（协调器空闲时不会调用，避免触发真实采集与权限申请）
    static var hotKeyAgain: E2EStep {
        action("press the screenshot shortcut again") { context in
            guard context.world.isActive, let coordinator = context.world.coordinator else {
                throw E2EScriptError.unavailable("an active session")
            }
            coordinator.start(.hotKey)
            try await context.driver.flush()
        }
    }

    // MARK: - 鼠标

    static func move(_ point: E2EPoint) -> E2EStep {
        action("move") { context in try await context.driver.move(to: point.resolve(context)) }
    }

    static func click(_ point: E2EPoint, count: Int = 1) -> E2EStep {
        action(count == 2 ? "double-click" : "click") { context in
            let target = try point.resolve(context)
            try await context.driver.move(to: target)
            try await context.driver.click(at: target, count: count)
        }
    }

    /// 分步拖拽：按下、拖到、松开（中间可以插入按键）
    static func mouseDown(_ point: E2EPoint) -> E2EStep {
        action("mouse down") { context in
            let target = try point.resolve(context)
            try await context.driver.move(to: target)
            try await context.driver.mouseDown(at: target)
        }
    }

    static func mouseDrag(_ point: E2EPoint) -> E2EStep {
        action("mouse drag") { context in try await context.driver.mouseDragged(to: point.resolve(context)) }
    }

    static func mouseUp(_ point: E2EPoint) -> E2EStep {
        action("mouse up") { context in try await context.driver.mouseUp(at: point.resolve(context)) }
    }

    /// 点击工具栏按钮（位置按工具栏布局计算，点击经窗口派发到 SwiftUI 按钮）
    static func clickToolbar(_ item: E2EToolbarItem) -> E2EStep {
        action("click toolbar \(item)") { context in
            let hasTranslate = context.session?.isTranslationAvailable ?? false
            guard let frame = context.world.overlay?.debugScreenViews.compactMap(\.debugToolbarFrame).first,
                let center = E2EInspect.toolbarCenter(of: item, toolbar: frame, hasTranslate: hasTranslate)
            else { throw E2EScriptError.unavailable("toolbar") }
            try await context.driver.move(to: center)
            try await context.driver.click(at: center)
        }
    }

    static func rightClick(_ point: E2EPoint) -> E2EStep {
        action("right-click") { context in try await context.driver.rightClick(at: point.resolve(context)) }
    }

    /// 按下 → 依次拖过各点 → 松开；points 在按下前一次性解析（拖动过程中选区会变）
    static func drag(_ points: [E2EPoint]) -> E2EStep {
        action("drag") { context in
            let resolved = try points.map { try $0.resolve(context) }
            if let first = resolved.first {
                try await context.driver.move(to: first)
            }
            try await context.driver.drag(through: resolved)
        }
    }

    static func scroll(_ deltaY: Int32, precise: Bool, momentum: Bool = false, at point: E2EPoint) -> E2EStep {
        let device = precise ? "precise" : "line"
        return action("scroll \(deltaY) (\(device)\(momentum ? ", momentum" : ""))") { context in
            try await context.driver.scroll(
                deltaY: deltaY, precise: precise, momentum: momentum, at: point.resolve(context))
        }
    }

    // MARK: - 键盘

    static func key(_ key: E2EKey, _ flags: NSEvent.ModifierFlags = []) -> E2EStep {
        action("key \(Self.describe(flags))\(key)") { context in try await context.driver.press(key, flags: flags) }
    }

    /// ⌘ + 字母
    static func command(_ letter: Character, shift: Bool = false) -> E2EStep {
        let flags: NSEvent.ModifierFlags = shift ? [.command, .shift] : .command
        return key(.character(letter), flags)
    }

    /// 单字母工具键等
    static func letter(_ letter: Character) -> E2EStep {
        key(.character(letter))
    }

    static func hold(_ flags: NSEvent.ModifierFlags) -> E2EStep {
        action("hold \(Self.describe(flags))") { context in try await context.driver.setModifiers(flags) }
    }

    static var releaseModifiers: E2EStep {
        action("release modifiers") { context in try await context.driver.setModifiers([]) }
    }

    static var spaceDown: E2EStep {
        action("space down") { context in try await context.driver.keyDown(.space) }
    }

    static var spaceUp: E2EStep {
        action("space up") { context in try await context.driver.keyUp(.space) }
    }

    static func type(_ text: String) -> E2EStep {
        action("type \"\(text)\"") { context in try await context.driver.type(text) }
    }

    /// 输入法组字（标记文本）
    static func compose(_ marked: String) -> E2EStep {
        action("compose \"\(marked)\"") { context in try await context.driver.setMarkedText(marked) }
    }

    /// 输入法提交
    static func commitComposition(_ text: String, label: String) -> E2EStep {
        action("commit composition \(label)") { context in try await context.driver.insertText(text) }
    }

    // MARK: - 界面

    /// 点击样式条上的色块（位置按样式条的布局计算，点击经窗口派发到 SwiftUI 按钮）
    static func clickColor(_ color: AnnotationColor) -> E2EStep {
        action("click color \(color.rawValue)") { context in
            guard let frame = context.world.overlay?.debugScreenViews.compactMap(\.debugStyleBarFrame).first,
                let center = E2EInspect.swatchCenter(color, styleBar: frame)
            else { throw E2EScriptError.unavailable("style bar") }
            try await context.driver.move(to: center)
            try await context.driver.click(at: center)
        }
    }

    static func wait(_ milliseconds: Int) -> E2EStep {
        action("wait \(milliseconds) ms") { _ in try? await Task.sleep(for: .milliseconds(milliseconds)) }
    }

    /// 记录当前值供后续步骤使用
    static func remember(_ title: String, _ body: @escaping @MainActor (E2EContext) throws -> Void) -> E2EStep {
        action("remember \(title)") { context in try body(context) }
    }

    // MARK: - 私有

    /// 等覆盖层上屏，且画布已装好跟踪区域（之前的 mouseMoved 不会派发到画布）
    @MainActor
    private static func waitForOverlay(_ context: E2EContext) async throws {
        let ready = await context.poll(timeout: .seconds(5)) {
            guard context.world.isOverlayPresented, let overlay = context.world.overlay else { return false }
            return overlay.debugScreenViews.allSatisfy { !$0.canvas.trackingAreas.isEmpty }
        }
        guard ready else { throw E2EScriptError.timedOut("the overlay") }
        try await context.driver.flush()
    }

    /// 新窗口的跟踪区域偶尔要过一会儿才认定光标在区域内，此前合成的 mouseMoved 不会派发到画布
    /// （真实鼠标由窗口服务器补发进入事件，不受影响）。在起点旁逐次移动 1 pt，直到会话跟上
    @MainActor
    private static func primeMouseTracking(_ context: E2EContext, near point: CGPoint) async throws {
        for attempt in 1...40 {
            let probe = CGPoint(x: point.x + CGFloat(attempt % 2 == 0 ? 0 : 1), y: point.y)
            try await context.driver.move(to: probe)
            if context.session?.cursor == probe {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        throw E2EScriptError.timedOut("mouse tracking on the overlay")
    }

    private static func describe(_ flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.shift) { text += "shift+" }
        if flags.contains(.option) { text += "option+" }
        if flags.contains(.command) { text += "cmd+" }
        return text
    }
}
#endif
