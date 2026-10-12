#if DEBUG
import AppKit

/// 演示动图里的假指针：Cubby 自己的一个小窗口，画系统箭头与按下时的光圈。
/// 只改窗口位置，不移动真实指针、不产生任何事件；移动过程中把每一帧的位置交给 onMove（例如喂给晾衣绳的轮询）
@MainActor
final class DemoCursor {
    /// 窗口边长（点）：箭头之外留出光圈的空间
    private static let size: CGFloat = 56
    private static let frameInterval: Double = 1.0 / 60

    private let window: NSWindow
    private let view = DemoCursorView()
    /// 箭头热点（AppKit 屏幕坐标，y 向上）
    private(set) var location: CGPoint
    private(set) var isPressed = false
    /// 每一帧的位置与是否按着
    var onMove: ((CGPoint, Bool) -> Void)?

    init(at location: CGPoint) {
        self.location = location
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: Self.size, height: Self.size), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = view
        place()
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func show() {
        window.orderFrontRegardless()
    }

    /// 缓入缓出地移到 target（AppKit 屏幕坐标）
    func move(to target: CGPoint, duration: Double) async {
        let start = location
        let steps = max(Int(duration / Self.frameInterval), 1)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            location = CGPoint(
                x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            place()
            onMove?(location, isPressed)
            await DemoClock.pause(Self.frameInterval)
        }
    }

    func press() {
        isPressed = true
        view.isPressed = true
        onMove?(location, true)
    }

    func release() {
        isPressed = false
        view.isPressed = false
        onMove?(location, false)
    }

    /// 单击：按下停一下再松开
    func click() async {
        press()
        await DemoClock.pause(0.12)
        release()
    }

    private func place() {
        // 热点在窗口中心
        window.setFrameOrigin(CGPoint(x: location.x - Self.size / 2, y: location.y - Self.size / 2))
    }
}

/// 箭头（系统光标图像）+ 按下时的半透明光圈
private final class DemoCursorView: NSView {
    var isPressed = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if isPressed {
            let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32))
            NSColor.systemYellow.withAlphaComponent(0.35).setFill()
            ring.fill()
            NSColor.systemYellow.withAlphaComponent(0.8).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
        let cursor = NSCursor.arrow
        let image = cursor.image
        // 热点（图像坐标，左上原点）对准窗口中心
        let origin = CGPoint(
            x: center.x - cursor.hotSpot.x, y: center.y - (image.size.height - cursor.hotSpot.y))
        image.draw(in: CGRect(origin: origin, size: image.size))
    }
}
#endif
