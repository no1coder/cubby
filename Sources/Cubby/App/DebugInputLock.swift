#if DEBUG
import AppKit

/// 仅调试构建：`--lock-input` 丢弃本应用收到的真实鼠标与键盘事件。拍 README 截图时场景不受误触影响
/// （例如在别的应用里打字时误按 ↩，把截图写进剪贴板）；场景自己的操作直接调用控制器，不经过事件。
/// 本地监听器按安装顺序调用，因此在启动时最先安装，早于面板与截图覆盖层的键盘监听
@MainActor
enum DebugInputLock {
    private static var monitor: Any?
    private static let lockedTypes: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
        .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel, .keyDown, .keyUp,
        .flagsChanged, .magnify, .swipe, .rotate, .gesture,
    ]

    static func installIfRequested() {
        guard CommandLine.arguments.contains("--lock-input"), monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: lockedTypes) { _ in nil }
    }
}
#endif
