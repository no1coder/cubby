import AppKit
import os

/// Cubby 自己写剪贴板后的 changeCount（每个剪贴板最近几次）：地址守护只把「带写入标记且 changeCount 对得上」的变化
/// 当作自己的写入。别的程序伪造写入标记时 changeCount 对不上，按外部变化处理，绕不过守护
enum OwnPasteboardWrites {
    /// 每个剪贴板记住的次数：连续几次写入（例如粘贴后马上恢复）之间监听器可能只轮询到最后一次
    private static let capacity = 8
    private static let counts = OSAllocatedUnfairLock(initialState: [String: [Int]]())

    /// 写入（含写入标记）之后立即调用
    static func record(_ pasteboard: NSPasteboard) {
        let name = pasteboard.name.rawValue
        let count = pasteboard.changeCount
        counts.withLock { state in
            state[name] = Array(((state[name] ?? []) + [count]).suffix(capacity))
        }
    }

    static func contains(_ changeCount: Int, on pasteboard: NSPasteboard) -> Bool {
        let name = pasteboard.name.rawValue
        return counts.withLock { $0[name]?.contains(changeCount) == true }
    }
}
