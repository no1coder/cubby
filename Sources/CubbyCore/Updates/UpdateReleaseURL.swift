import Foundation

/// 发布页地址的白名单（docs/UPDATE-REMINDER-DESIGN.md U7）：只打开 https://github.com 上本仓库的发布页，
/// 其余（包括从偏好设置读回、可能被改过的值）一律回退到固定的发布页——被改写的设置不能把用户带去别人的下载
public enum UpdateReleaseURL {
    private static let allowedScheme = "https"
    private static let allowedHost = "github.com"
    /// 路径必须以这几段开头（不区分大小写，与 GitHub 一致）
    private static let releasesPathPrefix = ["no1coder", "cubby", "releases"]

    /// 固定的发布页
    public static let releasesPage: URL = {
        var components = URLComponents()
        components.scheme = allowedScheme
        components.host = allowedHost
        components.path = "/no1coder/cubby/releases"
        // 由常量拼出，实际不会失败（URLComponents 只在路径不合法时返回 nil）；这里只为免去强制解包
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    /// https、主机正好是 github.com、不带端口与用户信息，且路径在本仓库的发布页之下
    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == allowedScheme
            && url.host?.lowercased() == allowedHost
            && url.port == nil
            && url.user == nil
            && url.password == nil
            && isReleasesPath(url.path(percentEncoded: true))
    }

    /// 路径以 /no1coder/cubby/releases 开头；含「.」「..」段或百分号编码的一律拒绝
    /// （浏览器会把 %2e%2e 当作上一级，绕过前缀判断）
    private static func isReleasesPath(_ path: String) -> Bool {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        guard segments.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("%") }) else { return false }
        return segments.count >= releasesPathPrefix.count
            && zip(segments, releasesPathPrefix).allSatisfy { $0.lowercased() == $1 }
    }

    /// 白名单内的地址原样返回，否则（含 nil）返回固定的发布页
    public static func sanitized(_ url: URL?) -> URL {
        guard let url, isAllowed(url) else { return releasesPage }
        return url
    }
}
