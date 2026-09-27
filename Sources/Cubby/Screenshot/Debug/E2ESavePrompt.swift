#if DEBUG
import AppKit
import CubbyCore

/// 端到端测试的「存储位置」桩：不弹出系统对话框，按脚本设定的回复返回；可保持「打开」以测试对话框期间的行为
@MainActor
final class E2ESavePrompt: SaveDestinationPrompting {
    enum Reply {
        /// 立即返回这个位置（相当于用户点「存储」）
        case url(URL)
        /// 立即取消
        case cancel
        /// 保持打开，直到脚本调用 resolve(_:)
        case hold
    }

    /// 一次存储请求的参数
    struct Request {
        let suggestedName: String
        let directory: URL
        let screen: NSScreen?
    }

    var reply = Reply.cancel
    private(set) var requests: [Request] = []
    private(set) var bringToFrontCount = 0
    private var pending: CheckedContinuation<URL?, Never>?

    /// 对话框（桩）正在等待回复
    var isOpen: Bool {
        pending != nil
    }

    func chooseDestination(suggestedName: String, directory: URL, screen: NSScreen?) async -> URL? {
        requests.append(Request(suggestedName: suggestedName, directory: directory, screen: screen))
        switch reply {
        case .url(let url): return url
        case .cancel: return nil
        case .hold:
            // 与正式实现一致：已有对话框打开时，这次请求视为取消（不覆盖尚未回复的 continuation）
            guard pending == nil else { return nil }
            return await withCheckedContinuation { pending = $0 }
        }
    }

    /// 结束保持打开的请求：url 为 nil 相当于用户点「取消」
    func resolve(_ url: URL?) {
        pending?.resume(returning: url)
        pending = nil
    }

    func bringToFront() {
        bringToFrontCount += 1
    }
}
#endif
