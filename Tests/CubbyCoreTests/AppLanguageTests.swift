import Foundation
import Testing
@testable import CubbyCore

@Suite("AppLanguage 界面语言")
struct AppLanguageTests {
    @Test(
        "应用偏好域未设置或为空时跟随系统",
        arguments: [nil, [String]()] as [[String]?])
    func followsSystemWithoutOverride(_ languages: [String]?) {
        #expect(AppLanguage(appleLanguages: languages) == .system)
    }

    @Test(
        "有覆盖时按应用实际会显示的语言归类（含地区与旧式标识）",
        arguments: [
            (["en"], AppLanguage.english),
            (["en-GB"], .english),
            (["zh-Hans"], .simplifiedChinese),
            (["zh-Hans-CN"], .simplifiedChinese),
            (["zh-CN"], .simplifiedChinese),
            (["ja", "zh-Hans"], .simplifiedChinese),
            // 不支持的语言：应用实际回退到英文界面，选单如实显示
            (["zh-Hant-TW"], .english),
            (["fr"], .english),
        ])
    func classifiesOverride(_ languages: [String], expected: AppLanguage) {
        #expect(AppLanguage(appleLanguages: languages) == expected)
    }

    @Test("写回 AppleLanguages 的值：跟随系统为 nil，固定语言只写一项")
    func appleLanguagesValue() {
        #expect(AppLanguage.system.appleLanguages == nil)
        #expect(AppLanguage.english.appleLanguages == ["en"])
        #expect(AppLanguage.simplifiedChinese.appleLanguages == ["zh-Hans"])
    }

    @Test("写入的值能原样读回")
    func roundTrips() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage(appleLanguages: language.appleLanguages) == language)
        }
    }

    @Test(
        "跟随系统时按系统首选语言解析界面语言",
        arguments: [
            (["zh-Hans-CN"], "zh-Hans"),
            (["ja-JP", "zh-Hans"], "zh-Hans"),
            (["en-US", "zh-Hans"], "en"),
            (["fr-FR"], "en"),
            ([], "en"),
        ])
    func resolvesSystem(_ preferences: [String], expected: String) {
        #expect(AppLanguage.system.resolvedLocalization(systemPreferences: preferences) == expected)
    }

    @Test("固定语言与系统首选语言无关")
    func resolvesFixedLanguage() {
        #expect(AppLanguage.english.resolvedLocalization(systemPreferences: ["zh-Hans-CN"]) == "en")
        #expect(AppLanguage.simplifiedChinese.resolvedLocalization(systemPreferences: ["en-US"]) == "zh-Hans")
    }

    @Test("支持的本地化与选项一一对应，源语言在前")
    func supportedLocalizations() {
        #expect(AppLanguage.supportedLocalizations == ["en", "zh-Hans"])
    }

    @Test("与 Info.plist 的 CFBundleLocalizations 与开发语言一致：新增本地化时两边不会漏改")
    func matchesInfoPlist() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let plist = try #require(NSDictionary(contentsOf: plistURL))
        #expect(plist["CFBundleLocalizations"] as? [String] == AppLanguage.supportedLocalizations)
        #expect(plist["CFBundleDevelopmentRegion"] as? String == AppLanguage.supportedLocalizations.first)
    }
}

@Suite("AppLanguageStore 读写应用偏好域")
@MainActor
struct AppLanguageStoreTests {
    @Test("未设置时跟随系统：不会读到全局域里的系统语言")
    func ignoresGlobalDomain() {
        // 普通读取会回退到全局域（本机系统语言总是有值），偏好域读取则不会
        withIsolatedLanguageStore { store, _ in
            #expect(store.language == .system)
        }
    }

    @Test("选定语言后写入偏好域并可读回，新实例同样读到")
    func persistsSelection() {
        withIsolatedLanguageStore { store, defaults in
            store.setLanguage(.english)
            #expect(store.language == .english)
            #expect(defaults.persistentDomain(forName: store.domainName)?[AppLanguageStore.key] as? [String] == ["en"])

            store.setLanguage(.simplifiedChinese)
            #expect(AppLanguageStore(defaults: defaults, domainName: store.domainName).language == .simplifiedChinese)
        }
    }

    @Test("改回跟随系统时移除覆盖")
    func removesOverride() {
        withIsolatedLanguageStore { store, defaults in
            store.setLanguage(.simplifiedChinese)
            store.setLanguage(.system)
            #expect(store.language == .system)
            #expect(defaults.persistentDomain(forName: store.domainName)?[AppLanguageStore.key] == nil)
        }
    }

    @Test("偏好域里的值损坏时视为跟随系统")
    func toleratesCorruptValue() {
        withIsolatedLanguageStore { store, defaults in
            defaults.set("zh-Hans", forKey: AppLanguageStore.key)
            #expect(store.language == .system)
        }
    }

    /// 独立的 suite 充当应用偏好域（store 需要知道域名，所以不复用 withIsolatedDefaults）
    private func withIsolatedLanguageStore(_ body: (AppLanguageStore, UserDefaults) -> Void) {
        let suiteName = "cubby-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("无法创建独立的 UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(AppLanguageStore(defaults: defaults, domainName: suiteName), defaults)
    }
}
