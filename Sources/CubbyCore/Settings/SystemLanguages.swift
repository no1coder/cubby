import Foundation

/// 系统的首选语言列表（系统设置 › 通用 › 语言与地区），不受 Cubby 界面语言覆盖的影响。
/// Locale.preferredLanguages 会先读应用偏好域：界面语言改成英文后它也变成英文，
/// 翻译的「自动」目标语言因此必须从这里取——界面语言只决定 Cubby 自己的文字
public enum SystemLanguages {
    private static let key = "AppleLanguages"

    public static var preferred: [String] {
        preferred(
            globalDomain: UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain),
            fallback: Locale.preferredLanguages)
    }

    /// 全局域没有可用的列表时（缺失、为空或类型不对）回退到 fallback
    static func preferred(globalDomain: [String: Any]?, fallback: [String]) -> [String] {
        guard let languages = globalDomain?[key] as? [String], !languages.isEmpty else { return fallback }
        return languages
    }
}
