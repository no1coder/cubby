import Foundation

/// 链接卡左侧的字母底板（不联网取网站图标）：域名首字母 + 由域名决定的色相，同一网站每次颜色一致
public enum LinkBadge {
    /// 小写域名，去掉开头的 www.；不是带域名的网址时为 nil
    public static func host(of url: String) -> String? {
        guard let host = URL(string: url)?.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// 域名的第一个字母或数字（大写）；没有时为「#」
    public static func letter(for host: String) -> String {
        host.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "#"
    }

    /// 0..<1 的色相：FNV-1a（与进程无关的稳定哈希）对 360 取模
    public static func hue(for host: String) -> Double {
        var hash: UInt32 = 0x811C_9DC5
        for byte in host.utf8 {
            hash = (hash ^ UInt32(byte)) &* 0x0100_0193
        }
        return Double(hash % 360) / 360
    }
}
