import Foundation
import Testing
@testable import CubbyCore

/// UserDefaults 中的 settingsVersion：缺失时写入当前版本，已有值不被降级覆盖
@Suite("AppSettings 设置版本号")
@MainActor
struct AppSettingsVersionTests {
    private let key = "settingsVersion"

    @Test("当前设置版本为 1")
    func currentVersion() {
        #expect(AppSettings.currentSettingsVersion == 1)
    }

    @Test("首次启动写入 settingsVersion = 1")
    func firstLaunchWritesVersion() {
        withIsolatedDefaults { defaults in
            #expect(defaults.object(forKey: key) == nil)
            _ = AppSettings(defaults: defaults)
            #expect(defaults.object(forKey: key) as? Int == 1)
        }
    }

    @Test("v0.1 遗留设置（无版本号）补写版本号，原有取值保持不变")
    func legacySettingsKeepValues() {
        withIsolatedDefaults { defaults in
            defaults.set(1000, forKey: "historyLimit")
            defaults.set(false, forKey: "pasteDirectly")
            defaults.set(["com.example.a"], forKey: "ignoredBundleIDs")

            let settings = AppSettings(defaults: defaults)

            #expect(defaults.object(forKey: key) as? Int == 1)
            #expect(settings.historyLimit == 1000)
            #expect(!settings.pasteDirectly)
            #expect(settings.ignoredBundleIDs == ["com.example.a"])
        }
    }

    @Test("重复初始化保持版本号为 1")
    func repeatedInitIsStable() {
        withIsolatedDefaults { defaults in
            _ = AppSettings(defaults: defaults)
            _ = AppSettings(defaults: defaults)
            #expect(defaults.object(forKey: key) as? Int == 1)
        }
    }

    @Test("非法的版本号值视为缺失并重写为 1", arguments: ["abc", "1"])
    func invalidVersionIsRewritten(_ stored: String) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: key)
            _ = AppSettings(defaults: defaults)
            #expect(defaults.object(forKey: key) as? Int == 1)
        }
    }

    @Test("更高版本写入的版本号不被覆盖，设置仍可读取")
    func newerVersionIsPreserved() {
        withIsolatedDefaults { defaults in
            defaults.set(99, forKey: key)
            defaults.set(200, forKey: "historyLimit")

            let settings = AppSettings(defaults: defaults)

            #expect(defaults.object(forKey: key) as? Int == 99)
            #expect(settings.historyLimit == 200)
        }
    }
}
