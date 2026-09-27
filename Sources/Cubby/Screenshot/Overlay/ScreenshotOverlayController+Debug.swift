#if DEBUG
import AppKit
import CubbyCore

/// 仅调试构建：端到端测试（--e2e）读取覆盖层内部状态的只读入口
extension ScreenshotOverlayController {
    var debugScreenViews: [OverlayScreenView] {
        screens.map(\.view)
    }

    var debugWindows: [NSWindow] {
        screens.map(\.window)
    }

    var debugEditor: TextAnnotationEditor? {
        editor
    }

    /// 覆盖层已隐藏（结束或导出中）
    var debugIsFinished: Bool {
        isFinished
    }
}
#endif
