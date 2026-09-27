import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 剪贴板条目翻译设置")
@MainActor
struct AppSettingsClipTranslationTests {
    @Test("默认：不自动翻译、卡片上不显示译文、没有按应用记住的语言")
    func defaults() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(!settings.translatesClipsOnCopy)
            #expect(!settings.showsTranslationOnCards)
            #expect(settings.clipTranslationTargets.languages.isEmpty)
            #expect(settings.clipTranslationTarget(for: "com.tinyspeck.slackmacgap") == nil)
        }
    }

    @Test("开关与按应用记住的语言写入 UserDefaults，新实例读回")
    func persists() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.showsTranslationOnCards = true
            settings.translatesClipsOnCopy = true
            settings.rememberClipTranslationTarget("en-US", for: "com.tinyspeck.slackmacgap")
            settings.rememberClipTranslationTarget("ja", for: "com.apple.mail")

            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.translatesClipsOnCopy)
            #expect(reloaded.showsTranslationOnCards)
            #expect(reloaded.clipTranslationTarget(for: "com.tinyspeck.slackmacgap") == "en")
            #expect(reloaded.clipTranslationTarget(for: "com.apple.mail") == "ja")
            #expect(defaults.bool(forKey: "translatesClipsOnCopy"))
            #expect(defaults.bool(forKey: "showsTranslationOnCards"))
        }
    }

    @Test("忘记某个应用；无法识别的语言视为忘记；存储里的无效项与非字符串值读取时丢弃")
    func forgetsAndSanitizes() {
        withIsolatedDefaults { defaults in
            defaults.set(
                ["com.apple.mail": "fr", "": "ja", "com.apple.Notes": 3, "com.apple.Safari": "und"],
                forKey: "clipTranslationTargetsByApp")
            let settings = AppSettings(defaults: defaults)
            #expect(settings.clipTranslationTargets.languages == ["com.apple.mail": "fr"])

            settings.rememberClipTranslationTarget("de", for: "com.apple.Notes")
            settings.rememberClipTranslationTarget(nil, for: "com.apple.mail")
            settings.rememberClipTranslationTarget("und", for: "com.apple.Notes")
            #expect(settings.clipTranslationTargets.languages.isEmpty)
            #expect(AppSettings(defaults: defaults).clipTranslationTargets.languages.isEmpty)
        }
    }

    @Test("打开自动翻译时一并打开「在卡片上显示译文」；关闭时不动它")
    func autoTranslateTurnsOnCardTranslations() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.setTranslatesClipsOnCopy(true)
            #expect(settings.translatesClipsOnCopy && settings.showsTranslationOnCards)
            settings.setTranslatesClipsOnCopy(false)
            #expect(!settings.translatesClipsOnCopy)
            #expect(settings.showsTranslationOnCards)
        }
    }
}
