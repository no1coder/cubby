import Foundation
import NaturalLanguage

/// 由译文推断排版语言（kCTLanguageAttributeName）：只影响 CJK 字形（简 / 繁 / 日）与韩文；拉丁文字返回 nil
enum TranslationLanguageGuess {
    static func language(of text: String) -> String? {
        let scalars = text.unicodeScalars
        if scalars.contains(where: TextScript.isKana) { return "ja" }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return "ko" }
        guard scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .traditionalChinese ? "zh-Hant" : "zh-Hans"
    }
}
