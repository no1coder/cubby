import Foundation

/// 大模型接入地址的问题（设置界面据此给出提示）
public enum LLMBaseURLError: Error, Equatable, Sendable {
    /// 未填写
    case empty
    /// 不是有效的网址
    case malformed
    /// 只允许 https（本机 localhost / 127.0.0.1 / ::1 除外）
    case insecure
    /// 网址中不能包含用户名、密码、查询参数或片段
    case unsupportedComponents
}

/// 接入地址的校验与安全策略（docs/TRANSLATION-DESIGN.md §3.6「安全」）
public enum LLMBaseURL {
    /// 允许使用 http 的本机主机
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// 规范化并校验用户填写的地址：去掉首尾空白与末尾的 /；省略协议时补 https://
    public static func validate(_ text: String) -> Result<URL, LLMBaseURLError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else {
            return .failure(.empty)
        }
        var candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        while candidate.hasSuffix("/"), !candidate.hasSuffix("://") { candidate.removeLast() }
        guard let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(), let host = components.host, !host.isEmpty,
            let url = components.url
        else { return .failure(.malformed) }
        guard components.user == nil, components.password == nil, components.query == nil,
            components.fragment == nil
        else { return .failure(.unsupportedComponents) }
        switch scheme {
        case "https": return .success(url)
        case "http": return isLoopback(url) ? .success(url) : .failure(.insecure)
        default: return .failure(.malformed)
        }
    }

    /// 主机是否为本机（localhost、127.0.0.1、::1）：可用 http，且文字不会离开这台 Mac
    public static func isLoopback(_ url: URL) -> Bool {
        guard let host = normalizedHost(url) else { return false }
        return loopbackHosts.contains(host)
    }

    /// 界面上显示的主机名（例如 api.deepseek.com；IPv6 带方括号，非默认端口一并显示）
    public static func displayHost(_ url: URL) -> String {
        guard let host = normalizedHost(url) else { return url.absoluteString }
        let bracketed = host.contains(":") ? "[\(host)]" : host
        return url.port.map { "\(bracketed):\($0)" } ?? bracketed
    }

    /// 来源：小写协议 + 主机 + 非默认端口，例如 https://api.deepseek.com、http://[::1]:11434。
    /// API Key 与来源绑定（见 LLMStoredKey）
    public static func origin(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = normalizedHost(url) ?? ""
        let bracketed = host.contains(":") ? "[\(host)]" : host
        let defaultPort = scheme == "https" ? 443 : scheme == "http" ? 80 : nil
        guard let port = url.port, port != defaultPort else { return "\(scheme)://\(bracketed)" }
        return "\(scheme)://\(bracketed):\(port)"
    }

    /// 在接入地址后拼接接口路径，例如 base + "chat/completions"
    public static func endpoint(_ base: URL, path: String) -> URL {
        base.appending(path: path)
    }

    /// 重定向策略：只允许同一协议、主机与端口内的重定向。
    /// 跨主机重定向会把 Authorization 发给别处，协议降级会让密钥明文传输，一律拒绝
    public static func allowsRedirect(from original: URL, to destination: URL) -> Bool {
        original.scheme?.lowercased() == destination.scheme?.lowercased()
            && normalizedHost(original) == normalizedHost(destination)
            && effectivePort(original) == effectivePort(destination)
    }

    /// 小写、去掉 IPv6 的方括号
    private static func normalizedHost(_ url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }
}
