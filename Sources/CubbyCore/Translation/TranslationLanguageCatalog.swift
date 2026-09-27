import Foundation

/// 截图翻译的语言表与 BCP-47 规范化（docs/TRANSLATION-DESIGN.md §3.4）
public enum TranslationLanguageCatalog {
    /// 语言选单候选的规范顺序：简体中文、繁体中文、英语、日语、韩语、法语、德语、西班牙语、
    /// 葡萄牙语、意大利语、俄语、越南语、泰语、印尼语、阿拉伯语
    public static let supported = [
        "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "vi", "th", "id", "ar",
    ]

    /// 语言选单的显示顺序：用户的首选语言（按系统设置的先后）排在最前，其余保持规范顺序
    public static func selectable(preferred: [String]) -> [String] {
        let leading = preferred.compactMap(normalize).reduce(into: [String]()) { result, code in
            if supported.contains(code), !result.contains(code) { result.append(code) }
        }
        return leading + supported.filter { !leading.contains($0) }
    }

    /// 规范化为「语言[-文字]」：中文按文字区分简 / 繁（zh-CN → zh-Hans，zh-TW / zh-HK → zh-Hant，
    /// 只写 zh 时按简体）；其他语言只保留语言代码（en-US → en，pt-BR → pt）。无法识别时返回 nil
    public static func normalize(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-")
        guard !trimmed.isEmpty else { return nil }
        let language = Locale.Language(identifier: trimmed)
        guard let code = language.languageCode?.identifier.lowercased(), code != "und" else { return nil }
        guard code == "zh" else { return code }
        // 未显式写出文字时按地区推断（maximalIdentifier：zh-TW → zh-Hant-TW，zh → zh-Hans-CN）
        let script = language.script ?? Locale.Language(identifier: language.maximalIdentifier).script
        return script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
    }

    /// 语言的本名（例如 ja →「日本語」、fr →「Français」），用于语言选单：用户总能认出自己的语言。
    /// 首字母按该语言的规则大写（与系统语言菜单一致）
    public static func nativeName(of code: String) -> String {
        let locale = Locale(identifier: code)
        guard let name = locale.localizedString(forIdentifier: code) else { return code }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// 按界面语言显示的语言名（例如界面为中文时 ja →「日语」），用于说明文字；
    /// 默认用应用实际显示的界面语言（而不是系统地区），设置页与翻译卡一致
    public static func localizedName(of code: String, locale: Locale = interfaceLocale) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }

    /// 应用实际显示的界面语言（本地化资源里与用户首选语言最匹配的一种）
    public static var interfaceLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
