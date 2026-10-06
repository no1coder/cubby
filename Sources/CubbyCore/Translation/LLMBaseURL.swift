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
    /// 国家代码顶级域名下常见的二级后缀（com.cn、co.uk 中的 com、co）：取主机简称时与顶级域名一并去掉
    static let secondLevelSuffixes: Set<String> = ["com", "net", "org", "gov", "edu", "ac", "co"]
    /// 国家代码顶级域名的长度（cn、uk、jp）
    private static let countryCodeLength = 2
    /// 国际化域名的 ASCII 形式前缀（xn--fsqu00a 这样的标签对用户没有意义）
    private static let punycodePrefix = "xn--"

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
        let shown = bracketed(host)
        return url.port.map { "\(shown):\($0)" } ?? shown
    }

    /// 翻译条徽标上的主机简称：域名的主体部分（api.siliconflow.cn → siliconflow，api.example.com.cn → example）。
    /// 本机名与 IP 地址原样显示（不带端口，IPv6 带方括号）；没有主机时退回完整地址
    public static func shortHost(_ url: URL) -> String {
        guard let host = normalizedHost(url) else { return url.absoluteString }
        if isLoopback(url) || isIPAddress(host) { return bracketed(host) }
        return mainLabel(of: host) ?? host
    }

    /// 来源：小写协议 + 主机 + 非默认端口，例如 https://api.deepseek.com、http://[::1]:11434。
    /// API Key 与来源绑定（见 LLMStoredKey）
    public static func origin(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = bracketed(normalizedHost(url) ?? "")
        let defaultPort = scheme == "https" ? 443 : scheme == "http" ? 80 : nil
        guard let port = url.port, port != defaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
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

    /// IPv6 地址加方括号（[::1]），其余原样
    private static func bracketed(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }

    /// IPv6（含冒号）或各段都是数字的 IPv4 地址
    private static func isIPAddress(_ host: String) -> Bool {
        host.contains(":")
            || host.split(separator: ".").allSatisfy { label in label.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// 去掉顶级域名（顶级域名是国家代码时连同 com、co 这类二级后缀）后的最后一段；
    /// 只有一两段的主机取第一段（openrouter.ai → openrouter）。末尾的点（完全限定域名）忽略。
    /// 取到的是 punycode（国际化域名）或不超过 2 个字符（多半是表里没有的公共后缀，如 ne.jp）时返回 nil，
    /// 由调用方显示完整主机
    private static func mainLabel(of host: String) -> String? {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2, let topLevel = labels.last else { return readableLabel(labels.first) }
        let withoutTopLevel = labels.dropLast()
        let isCountryCode = topLevel.count == countryCodeLength && topLevel.allSatisfy(\.isLetter)
        let hasSecondLevelSuffix = isCountryCode && secondLevelSuffixes.contains(withoutTopLevel.last ?? "")
        return readableLabel((hasSecondLevelSuffix ? withoutTopLevel.dropLast() : withoutTopLevel).last)
    }

    /// 能单独认出服务的一段：不是 punycode，且长于 2 个字符
    private static func readableLabel(_ label: String?) -> String? {
        guard let label, label.count > countryCodeLength, !label.hasPrefix(punycodePrefix) else { return nil }
        return label
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }
}
