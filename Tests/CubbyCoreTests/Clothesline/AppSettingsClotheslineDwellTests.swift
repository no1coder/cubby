import Foundation
import Testing
@testable import CubbyCore

/// 晾衣绳的停留时长与截图自动挂绳（docs/UI-UPGRADE-PLAN.md 第 5 节）
@Suite("AppSettings 晾衣绳停留时长与截图挂绳")
@MainActor
struct AppSettingsClotheslineDwellTests {
    // MARK: - 停留时长

    @Test("停留时长默认 0.5 秒，且在可选列表里")
    func dwellDefault() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.clotheslineDwell == 0.5)
            #expect(AppSettings.defaultClotheslineDwell == 0.5)
            #expect(AppSettings.clotheslineDwellChoices.contains(AppSettings.defaultClotheslineDwell))
        }
    }

    @Test("可选列表从短到长、互不重复，且都在有效范围内")
    func dwellChoicesAreValid() {
        let choices = AppSettings.clotheslineDwellChoices
        #expect(choices == [0.3, 0.5, 0.8, 1.2])
        #expect(choices == choices.sorted())
        #expect(Set(choices).count == choices.count)
        #expect(choices.allSatisfy(AppSettings.clotheslineDwellRange.contains))
    }

    @Test("每个可选值都能被新实例读回", arguments: AppSettings.clotheslineDwellChoices)
    func dwellRoundTrip(_ value: TimeInterval) {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).clotheslineDwell = value
            #expect(defaults.double(forKey: "clotheslineDwell") == value)
            #expect(AppSettings(defaults: defaults).clotheslineDwell == value)
        }
    }

    @Test("范围内的非列表值（例如手动写入的 2 秒）原样读回", arguments: [0.1, 2.0, 3.0])
    func dwellInRangeKept(_ value: TimeInterval) {
        withIsolatedDefaults { defaults in
            defaults.set(value, forKey: "clotheslineDwell")
            #expect(AppSettings(defaults: defaults).clotheslineDwell == value)
        }
    }

    @Test(
        "存储值超出 0.1…3.0 或不是有限数时回退 0.5",
        arguments: [0.0, 0.09, -1, 3.01, 60, Double.infinity, -Double.infinity, Double.nan])
    func dwellOutOfRangeFallsBack(_ value: TimeInterval) {
        withIsolatedDefaults { defaults in
            defaults.set(value, forKey: "clotheslineDwell")
            #expect(AppSettings(defaults: defaults).clotheslineDwell == 0.5)
        }
    }

    @Test("存储值不是数字时回退 0.5")
    func dwellWrongTypeFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set("0.8", forKey: "clotheslineDwell")
            #expect(AppSettings(defaults: defaults).clotheslineDwell == 0.5)
            defaults.set(["0.8"], forKey: "clotheslineDwell")
            #expect(AppSettings(defaults: defaults).clotheslineDwell == 0.5)
            // 布尔值在 UserDefaults 里也是 NSNumber（true 会读成 1.0，落在范围内），同样视为无效
            defaults.set(true, forKey: "clotheslineDwell")
            #expect(AppSettings(defaults: defaults).clotheslineDwell == 0.5)
        }
    }

    @Test("写入超出范围的值时立即回到默认值，存储的也是默认值", arguments: [0.0, 5.0, Double.nan])
    func dwellSetterSanitizes(_ value: TimeInterval) {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.clotheslineDwell = 1.2
            settings.clotheslineDwell = value
            #expect(settings.clotheslineDwell == 0.5)
            #expect(defaults.double(forKey: "clotheslineDwell") == 0.5)
            #expect(AppSettings(defaults: defaults).clotheslineDwell == 0.5)
        }
    }

    // MARK: - 截图自动挂绳

    @Test("截图自动挂到晾衣绳默认关闭")
    func hangsScreenshotsDefault() {
        withIsolatedDefaults { defaults in
            #expect(!AppSettings(defaults: defaults).hangsScreenshotsOnClothesline)
        }
    }

    @Test("开启、关闭都能被新实例读回")
    func hangsScreenshotsRoundTrip() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).hangsScreenshotsOnClothesline = true
            #expect(defaults.bool(forKey: "hangsScreenshotsOnClothesline"))
            #expect(AppSettings(defaults: defaults).hangsScreenshotsOnClothesline)

            AppSettings(defaults: defaults).hangsScreenshotsOnClothesline = false
            #expect(!AppSettings(defaults: defaults).hangsScreenshotsOnClothesline)
        }
    }

    @Test("存储值类型不对时回退为关闭")
    func hangsScreenshotsWrongTypeFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set("yes", forKey: "hangsScreenshotsOnClothesline")
            #expect(!AppSettings(defaults: defaults).hangsScreenshotsOnClothesline)
        }
    }

    // MARK: - 版本

    @Test("新增的两个键不改变设置格式版本")
    func settingsVersionUnchanged() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.clotheslineDwell = 0.8
            settings.hangsScreenshotsOnClothesline = true
            #expect(AppSettings.currentSettingsVersion == 1)
            #expect(defaults.integer(forKey: "settingsVersion") == 1)
        }
    }
}
