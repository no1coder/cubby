import AppKit
import CubbyCore

/// NSEvent（鼠标）→ `ScreenshotEvent` 的翻译（§2.3）。光标种类由 Core 的 `ScreenshotSession.cursorKind` 决定
@MainActor
enum OverlayInteraction {
    /// 鼠标类事件的翻译；point 为全局点。不关心的事件返回 nil
    static func event(for event: NSEvent, at point: CGPoint) -> ScreenshotEvent? {
        switch event.type {
        case .mouseMoved:
            return .mouseMoved(point)
        case .leftMouseDown:
            return .mouseDown(point, clickCount: event.clickCount)
        case .leftMouseDragged:
            return .mouseDragged(point)
        case .leftMouseUp:
            return .mouseUp(point)
        case .rightMouseDown:
            return .rightMouseDown(point)
        case .scrollWheel:
            return scroll(event)
        default:
            return nil
        }
    }

    /// 触控板直接用 scrollingDeltaY 并跳过惯性阶段；行式滚轮每行换算（规则在 Core 的 `ScreenshotInput`）
    private static func scroll(_ event: NSEvent) -> ScreenshotEvent? {
        ScreenshotInput.scrollDelta(
            scrollingDeltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            isMomentum: !event.momentumPhase.isEmpty
        ).map { .scrolled(deltaY: $0) }
    }
}

/// 光标实例缓存：鼠标每次移动都会重设光标，避免反复创建（macOS 15 的 frameResize 每次返回新对象）
@MainActor
final class OverlayCursorCache {
    private var cursors: [ScreenshotCursorKind: NSCursor] = [:]

    func cursor(for kind: ScreenshotCursorKind) -> NSCursor {
        if let cached = cursors[kind] {
            return cached
        }
        let cursor = Self.make(kind)
        cursors[kind] = cursor
        return cursor
    }

    private static func make(_ kind: ScreenshotCursorKind) -> NSCursor {
        switch kind {
        case .crosshair: .crosshair
        case .arrow: .arrow
        case .iBeam: .iBeam
        case .move: OverlayCursors.move
        case .camera: OverlayCursors.camera
        case .resize(let handle): OverlayCursors.resize(handle)
        }
    }
}

/// 自定义与系统光标
@MainActor
enum OverlayCursors {
    /// 选区内 / 可拖动标注：四向移动（系统没有公开的移动光标，用 SF Symbol 绘制带白描边的版本）
    static let move =
        symbolCursor(
            "arrow.up.and.down.and.arrow.left.and.right", pointSize: OverlayTokens.moveCursorPointSize) ?? .openHand
    /// 纯净窗口模式：相机（与系统 ⇧⌘4 空格一致）
    static let camera = symbolCursor("camera.fill", pointSize: OverlayTokens.cameraCursorPointSize) ?? .pointingHand

    /// 手柄方向的缩放光标：macOS 15+ 用 frameResize，macOS 14 回退左右 / 上下（角用十字）
    static func resize(_ handle: SelectionHandle) -> NSCursor {
        if #available(macOS 15, *) {
            return .frameResize(position: position(for: handle), directions: .all)
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }

    @available(macOS 15, *)
    private static func position(for handle: SelectionHandle) -> NSCursor.FrameResizePosition {
        switch handle {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
    }

    /// 黑色符号 + 白色外描边（先在 8 个方向各画一次白色版本），热点在中心
    private static func symbolCursor(_ name: String, pointSize: CGFloat) -> NSCursor? {
        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard
            let black = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(base.applying(.init(paletteColors: [.black]))),
            let white = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(base.applying(.init(paletteColors: [.white])))
        else { return nil }
        let outline = OverlayTokens.cursorOutlineWidth
        let padding = OverlayTokens.cursorCanvasPadding
        let size = CGSize(
            width: black.size.width + outline * 2 + padding, height: black.size.height + outline * 2 + padding)
        let image = NSImage(size: size, flipped: false) { rect in
            let origin = CGPoint(x: (rect.width - black.size.width) / 2, y: (rect.height - black.size.height) / 2)
            let offsets: [(CGFloat, CGFloat)] = [
                (-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1),
            ]
            for (dx, dy) in offsets {
                let shifted = CGPoint(x: origin.x + dx * outline, y: origin.y + dy * outline)
                white.draw(in: CGRect(origin: shifted, size: white.size))
            }
            black.draw(in: CGRect(origin: origin, size: black.size))
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }
}
