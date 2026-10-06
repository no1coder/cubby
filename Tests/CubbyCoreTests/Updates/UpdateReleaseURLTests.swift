import Foundation
import Testing
@testable import CubbyCore

@Suite("UpdateReleaseURL 发布页地址白名单")
struct UpdateReleaseURLTests {
    @Test(
        "只接受 https://github.com 上本仓库的发布页",
        arguments: [
            ("https://github.com/no1coder/cubby/releases/tag/v0.3.0", true),
            ("https://GitHub.com/no1coder/cubby/releases", true),
            ("http://github.com/no1coder/cubby/releases", false),
            ("https://github.com.evil.example/releases", false),
            ("https://evil.example/github.com", false),
            ("https://api.github.com/repos/no1coder/cubby", false),
            ("https://github.com:8443/no1coder/cubby", false),
            ("https://user@github.com/no1coder/cubby", false),
            ("file:///Applications/Cubby.app", false),
            ("javascript:alert(1)", false),
            // 只认本仓库的发布页：被改写的偏好设置不能把用户带去别人的下载
            ("https://github.com/evil/x/releases/download/v99/Cubby.dmg", false),
            ("https://github.com/no1coder/cubby-evil/releases", false),
            ("https://github.com/no1coder/cubby/archive/main.zip", false),
            ("https://github.com/no1coder/cubby/releases/../../evil", false),
        ])
    func allowsOnlyGitHub(_ text: String, _ allowed: Bool) throws {
        let url = try #require(URL(string: text))
        #expect(UpdateReleaseURL.isAllowed(url) == allowed)
    }

    @Test("不在白名单内或缺失时回退到固定的发布页")
    func sanitizes() throws {
        let page = UpdateReleaseURL.releasesPage
        #expect(page.absoluteString == "https://github.com/no1coder/cubby/releases")
        #expect(UpdateReleaseURL.isAllowed(page))
        #expect(UpdateReleaseURL.sanitized(nil) == page)
        #expect(UpdateReleaseURL.sanitized(URL(string: "https://evil.example/x")) == page)
        let tag = try #require(URL(string: "https://github.com/no1coder/cubby/releases/tag/v0.3.0"))
        #expect(UpdateReleaseURL.sanitized(tag) == tag)
    }
}
