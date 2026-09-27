import Foundation

/// 界面语言：跟随系统，或固定为某种已本地化的语言。
/// 沿用 macOS「按 App 设置语言」的机制——应用偏好域里的 AppleLanguages 键，因此与
/// 「系统设置 › 通用 › 语言与地区 › 应用程序」双向一致；系统在进程启动时读取，改动在重新打开后生效
public enum AppLanguage: Hashable, Sendable, CaseIterable {
    case system
    case english
    case simplifiedChinese

    /// 应用提供的本地化（与 Info.plist 的 CFBundleLocalizations 一致），源语言在前：系统在其余语言都不匹配时回退到它
    public static let supportedLocalizations = allCases.compactMap(\.localization)

    /// 对应的本地化标识；跟随系统时为 nil
    public var localization: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    /// 写入应用偏好域 AppleLanguages 的值；nil 表示移除覆盖
    public var appleLanguages: [String]? {
        localization.map { [$0] }
    }

    /// 由应用偏好域里的 AppleLanguages 推断。未设置或为空时跟随系统；
    /// 有覆盖时按应用实际会显示的语言归类（例如 zh-CN 归为简体中文，不支持的语言归为英文），选单与界面保持一致
    public init(appleLanguages: [String]?) {
        guard let appleLanguages, !appleLanguages.isEmpty else {
            self = .system
            return
        }
        self = Self.fixed(localization: Self.resolve(appleLanguages))
    }

    /// 选中这一项后应用会显示的界面语言；systemPreferences 为系统（全局域）的首选语言列表
    public func resolvedLocalization(systemPreferences: [String]) -> String {
        localization ?? Self.resolve(systemPreferences)
    }

    /// 按系统的匹配规则（含地区、脚本与旧式标识）从支持的本地化中选出一种；都不匹配时为源语言
    private static func resolve(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: supportedLocalizations, forPreferences: preferences).first
            ?? supportedLocalizations[0]
    }

    private static func fixed(localization: String) -> AppLanguage {
        allCases.first { $0.localization == localization } ?? .english
    }
}

/// 读写应用偏好域里的界面语言覆盖。只看本应用的持久域：普通读取会回退到全局域，
/// 而全局域里总有系统语言，那样就分不清「跟随系统」与「固定为某种语言」
@MainActor
public struct AppLanguageStore {
    public static let key = "AppleLanguages"

    public let domainName: String
    private let defaults: UserDefaults

    /// domainName 为偏好域名称：UserDefaults.standard 对应 bundle id，没有 bundle 的调试构建对应进程名
    public init(
        defaults: UserDefaults = .standard,
        domainName: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    ) {
        self.defaults = defaults
        self.domainName = domainName
    }

    /// 当前保存的选择（值损坏时视为跟随系统）
    public var language: AppLanguage {
        AppLanguage(appleLanguages: defaults.persistentDomain(forName: domainName)?[Self.key] as? [String])
    }

    public func setLanguage(_ language: AppLanguage) {
        if let languages = language.appleLanguages {
            defaults.set(languages, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
