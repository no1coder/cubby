import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 剪贴板安全设置")
@MainActor
struct AppSettingsSecurityTests {
    @Test("默认：开启守护、守护全部类型、粘贴后核对")
    func defaults() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.addressGuardEnabled)
            #expect(settings.guardedKinds == Set(SensitiveKind.allCases))
            #expect(settings.verifiesPastes)
        }
    }

    @Test("修改后新实例读回一致")
    func roundTrip() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.addressGuardEnabled = false
            settings.guardedKinds = [.bitcoin, .bankCard]
            settings.verifiesPastes = false

            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.addressGuardEnabled == false)
            #expect(reloaded.guardedKinds == [.bitcoin, .bankCard])
            #expect(reloaded.verifiesPastes == false)
            #expect(defaults.stringArray(forKey: "guardedKinds") == ["bankCard", "bitcoin"])
        }
    }

    @Test("存储里无法识别的类型被忽略")
    func ignoresUnknownKinds() {
        withIsolatedDefaults { defaults in
            defaults.set(["ethereum", "dogecoin", ""], forKey: "guardedKinds")
            #expect(AppSettings(defaults: defaults).guardedKinds == [.ethereum])
        }
    }

    @Test("存储的空数组表示一个都不守护")
    func emptyStoredArray() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.guardedKinds = []
            #expect(AppSettings(defaults: defaults).guardedKinds.isEmpty)
        }
    }
}
