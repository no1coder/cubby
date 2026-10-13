import AppKit
import CubbyCore

/// 打开条目：链接用浏览器、文件用默认应用、图片用预览（图片先解密成临时副本，见 SharedFiles，E9）
@MainActor
enum ItemOpener {
    /// 仅允许打开 http/https 链接，防止被篡改的历史文件借助自定义 scheme 执行动作
    private static let allowedSchemes: Set<String> = ["http", "https"]

    /// 返回是否成功打开
    @discardableResult
    /// - Parameter imageFile: 图片条目才调用：生成交给预览的临时副本
    static func open(_ item: ClipItem, imageFile: () -> URL?) -> Bool {
        switch item.payload {
        case .text(let text):
            guard item.kind == .link, let url = safeWebURL(text) else { return false }
            return NSWorkspace.shared.open(url)
        case .image:
            guard let file = imageFile() else { return false }
            return NSWorkspace.shared.open(file)
        case .files(let paths):
            let urls = paths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }
            urls.forEach { _ = NSWorkspace.shared.open($0) }
            return true
        }
    }

    static func safeWebURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            allowedSchemes.contains(scheme),
            url.host?.isEmpty == false
        else { return nil }
        return url
    }

    static func revealInFinder(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
