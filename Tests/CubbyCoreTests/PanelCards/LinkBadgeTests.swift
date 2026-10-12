import Testing
@testable import CubbyCore

/// 链接卡的字母底板（不联网，不取网站图标）：域名、首字母与由域名决定的色相
@Suite("LinkBadge 链接字母底板")
struct LinkBadgeTests {
    @Test(
        "域名：小写、去掉 www.；不是网址时为 nil",
        arguments: [
            ("https://github.com/no1coder/cubby", "github.com"),
            ("https://WWW.Apple.com/mac/", "apple.com"),
            ("http://localhost:8080/path", "localhost"),
            ("https://www2.example.org", "www2.example.org"),
            ("mailto:someone@example.com", nil),
            ("not a url", nil),
            ("", nil),
        ] as [(String, String?)])
    func host(_ url: String, _ expected: String?) {
        #expect(LinkBadge.host(of: url) == expected)
    }

    @Test(
        "首字母：域名第一个字母或数字，大写；没有时为「#」",
        arguments: [
            ("github.com", "G"),
            ("apple.com", "A"),
            ("1password.com", "1"),
            ("-dash.io", "D"),
            ("---", "#"),
            ("", "#"),
        ])
    func letter(_ host: String, _ expected: String) {
        #expect(LinkBadge.letter(for: host) == expected)
    }

    @Test("色相在 0..<1 之间，同一域名每次相同")
    func hueIsStable() {
        for host in ["github.com", "apple.com", "example.org", ""] {
            let hue = LinkBadge.hue(for: host)
            #expect(hue >= 0 && hue < 1)
            #expect(hue == LinkBadge.hue(for: host))
        }
    }

    @Test("不同域名的色相分散（不全挤在一处）")
    func huesSpread() {
        let hosts = ["github.com", "apple.com", "example.org", "figma.com", "notion.so", "swift.org", "zhihu.com"]
        let hues = hosts.map(LinkBadge.hue(for:))
        #expect(Set(hues.map { Int($0 * 10) }).count >= 4)
    }

    @Test("色相固定值（用稳定的哈希，不随进程变化）")
    func hueFixedValue() {
        // FNV-1a 32 位："a" = 0xE40C292C
        #expect(LinkBadge.hue(for: "a") == Double(0xE40C_292C % 360) / 360)
    }
}
