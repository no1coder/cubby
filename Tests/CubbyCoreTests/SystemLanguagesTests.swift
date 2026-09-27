import Foundation
import Testing
@testable import CubbyCore

@Suite("SystemLanguages 系统首选语言")
struct SystemLanguagesTests {
    @Test("读取全局域的 AppleLanguages，不受应用界面语言覆盖影响")
    func readsGlobalDomain() {
        let global: [String: Any] = ["AppleLanguages": ["zh-Hans-CN", "en-CN"]]
        #expect(SystemLanguages.preferred(globalDomain: global, fallback: ["en"]) == ["zh-Hans-CN", "en-CN"])
    }

    @Test(
        "全局域缺失、为空或类型不对时回退",
        arguments: [
            nil,
            [:],
            ["AppleLanguages": [String]()],
            ["AppleLanguages": "zh-Hans"],
        ] as [[String: any Sendable]?])
    func fallsBack(_ global: [String: any Sendable]?) {
        #expect(SystemLanguages.preferred(globalDomain: global, fallback: ["en-US"]) == ["en-US"])
    }

    @Test("本机调用返回非空列表")
    func liveValueIsNotEmpty() {
        #expect(!SystemLanguages.preferred.isEmpty)
    }
}
