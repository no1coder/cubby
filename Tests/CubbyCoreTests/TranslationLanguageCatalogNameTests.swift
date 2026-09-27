import Foundation
import Testing
@testable import CubbyCore

@Suite("TranslationLanguageCatalog 语言名（设置页与翻译卡共用）")
struct TranslationLanguageCatalogNameTests {
    @Test("本名首字母按该语言大写")
    func nativeNameIsCapitalized() {
        #expect(TranslationLanguageCatalog.nativeName(of: "fr") == "Français")
        #expect(TranslationLanguageCatalog.nativeName(of: "de") == "Deutsch")
        #expect(TranslationLanguageCatalog.nativeName(of: "ja") == "日本語")
    }

    @Test("无法识别的代码原样返回")
    func unknownCodeFallsBack() {
        #expect(TranslationLanguageCatalog.localizedName(of: "", locale: Locale(identifier: "en")) == "")
    }

    @Test("默认按应用的界面语言显示")
    func defaultsToInterfaceLanguage() {
        let expected = TranslationLanguageCatalog.interfaceLocale.localizedString(forIdentifier: "ja")
        #expect(TranslationLanguageCatalog.localizedName(of: "ja") == expected)
    }
}
