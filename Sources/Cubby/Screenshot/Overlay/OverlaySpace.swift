import AppKit
import CubbyCore

// 覆盖层坐标换算 `OverlaySpace` 已下沉到 CubbyCore（Layout/OverlaySpace.swift，有单元测试）。

/// AppKit ↔ 全局点：统一走 `ScreenTopologyProvider`（App 层唯一的换算点，§3.2）
@MainActor
enum OverlayScreens {
    static func appKitRect(_ global: CGRect) -> CGRect {
        ScreenTopologyProvider.toAppKit(global)
    }

    /// 当前鼠标位置（全局点）
    static var mouseLocation: CGPoint {
        ScreenTopologyProvider.toGlobal(NSEvent.mouseLocation)
    }

    static func nsScreen(for screen: CaptureScreen) -> NSScreen? {
        ScreenTopologyProvider.nsScreen(for: screen)
    }
}
