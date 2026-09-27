import AppKit
import CubbyCore

/// 粘贴方式
enum PasteMode {
    /// ↩ 按默认格式粘贴
    case standard
    /// ⇧↩ 以另一种格式粘贴
    case alternate
    /// ⌘↩ 仅复制
    case copyOnly
}

/// 粘贴目标应用（面板呼出前的前台应用）
struct PasteTarget: Equatable {
    let name: String
    let bundleID: String?
    let processID: pid_t

    /// 当前前台应用；前台是本应用自身时返回 nil
    @MainActor
    static func current() -> PasteTarget? {
        #if DEBUG
        if let override = debugOverride { return override }
        #endif
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return PasteTarget(
            name: app.localizedName ?? String(localized: "Current App", comment: "Paste target whose name is unknown"),
            bundleID: app.bundleIdentifier,
            processID: app.processIdentifier
        )
    }

    #if DEBUG
    /// 调试 / 截图：`--paste-target <bundleID>` 固定底栏显示的粘贴目标（只用于显示，不参与真实粘贴）
    @MainActor
    private static var debugOverride: PasteTarget? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--paste-target"), arguments.indices.contains(index + 1),
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: arguments[index + 1])
        else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return PasteTarget(name: name, bundleID: arguments[index + 1], processID: 0)
    }
    #endif
}

/// 面板内的轻提示
struct PanelToast: Equatable, Identifiable {
    enum Action: Equatable {
        case undoDelete
    }

    let id = UUID()
    let message: String
    let symbolName: String
    let action: Action?

    static func deleted() -> PanelToast {
        PanelToast(
            message: String(localized: "Deleted", comment: "Toast after deleting an item"),
            symbolName: "trash",
            action: .undoDelete
        )
    }

    static func error(_ message: String) -> PanelToast {
        PanelToast(message: message, symbolName: "exclamationmark.triangle.fill", action: nil)
    }

    /// 普通说明（如「此类内容不支持翻译」「已复制译文」）
    static func info(_ message: String, symbolName: String) -> PanelToast {
        PanelToast(message: message, symbolName: symbolName, action: nil)
    }
}
