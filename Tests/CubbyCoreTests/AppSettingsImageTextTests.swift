import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 图片文字搜索 indexesImageText")
@MainActor
struct AppSettingsImageTextTests {
    @Test("默认开启")
    func defaultsToTrue() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).indexesImageText)
        }
    }

    @Test("关闭后新实例读回关闭，再开启后读回开启")
    func persists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).indexesImageText = false
            #expect(!AppSettings(defaults: defaults).indexesImageText)
            #expect(defaults.object(forKey: "indexesImageText") as? Bool == false)

            AppSettings(defaults: defaults).indexesImageText = true
            #expect(AppSettings(defaults: defaults).indexesImageText)
        }
    }

    @Test("存储值类型非法时回退为默认开启")
    func invalidStoredValueFallsBackToDefault() {
        withIsolatedDefaults { defaults in
            defaults.set("off", forKey: "indexesImageText")
            #expect(AppSettings(defaults: defaults).indexesImageText)
        }
    }
}
