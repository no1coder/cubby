#if DEBUG
import AppKit
import Darwin

/// 合成滚轮事件：NSEvent 没有构造滚轮事件的公开接口，只能先建 CGEvent 再转换。
///
/// 转换出的 NSEvent 默认没有窗口（postEvent 后不会派发到任何视图），因此写入两项未公开的信息，
/// 仅用于调试构建的端到端测试：
/// - CGEvent 字段 51：事件所属的窗口号（实测 `NSEvent(cgEvent:)` 由它得到 `window`）；
/// - `CGEventSetWindowLocation`：窗口内位置（左上原点），对应 `locationInWindow`。
/// 任何一项失效时返回 nil，脚本以「无法构造滚轮事件」失败，而不是静默跳过。
@MainActor
enum E2EScrollEvent {
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void

    private static let windowNumberField = CGEventField(rawValue: 51)
    /// kCGMomentumScrollPhaseContinue
    private static let momentumContinue: Int64 = 2

    static func make(
        deltaY: Int32,
        precise: Bool,
        momentum: Bool,
        at point: CGPoint,
        in window: NSWindow,
        flags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> NSEvent? {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1, wheel1: deltaY,
                wheel2: 0, wheel3: 0),
            let windowField = windowNumberField, let setWindowLocation
        else { return nil }
        // CG 全局坐标与全局点同为主屏左上原点、y 向下
        event.location = point
        event.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
        event.timestamp = CGEventTimestamp(timestamp * 1_000_000_000)
        if momentum {
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumContinue)
        }
        event.setIntegerValueField(windowField, value: Int64(window.windowNumber))
        let local = window.convertPoint(fromScreen: ScreenTopologyProvider.toAppKit(point))
        setWindowLocation(event, CGPoint(x: local.x, y: window.frame.height - local.y))
        guard let converted = NSEvent(cgEvent: event), converted.window === window,
            converted.hasPreciseScrollingDeltas == precise
        else { return nil }
        return converted
    }

    private static var setWindowLocation: SetWindowLocation? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGEventSetWindowLocation") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetWindowLocation.self)
    }
}
#endif
