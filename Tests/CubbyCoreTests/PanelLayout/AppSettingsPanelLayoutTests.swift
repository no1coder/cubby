import Carbon.HIToolbox
import Foundation
import Testing
@testable import CubbyCore

/// 面板位置与「上次选的浮动位置」、「只看图片」快捷键（docs/UI-UPGRADE-PLAN.md 第 3、4 节）
@Suite("AppSettings 面板排布与只看图片")
@MainActor
struct AppSettingsPanelLayoutTests {
    /// ⌃⌥I：非默认的自定义快捷键
    private let customHotKey = HotKey(
        keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(controlKey | optionKey), keyLabel: "I")

    // MARK: - 浮动位置记忆

    @Test("从未设置时面板在鼠标旁，记住的浮动位置也是鼠标旁")
    func defaults() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.panelPosition == .mouse)
            #expect(settings.floatingPanelPosition == .mouse)
        }
    }

    @Test("选择浮动位置时同时记住它，并可被新实例读回", arguments: [PanelPosition.statusItem, .center])
    func choosingFloatingRemembersIt(_ position: PanelPosition) {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).panelPosition = position
            #expect(defaults.string(forKey: "floatingPanelPosition") == position.rawValue)
            #expect(AppSettings(defaults: defaults).floatingPanelPosition == position)
        }
    }

    @Test("切到停靠排布时保留上次的浮动位置", arguments: [PanelPosition.dockRight, .dockBottom])
    func dockingKeepsFloating(_ dock: PanelPosition) {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.panelPosition = .center
            settings.panelPosition = dock
            #expect(settings.floatingPanelPosition == .center)

            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.panelPosition == dock)
            #expect(reloaded.floatingPanelPosition == .center)
        }
    }

    @Test("顶栏布局按钮循环一圈后回到用户选过的浮动位置")
    func layoutButtonRoundTrip() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.panelPosition = .statusItem
            for _ in 0..<3 {
                settings.panelPosition = settings.panelPosition.cycledLayout(
                    floatingFallback: settings.floatingPanelPosition)
            }
            #expect(settings.panelPosition == .statusItem)
        }
    }

    @Test("旧版本只存了浮动位置：记住的浮动位置取它")
    func migratesFromPanelPosition() {
        withIsolatedDefaults { defaults in
            defaults.set("center", forKey: "panelPosition")
            #expect(AppSettings(defaults: defaults).floatingPanelPosition == .center)
        }
    }

    @Test(
        "当前是浮动位置时以它为准；否则取记住的浮动位置，再不行回到鼠标旁",
        arguments: [
            ("dockRight", "statusItem", PanelPosition.statusItem),
            ("garbage", "center", .center),
            ("dockBottom", "dockRight", .mouse),
            ("", "garbage", .mouse),
            ("center", "statusItem", .statusItem),
        ])
    func invalidFloatingFallsBack(_ storedFloating: String, _ storedPosition: String, _ expected: PanelPosition) {
        withIsolatedDefaults { defaults in
            defaults.set(storedFloating, forKey: "floatingPanelPosition")
            defaults.set(storedPosition, forKey: "panelPosition")
            #expect(AppSettings(defaults: defaults).floatingPanelPosition == expected)
        }
    }

    @Test("非法的面板位置回退到鼠标旁")
    func invalidPanelPositionFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set("dockLeft", forKey: "panelPosition")
            #expect(AppSettings(defaults: defaults).panelPosition == .mouse)
        }
    }

    // MARK: - 只看图片快捷键

    @Test("从未设置时为 ⌃⇧V")
    func imagesHotKeyDefault() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).imagesHotKey == .imagesDefault)
        }
    }

    @Test("自定义后可被新实例读回；关闭后读回 nil 并写入禁用标志")
    func imagesHotKeyRoundTrip() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).imagesHotKey = customHotKey
            #expect(AppSettings(defaults: defaults).imagesHotKey == customHotKey)

            AppSettings(defaults: defaults).imagesHotKey = nil
            #expect(defaults.bool(forKey: "imagesHotKeyDisabled"))
            #expect(defaults.data(forKey: "imagesHotKey") == nil)
            #expect(AppSettings(defaults: defaults).imagesHotKey == nil)

            AppSettings(defaults: defaults).imagesHotKey = customHotKey
            #expect(!defaults.bool(forKey: "imagesHotKeyDisabled"))
            #expect(AppSettings(defaults: defaults).imagesHotKey == customHotKey)
        }
    }

    @Test("数据损坏时回退默认值；禁用标志优先于残留数据")
    func imagesHotKeyCorruption() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(Data("garbage".utf8), forKey: "imagesHotKey")
            #expect(AppSettings(defaults: defaults).imagesHotKey == .imagesDefault)

            defaults.set(try JSONEncoder().encode(customHotKey), forKey: "imagesHotKey")
            defaults.set(true, forKey: "imagesHotKeyDisabled")
            #expect(AppSettings(defaults: defaults).imagesHotKey == nil)
        }
    }

    @Test("与其他可关闭的快捷键各用各的禁用标志")
    func disabledFlagsAreIndependent() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.imagesHotKey = nil
            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.screenshotHotKey == .screenshotDefault)
            #expect(reloaded.clotheslineHotKey == .clotheslineDefault)
            #expect(reloaded.hotKey == .default)
        }
    }
}
