import Carbon.HIToolbox
import Foundation
import Testing
@testable import CubbyCore

/// 晾衣绳设置（docs/UI-UPGRADE-PLAN.md 第 5 节）：开关、快捷键、绳上条目的持久化
@Suite("AppSettings 晾衣绳")
@MainActor
struct AppSettingsClotheslineTests {
    private let customHotKey = HotKey(
        keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey), keyLabel: "L")

    @Test("默认开启，快捷键为 ⌃⌥T，绳上为空")
    func defaults() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.clotheslineEnabled)
            #expect(settings.clotheslineHotKey == .clotheslineDefault)
            #expect(settings.clothesline.isEmpty)
        }
    }

    @Test("关闭后可被新实例读回")
    func enabledPersists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).clotheslineEnabled = false
            #expect(!AppSettings(defaults: defaults).clotheslineEnabled)
            AppSettings(defaults: defaults).clotheslineEnabled = true
            #expect(AppSettings(defaults: defaults).clotheslineEnabled)
        }
    }

    @Test("开关存储值类型不对时回退为开启")
    func enabledInvalidFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set("off", forKey: "clotheslineEnabled")
            #expect(AppSettings(defaults: defaults).clotheslineEnabled)
        }
    }

    @Test("快捷键：自定义、关闭、再打开都能读回")
    func hotKeyRoundTrip() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).clotheslineHotKey = customHotKey
            #expect(AppSettings(defaults: defaults).clotheslineHotKey == customHotKey)

            AppSettings(defaults: defaults).clotheslineHotKey = nil
            #expect(defaults.bool(forKey: "clotheslineHotKeyDisabled"))
            #expect(AppSettings(defaults: defaults).clotheslineHotKey == nil)

            AppSettings(defaults: defaults).clotheslineHotKey = customHotKey
            #expect(AppSettings(defaults: defaults).clotheslineHotKey == customHotKey)
        }
    }

    @Test("快捷键数据损坏时回退默认值")
    func hotKeyCorruptionFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set(Data(#"{"keyCode": 17}"#.utf8), forKey: "clotheslineHotKey")
            #expect(AppSettings(defaults: defaults).clotheslineHotKey == .clotheslineDefault)
        }
    }

    @Test("绳上条目按顺序以 UUID 字符串数组存储，可被新实例读回")
    func itemsRoundTrip() {
        withIsolatedDefaults { defaults in
            let ids = [UUID(), UUID(), UUID()]
            AppSettings(defaults: defaults).clothesline = Clothesline(itemIDs: ids)
            #expect(defaults.stringArray(forKey: "clotheslineItems") == ids.map(\.uuidString))
            #expect(AppSettings(defaults: defaults).clothesline.itemIDs == ids)
        }
    }

    @Test("读回时丢弃无法解析与重复的 id")
    func itemsTolerateCorruption() {
        withIsolatedDefaults { defaults in
            let first = UUID()
            let second = UUID()
            defaults.set(
                [first.uuidString, "not-a-uuid", second.uuidString, first.uuidString, ""],
                forKey: "clotheslineItems")
            #expect(AppSettings(defaults: defaults).clothesline.itemIDs == [first, second])
        }
    }

    @Test("存储值类型不对时视为空绳")
    func itemsWrongTypeIsEmpty() {
        withIsolatedDefaults { defaults in
            defaults.set(42, forKey: "clotheslineItems")
            #expect(AppSettings(defaults: defaults).clothesline.isEmpty)
        }
    }

    @Test("取下最后一张后存为空数组，读回为空绳")
    func emptyingPersists() {
        withIsolatedDefaults { defaults in
            let id = UUID()
            let settings = AppSettings(defaults: defaults)
            settings.clothesline = settings.clothesline.hanging(id).line
            settings.clothesline = settings.clothesline.removing(id)
            #expect(defaults.stringArray(forKey: "clotheslineItems") == [])
            #expect(AppSettings(defaults: defaults).clothesline.isEmpty)
        }
    }
}
