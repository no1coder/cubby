#if DEBUG
import AppKit

/// README 动图的演示脚本（`--scenario demo:<名称>`，仅调试构建，须与 --demo-history、--backdrop 搭配）：
/// 按时间轴直接设置面板、晾衣绳、截图覆盖层与地址守护的状态，不合成任何系统输入、不移动真实指针；
/// 画面里的指针是 DemoCursor 画的假指针。剪贴板写入一律落在私有的命名剪贴板（DemoPasteboard），不碰用户的剪贴板
enum DemoScenario: String {
    case searchPaste = "demo:search-paste"
    case clothesline = "demo:clothesline"
    case screenshot = "demo:screenshot"
    case addressGuard = "demo:address-guard"

    static let prefix = "demo:"

    /// 当前启动参数里的演示脚本
    static var requested: DemoScenario? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--scenario"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return DemoScenario(rawValue: arguments[index + 1])
    }

    /// 开场前的空白时长：录制工具先开始录，再看到第一个动作
    static let leadIn: Double = 2.0
}

/// 演示用的私有剪贴板：面板粘贴与截图输出都写到这里，系统剪贴板保持不变
@MainActor
enum DemoPasteboard {
    static let shared = NSPasteboard(name: NSPasteboard.Name("io.github.no1coder.Cubby.demo"))

    /// 演示脚本运行时用私有剪贴板，否则用系统剪贴板
    static var output: NSPasteboard {
        DemoScenario.requested == nil ? .general : shared
    }
}

/// 演示时间轴的小工具
enum DemoClock {
    /// 等待若干秒（被取消时立即返回）
    static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}

extension AppDelegate {
    /// 运行演示脚本：各脚本见 DemoScript+*.swift
    func runDemo(_ demo: DemoScenario) {
        Task { @MainActor in
            await DemoClock.pause(DemoScenario.leadIn)
            switch demo {
            case .searchPaste: await runSearchPasteDemo()
            case .clothesline: await runClotheslineDemo()
            case .screenshot: await runScreenshotDemo()
            case .addressGuard: await runAddressGuardDemo()
            }
            logger.notice("Demo finished: \(demo.rawValue, privacy: .public)")
        }
    }
}
#endif
