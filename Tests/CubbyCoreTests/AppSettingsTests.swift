import Carbon.HIToolbox
import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 偏好设置")
@MainActor
struct AppSettingsTests {
    /// ⌥⌘K：非默认的自定义快捷键
    private let customHotKey = HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey), keyLabel: "K")

    @Test("首次启动使用默认值")
    func defaultValues() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.hotKey == .default)
            #expect(settings.historyLimit == AppSettings.defaultHistoryLimit)
            #expect(settings.pasteDirectly)
            #expect(!settings.isPaused)
            #expect(settings.ignoredBundleIDs == AppSettings.defaultIgnoredBundleIDs)
            #expect(settings.panelPosition == .mouse)
            #expect(settings.pasteFormat == .original)
            #expect(!settings.hasCompletedOnboarding)
        }
    }

    @Test("默认忽略列表包含常见密码管理器（含 KeePassXC）")
    func defaultIgnoredIncludesPasswordManagers() {
        let ids = AppSettings.defaultIgnoredBundleIDs
        #expect(ids.contains("org.keepassxc.keepassxc"))
        #expect(ids.contains("com.1password.1password"))
        #expect(Set(ids).count == ids.count)
    }

    @Test("默认上限在可选项之内")
    func defaultLimitIsSelectable() {
        #expect(AppSettings.historyLimitOptions.contains(AppSettings.defaultHistoryLimit))
    }

    @Test("修改后新实例可读回全部设置")
    func persistsChanges() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.hotKey = customHotKey
            settings.historyLimit = 1000
            settings.pasteDirectly = false
            settings.isPaused = true
            settings.ignoredBundleIDs = ["com.example.a"]
            settings.panelPosition = .statusItem
            settings.pasteFormat = .plainText
            settings.hasCompletedOnboarding = true

            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.hotKey == customHotKey)
            #expect(reloaded.historyLimit == 1000)
            #expect(!reloaded.pasteDirectly)
            #expect(reloaded.isPaused)
            #expect(reloaded.ignoredBundleIDs == ["com.example.a"])
            #expect(reloaded.panelPosition == .statusItem)
            #expect(reloaded.pasteFormat == .plainText)
            #expect(reloaded.hasCompletedOnboarding)
        }
    }

    @Test("快捷键以 JSON 形式写入 UserDefaults")
    func hotKeyStoredAsJSON() throws {
        try withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).hotKey = customHotKey
            let data = try #require(defaults.data(forKey: "hotKey"))
            #expect(try JSONDecoder().decode(HotKey.self, from: data) == customHotKey)
        }
    }

    @Test("面板位置的每个选项都可持久化", arguments: PanelPosition.allCases)
    func panelPositionRoundTrip(_ position: PanelPosition) {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).panelPosition = position
            #expect(AppSettings(defaults: defaults).panelPosition == position)
        }
    }

    @Test("清空忽略列表后不会恢复为默认列表")
    func emptyIgnoreListPersists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).ignoredBundleIDs = []
            #expect(AppSettings(defaults: defaults).ignoredBundleIDs.isEmpty)
        }
    }

    @Test("存储值非法时回退默认值")
    func invalidStoredValuesFallBack() {
        withIsolatedDefaults { defaults in
            defaults.set("unknownPreset", forKey: "hotKey")
            defaults.set(-5, forKey: "historyLimit")
            defaults.set("yes", forKey: "pasteDirectly")
            defaults.set("topLeft", forKey: "panelPosition")
            defaults.set("markdown", forKey: "pasteFormat")

            let settings = AppSettings(defaults: defaults)
            #expect(settings.hotKey == .default)
            #expect(settings.historyLimit == AppSettings.defaultHistoryLimit)
            #expect(settings.pasteDirectly)
            #expect(settings.panelPosition == .mouse)
            #expect(settings.pasteFormat == .original)
        }
    }

    @Test(
        "快捷键数据损坏或字段缺失时回退默认快捷键",
        arguments: [
            Data("garbage".utf8),
            Data(#"{"keyCode": 9}"#.utf8),
            Data(#"{"keyCode": "V", "modifiers": 0, "keyLabel": "V"}"#.utf8),
        ])
    func corruptedHotKeyFallsBack(_ data: Data) {
        withIsolatedDefaults { defaults in
            defaults.set(data, forKey: "hotKey")
            #expect(AppSettings(defaults: defaults).hotKey == .default)
        }
    }

    // MARK: - shouldCapture

    @Test("暂停时一律不采集")
    func pausedCapturesNothing() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.isPaused = true
            #expect(!settings.shouldCapture(from: nil))
            #expect(!settings.shouldCapture(from: SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")))
        }
    }

    @Test("来源为空或无 bundleID 时采集")
    func unknownSourceIsCaptured() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.shouldCapture(from: nil))
            #expect(settings.shouldCapture(from: SourceApp(bundleID: nil, name: "Mystery")))
        }
    }

    @Test("忽略列表中的应用不采集，其他应用采集")
    func ignoredAppsAreSkipped() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let ignored = AppSettings.defaultIgnoredBundleIDs[0]
            #expect(!settings.shouldCapture(from: SourceApp(bundleID: ignored, name: "1Password")))
            #expect(settings.shouldCapture(from: SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")))
        }
    }

    // MARK: - 忽略列表增删

    @Test("addIgnoredApp 追加且去重，并持久化")
    func addIgnoredAppDeduplicates() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.ignoredBundleIDs = ["a"]
            settings.addIgnoredApp(bundleID: "b")
            settings.addIgnoredApp(bundleID: "b")
            settings.addIgnoredApp(bundleID: "a")

            #expect(settings.ignoredBundleIDs == ["a", "b"])
            #expect(AppSettings(defaults: defaults).ignoredBundleIDs == ["a", "b"])
            #expect(!settings.shouldCapture(from: SourceApp(bundleID: "b", name: nil)))
        }
    }

    @Test("removeIgnoredApp 删除指定项，不存在时无影响")
    func removeIgnoredApp() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.ignoredBundleIDs = ["a", "b", "c"]
            settings.removeIgnoredApp(bundleID: "b")
            settings.removeIgnoredApp(bundleID: "zzz")

            #expect(settings.ignoredBundleIDs == ["a", "c"])
            #expect(AppSettings(defaults: defaults).ignoredBundleIDs == ["a", "c"])
            #expect(settings.shouldCapture(from: SourceApp(bundleID: "b", name: nil)))
        }
    }
}
