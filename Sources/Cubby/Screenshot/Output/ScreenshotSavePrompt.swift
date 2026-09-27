import AppKit
import CubbyCore
import UniformTypeIdentifiers
import os

/// 「选择存储位置」：截图的 ⌘S / 工具栏「存储」与贴图的「存储…」共用（设计文档 §9.4）。
/// 抽成协议以便端到端测试换成桩实现，不弹出真实的系统对话框
@MainActor
protocol SaveDestinationPrompting: AnyObject {
    /// 让用户选择存储位置与文件名；取消返回 nil。screen：对话框出现在这块屏幕上（nil 时由系统决定）
    func chooseDestination(suggestedName: String, directory: URL, screen: NSScreen?) async -> URL?
    /// 对话框打开时把它提到最前（例如对话框被其他窗口挡住后，用户再按截图快捷键）
    func bringToFront()
}

/// 正式实现：NSSavePanel，只允许 PNG，可新建文件夹，文件名可改；同名文件的「替换」确认由系统对话框处理。
///
/// 用 `begin(completionHandler:)` 而不是 `runModal()`：剪贴板监听的计时器不挂在 modalPanel 模式上，
/// 模态运行期间监听会暂停。Cubby 是 accessory 应用，先激活自己对话框才能成为 key；
/// 焦点还给截图前的前台应用由调用方负责（截图会话结束时）。
@MainActor
final class ScreenshotSavePrompt: SaveDestinationPrompting {
    /// 全应用共用一个：截图与贴图不会同时弹出两个存储对话框
    static let shared = ScreenshotSavePrompt()

    private var panel: NSSavePanel?
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")

    func chooseDestination(suggestedName: String, directory: URL, screen: NSScreen?) async -> URL? {
        // 已有对话框打开（例如贴图的存储还没结束）：把它提到前面，这次请求视为取消
        guard panel == nil else {
            logger.notice("Save dialog already open, the new save request is treated as cancelled")
            bringToFront()
            return nil
        }
        let panel = Self.makePanel(suggestedName: suggestedName, directory: directory)
        self.panel = panel
        defer { self.panel = nil }
        NSApp.activate()
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            Self.center(panel, on: screen)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func bringToFront() {
        guard let panel else { return }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// 仅调试构建：delay 后替用户点「取消」（走查场景 screenshot:save-dialog，不写任何文件）
    func debugCancel(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.panel?.cancel(nil)
        }
    }
    #endif

    // MARK: - 私有

    private static func makePanel(suggestedName: String, directory: URL) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = directory
        panel.nameFieldStringValue = suggestedName
        // 贴图是浮动层级：对话框放到模态面板层级，不会被贴图挡住
        panel.level = .modalPanel
        return panel
    }

    /// 放到指定屏幕可见区域的中央偏上（与系统居中对话框的位置一致）
    private static func center(_ panel: NSWindow, on screen: NSScreen?) {
        guard let screen, panel.screen != screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + (visible.height - size.height) * 2 / 3
        )
        panel.setFrameOrigin(origin)
    }
}

/// 存储对话框前后的焦点：对话框需要激活 Cubby（accessory 应用），结束后把前台还给截图前的应用，
/// 否则用户随后的 ⌘V 会落到 Cubby 上。只有 Cubby 原本不在前台时才归还
@MainActor
struct FocusRestorer {
    private let previous: NSRunningApplication?
    private let wasActive: Bool

    static func capture() -> FocusRestorer {
        let current = NSRunningApplication.current
        let frontmost = NSWorkspace.shared.frontmostApplication
        return FocusRestorer(
            previous: frontmost?.processIdentifier == current.processIdentifier ? nil : frontmost,
            wasActive: NSApp.isActive
        )
    }

    func restore() {
        guard !wasActive, NSApp.isActive, let previous, !previous.isTerminated else { return }
        NSApp.yieldActivation(to: previous)
        previous.activate(options: [])
    }
}

/// 把 PNG 写到存储对话框选定的位置（后台执行），成功后记住文件夹作为下次的起始目录
@MainActor
enum ScreenshotSaveWriter {
    /// 同名文件的「替换」已由存储对话框确认，这里直接覆盖
    static func write(_ png: Data, to url: URL, settings: AppSettings) async -> Result<
        URL, ScreenshotFileSaver.SaveError
    > {
        let result = await Task.detached(priority: .userInitiated) {
            Result { () throws(ScreenshotFileSaver.SaveError) in
                try ScreenshotFileSaver.write(png, to: url, overwrite: true)
            }
        }.value
        if case .success(let written) = result {
            settings.screenshotSaveDirectory = written.deletingLastPathComponent()
        }
        return result
    }

    /// 「已存储到 <文件夹名>」
    static func savedMessage(for url: URL) -> String {
        let folder = FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
        return String(localized: "Saved to \(folder)", comment: "HUD after saving a screenshot. %@ = folder name")
    }
}
