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

    @Test("从未设置过时，默认 ⌃⇧V 已被面板或截图快捷键占用：视为关闭，不与自己的快捷键撞键")
    func defaultYieldsToExistingShortcuts() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(try JSONEncoder().encode(HotKey.imagesDefault), forKey: "hotKey")
            #expect(AppSettings(defaults: defaults).imagesHotKey == nil)
        }
        try withIsolatedDefaults { defaults in
            defaults.set(try JSONEncoder().encode(HotKey.imagesDefault), forKey: "screenshotHotKey")
            #expect(AppSettings(defaults: defaults).imagesHotKey == nil)
        }
    }

    @Test("用户明确设成 ⌃⇧V 时照样读回（冲突由设置里的录制器拦下，不在这里改写）")
    func explicitChoiceIsKept() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(try JSONEncoder().encode(HotKey.imagesDefault), forKey: "imagesHotKey")
            defaults.set(try JSONEncoder().encode(customHotKey), forKey: "hotKey")
            #expect(AppSettings(defaults: defaults).imagesHotKey == .imagesDefault)
        }
    }

    @Test("晾衣绳的默认 ⌃⌥T 被其他快捷键占用时同样视为关闭")
    func clotheslineDefaultYields() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(try JSONEncoder().encode(HotKey.clotheslineDefault), forKey: "imagesHotKey")
            let settings = AppSettings(defaults: defaults)
            #expect(settings.imagesHotKey == .clotheslineDefault)
            #expect(settings.clotheslineHotKey == nil)
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

/// 按动作读写全局快捷键（设置里的冲突检查、热键注册失败时的回退共用）
@Suite("AppSettings 按动作读写快捷键")
@MainActor
struct AppSettingsHotKeyActionTests {
    private let custom = HotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey), keyLabel: "J")

    @Test("每个动作读到对应的快捷键", arguments: HotKeyAction.allCases)
    func reading(_ action: HotKeyAction) {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let expected: HotKey? =
                switch action {
                case .togglePanel: .default
                case .screenshot: .screenshotDefault
                case .images: .imagesDefault
                case .clothesline: .clotheslineDefault
                }
            #expect(settings.hotKey(for: action) == expected)
        }
    }

    @Test("按动作写入后可读回，且不影响其他动作", arguments: HotKeyAction.allCases)
    func writing(_ action: HotKeyAction) {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.setHotKey(custom, for: action)
            #expect(AppSettings(defaults: defaults).hotKey(for: action) == custom)
            for other in HotKeyAction.allCases where other != action {
                #expect(settings.hotKey(for: other) != custom)
            }
        }
    }

    @Test("面板快捷键不可关闭：写入 nil 被忽略；其他动作写入 nil 即关闭")
    func clearing() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.setHotKey(nil, for: .togglePanel)
            #expect(settings.hotKey(for: .togglePanel) == .default)
            settings.setHotKey(nil, for: .images)
            #expect(settings.hotKey(for: .images) == nil)
        }
    }
}
