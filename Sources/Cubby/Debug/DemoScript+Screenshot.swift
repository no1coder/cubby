#if DEBUG
import AppKit
import CubbyCore

/// `demo:screenshot`：合成桌面（ShowcaseFrameSource，不截屏）上拖出选区 → 矩形 → 箭头 → 文字 → ↩ 复制。
/// 所有操作都是交给覆盖层 reducer 的事件；文字经编辑器的 NSTextView 插入（与输入法提交同一路径），
/// 输出写到私有剪贴板（DemoPasteboard），只写入临时数据目录里的历史
extension AppDelegate {
    func runScreenshotDemo() async {
        guard let screenshots, let screen = NSScreen.main,
            let captureScreen = ScreenTopologyProvider.captureScreen(for: screen)
        else { return }
        let layout = ShowcaseLayout(screen: captureScreen)
        let copy = ShowcaseCopy.current
        let selection = layout.selection
        let cursor = DemoCursor(at: DemoWindows.appKitPoint(CGPoint(x: selection.midX + 60, y: selection.maxY + 80)))
        let caption = DemoKeyCaption(
            center: DemoWindows.appKitPoint(CGPoint(x: selection.midX, y: selection.maxY + 112)))
        caption.show(HotKey.screenshotDefault.displayName, "Screenshot")
        guard let overlay = await screenshots.startDemoSession() else { return }
        let driver = DemoOverlayDriver(overlay: overlay, cursor: cursor)
        await DemoClock.pause(0.6)
        // 拖出选区
        await driver.drag(
            from: CGPoint(x: selection.minX, y: selection.minY), to: CGPoint(x: selection.maxX, y: selection.maxY))
        await DemoClock.pause(0.6)
        // 矩形框住「现在」气温卡
        caption.show("R", "Rectangle")
        overlay.send(.command(.selectTool(.rectangle)))
        overlay.send(.command(.selectColor(.orange)))
        let tile = layout.tile(0).insetBy(dx: -6, dy: -6)
        await driver.drag(from: tile.origin, to: CGPoint(x: tile.maxX, y: tile.maxY))
        await DemoClock.pause(0.5)
        // 文字标注
        caption.show("T", "Text")
        overlay.send(.command(.selectTool(.text)))
        overlay.send(.command(.selectColor(.red)))
        overlay.send(.command(.adjustWeight(heavier: true)))
        let origin = layout.calloutOrigin
        await driver.click(at: origin)
        await driver.type(copy.callout)
        overlay.send(.textCommitted(copy.callout))
        await DemoClock.pause(0.4)
        // 箭头从文字指向最高的柱子
        caption.show("A", "Arrow")
        overlay.send(.command(.selectTool(.arrow)))
        let fontSize = ScreenshotTool.text.fontSize(for: .heavy)
        let textSize = TextLayout.size(of: copy.callout, fontSize: fontSize, maxWidth: .infinity)
        let tail = CGPoint(x: origin.x + textSize.width + 8, y: origin.y + textSize.height * 0.55)
        let bar = layout.barRect(layout.lastBarIndex)
        await driver.drag(from: tail, to: CGPoint(x: bar.minX - 5, y: bar.minY + 3))
        await DemoClock.pause(0.8)
        caption.show("\u{21A9}", "Copy", for: 1.6)
        await DemoClock.pause(0.3)
        overlay.send(.command(.confirm))
        cursor.hide()
        await DemoClock.pause(2.2)
    }
}

/// 假指针 + 覆盖层事件：指针怎么动，事件就怎么发（坐标为屏幕左上原点）
@MainActor
private struct DemoOverlayDriver {
    let overlay: ScreenshotOverlayController
    let cursor: DemoCursor

    func move(to point: CGPoint, duration: Double = 0.5) async {
        cursor.onMove = { [overlay] location, pressed in
            let global = DemoWindows.topLeftPoint(location)
            overlay.send(pressed ? .mouseDragged(global) : .mouseMoved(global))
        }
        await cursor.move(to: DemoWindows.appKitPoint(point), duration: duration)
        cursor.onMove = nil
    }

    func drag(from start: CGPoint, to end: CGPoint) async {
        await move(to: start)
        await DemoClock.pause(0.15)
        overlay.send(.mouseDown(start, clickCount: 1))
        cursor.press()
        await move(to: end, duration: 0.8)
        overlay.send(.mouseUp(end))
        cursor.release()
    }

    func click(at point: CGPoint) async {
        await move(to: point)
        cursor.press()
        overlay.send(.mouseDown(point, clickCount: 1))
        overlay.send(.mouseUp(point))
        await DemoClock.pause(0.12)
        cursor.release()
    }

    /// 逐字插入编辑器（触发编辑器的 textChanged）
    func type(_ text: String) async {
        for character in text {
            overlay.editor?.textView.insertText(
                String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            await DemoClock.pause(0.07)
        }
    }
}

extension ScreenshotCoordinator {
    /// 演示：合成桌面 + 空白会话（指针在选区左上角之外），上屏后返回覆盖层
    func startDemoSession() async -> ScreenshotOverlayController? {
        await withCheckedContinuation { continuation in
            let source = ShowcaseFrameSource(screens: ScreenTopologyProvider.screens(), copy: .current)
            var resumed = false
            debugAfterPresent = { overlay in
                resumed = true
                continuation.resume(returning: overlay as? ScreenshotOverlayController)
            }
            begin(frameSource: source, windowSource: source) { capture in
                guard let screen = capture.topology.screens.first else { return nil }
                let selection = ShowcaseLayout(screen: screen).selection
                let cursor = CGPoint(x: selection.midX + 60, y: selection.maxY + 80)
                return ScreenshotSession.initial(styles: .default, cursor: cursor, topology: capture.topology)
            }
            if case .idle = state, !resumed {
                continuation.resume(returning: nil)
            }
        }
    }
}
#endif
