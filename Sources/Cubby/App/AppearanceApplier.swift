import AppKit
import CubbyCore

/// 把外观设置应用到整个应用：NSApp.appearance 作用于所有窗口（面板、预览、晾衣绳、设置、引导等）
@MainActor
enum AppearanceApplier {
    static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = (debugOverride ?? appearance).appearanceName.flatMap(NSAppearance.init(named:))
    }

    /// 截图走查：--light / --dark 强制外观，优先于设置（调试构建）
    private static var debugOverride: AppAppearance? {
        #if DEBUG
        let arguments = CommandLine.arguments
        if arguments.contains("--light") { return .light }
        if arguments.contains("--dark") { return .dark }
        #endif
        return nil
    }
}
