import Carbon.HIToolbox
import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 截图设置")
@MainActor
struct AppSettingsScreenshotTests {
    /// ⌃⌥S：非默认的自定义截图快捷键
    private let customHotKey = HotKey(
        keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), keyLabel: "S")
    private let folder = URL(fileURLWithPath: "/Users/tester/Pictures/Shots", isDirectory: true)

    // MARK: - 截图快捷键

    @Test("从未设置时使用默认截图快捷键")
    func hotKeyDefaultsWhenNeverSet() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).screenshotHotKey == .screenshotDefault)
        }
    }

    @Test("自定义快捷键可被新实例读回")
    func customHotKeyPersists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).screenshotHotKey = customHotKey
            #expect(AppSettings(defaults: defaults).screenshotHotKey == customHotKey)
        }
    }

    @Test("用户清空后读回 nil，不会恢复为默认值")
    func clearedHotKeyStaysCleared() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).screenshotHotKey = nil
            #expect(AppSettings(defaults: defaults).screenshotHotKey == nil)
        }
    }

    @Test("清空后再设置：读回新值，禁用标志被清除")
    func settingAfterClearingReenables() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotHotKey = nil
            settings.screenshotHotKey = customHotKey

            #expect(AppSettings(defaults: defaults).screenshotHotKey == customHotKey)
            #expect(!defaults.bool(forKey: "screenshotHotKeyDisabled"))
        }
    }

    @Test("存储格式：快捷键为 JSON 数据，清空时写入禁用标志并移除数据")
    func storageFormat() throws {
        try withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotHotKey = customHotKey
            let data = try #require(defaults.data(forKey: "screenshotHotKey"))
            #expect(try JSONDecoder().decode(HotKey.self, from: data) == customHotKey)

            settings.screenshotHotKey = nil
            #expect(defaults.bool(forKey: "screenshotHotKeyDisabled"))
            #expect(defaults.data(forKey: "screenshotHotKey") == nil)
        }
    }

    @Test("禁用标志优先于残留的快捷键数据")
    func disabledFlagWins() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(try JSONEncoder().encode(customHotKey), forKey: "screenshotHotKey")
            defaults.set(true, forKey: "screenshotHotKeyDisabled")
            #expect(AppSettings(defaults: defaults).screenshotHotKey == nil)
        }
    }

    @Test(
        "快捷键数据损坏或类型不对时回退默认值（而不是视为关闭）",
        arguments: [
            Data("garbage".utf8),
            Data(#"{"keyCode": 19}"#.utf8),
        ])
    func corruptedHotKeyFallsBack(_ data: Data) {
        withIsolatedDefaults { defaults in
            defaults.set(data, forKey: "screenshotHotKey")
            #expect(AppSettings(defaults: defaults).screenshotHotKey == .screenshotDefault)
        }
    }

    @Test("截图快捷键与面板快捷键互不影响")
    func independentFromPanelHotKey() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotHotKey = nil
            #expect(settings.hotKey == .default)

            settings.hotKey = customHotKey
            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.screenshotHotKey == nil)
            #expect(reloaded.hotKey == customHotKey)
        }
    }

    // MARK: - 保存位置

    @Test("保存位置默认为 nil（跟随系统截图位置）")
    func saveDirectoryDefaultsToNil() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).screenshotSaveDirectory == nil)
        }
    }

    @Test("自定义保存位置以路径字符串存储，可被新实例读回")
    func saveDirectoryPersists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).screenshotSaveDirectory = folder
            #expect(defaults.string(forKey: "screenshotSaveDirectory") == folder.path)

            let reloaded = AppSettings(defaults: defaults).screenshotSaveDirectory
            #expect(reloaded?.path == folder.path)
            #expect(reloaded?.isFileURL == true)
            #expect(reloaded?.hasDirectoryPath == true)
        }
    }

    @Test("恢复默认后移除存储的键")
    func resettingSaveDirectoryRemovesKey() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotSaveDirectory = folder
            settings.screenshotSaveDirectory = nil

            #expect(defaults.object(forKey: "screenshotSaveDirectory") == nil)
            #expect(AppSettings(defaults: defaults).screenshotSaveDirectory == nil)
        }
    }

    // MARK: - 每次存储前询问位置

    @Test("「每次存储前询问位置」默认开启")
    func asksWhereToSaveByDefault() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).asksWhereToSaveScreenshots)
            #expect(defaults.object(forKey: "screenshotAsksWhereToSave") == nil)
        }
    }

    @Test("关闭后可被新实例读回；再打开也能读回")
    func asksWhereToSavePersists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).asksWhereToSaveScreenshots = false
            #expect(defaults.object(forKey: "screenshotAsksWhereToSave") as? Bool == false)
            #expect(!AppSettings(defaults: defaults).asksWhereToSaveScreenshots)

            AppSettings(defaults: defaults).asksWhereToSaveScreenshots = true
            #expect(AppSettings(defaults: defaults).asksWhereToSaveScreenshots)
        }
    }

    @Test("与保存位置互不影响")
    func asksWhereToSaveIsIndependentOfFolder() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotSaveDirectory = folder
            settings.asksWhereToSaveScreenshots = false
            settings.screenshotSaveDirectory = nil
            #expect(!AppSettings(defaults: defaults).asksWhereToSaveScreenshots)
        }
    }

    @Test("非文件 URL 不会被保存", arguments: ["https://example.com/shots", "ftp://host/dir"])
    func nonFileURLIsRejected(_ string: String) throws {
        let url = try #require(URL(string: string))
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotSaveDirectory = url

            #expect(settings.screenshotSaveDirectory == nil)
            #expect(defaults.object(forKey: "screenshotSaveDirectory") == nil)
        }
    }

    @Test("存储值为空、相对路径或类型不对时视为未设置", arguments: ["", "Pictures/Shots", "~/Pictures"])
    func invalidStoredPathIsIgnored(_ stored: String) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: "screenshotSaveDirectory")
            #expect(AppSettings(defaults: defaults).screenshotSaveDirectory == nil)
        }
    }

    @Test("存储值不是字符串时视为未设置")
    func nonStringStoredValueIsIgnored() {
        withIsolatedDefaults { defaults in
            defaults.set(42, forKey: "screenshotSaveDirectory")
            #expect(AppSettings(defaults: defaults).screenshotSaveDirectory == nil)
        }
    }

    // MARK: - 标注样式

    @Test("从未设置时每个工具都是默认样式")
    func annotationStylesDefault() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).annotationStyles == .default)
        }
    }

    @Test("修改后以 JSON 写入并可被新实例读回")
    func annotationStylesPersist() throws {
        try withIsolatedDefaults { defaults in
            let styles = ToolStyles.default
                .setting(AnnotationStyle(color: .blue, weight: .heavy), for: .arrow)
                .setting(AnnotationStyle(color: .green, weight: .light), for: .text)
            AppSettings(defaults: defaults).annotationStyles = styles

            let data = try #require(defaults.data(forKey: "annotationStyles"))
            #expect(data == styles.encoded())
            let reloaded = AppSettings(defaults: defaults).annotationStyles
            #expect(reloaded == styles)
            #expect(reloaded.style(for: .arrow) == AnnotationStyle(color: .blue, weight: .heavy))
            #expect(reloaded.style(for: .rectangle) == ScreenshotTool.rectangle.defaultStyle)
        }
    }

    @Test(
        "存储值损坏或类型不对时回退默认样式",
        arguments: [Data("garbage".utf8), Data("[1, 2]".utf8), Data("null".utf8)])
    func corruptedAnnotationStylesFallBack(_ data: Data) {
        withIsolatedDefaults { defaults in
            defaults.set(data, forKey: "annotationStyles")
            #expect(AppSettings(defaults: defaults).annotationStyles == .default)
        }
    }

    @Test("存储值不是 Data 时回退默认样式")
    func nonDataAnnotationStylesFallBack() {
        withIsolatedDefaults { defaults in
            defaults.set("red", forKey: "annotationStyles")
            #expect(AppSettings(defaults: defaults).annotationStyles == .default)
        }
    }

    @Test("部分条目无效时只忽略无效条目，其余保留")
    func partiallyInvalidAnnotationStyles() {
        withIsolatedDefaults { defaults in
            let json = #"{"arrow": {"color": "blue", "weight": "heavy"}, "pen": {"color": "pink"}, "laser": {}}"#
            defaults.set(Data(json.utf8), forKey: "annotationStyles")
            let styles = AppSettings(defaults: defaults).annotationStyles
            #expect(styles.style(for: .arrow) == AnnotationStyle(color: .blue, weight: .heavy))
            #expect(styles.style(for: .pen) == ScreenshotTool.pen.defaultStyle)
        }
    }

    // MARK: - 版本

    @Test("新增截图键不改变设置格式版本")
    func settingsVersionUnchanged() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.screenshotHotKey = nil
            settings.screenshotSaveDirectory = folder
            #expect(AppSettings.currentSettingsVersion == 1)
            #expect(defaults.integer(forKey: "settingsVersion") == 1)
        }
    }
}
