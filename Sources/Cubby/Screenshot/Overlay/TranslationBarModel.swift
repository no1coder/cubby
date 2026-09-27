import CubbyCore
import Foundation

/// 翻译条上的操作；覆盖层把它们翻译成会话事件或委托调用
enum TranslationBarAction: Equatable {
    case showTranslation(Bool)
    case setWipe(Bool)
    case copy
    case retry
    case retranslateSelection
    /// 「去设置」「下载语言」：暂停覆盖层，交给 provider 去解决
    case resolve(TranslationFailure)
    case chooseLanguage(String)
}

/// 翻译条的显示状态（值类型，变化时才刷新 SwiftUI）
struct TranslationBarModel: Equatable {
    /// 语言选单里的一项
    struct LanguageOption: Equatable, Identifiable {
        let code: String
        /// 该语言自己的写法（English、日本語、简体中文）
        let name: String
        let isSelected: Bool
        /// 与原文相同的语言置灰
        let isDisabled: Bool

        var id: String { code }
    }

    /// 条内附带的一句提示与按钮（部分未翻译、选区已变化）
    struct Notice: Equatable {
        let message: String
        let actionTitle: String
        let action: TranslationBarAction
    }

    enum Content: Equatable {
        /// 识别 / 翻译进行中：状态文字（Esc 取消）
        case progress(String)
        /// 失败 / 无文字 / 待选语言：原因 + 可选的操作按钮
        case failure(message: String, actionTitle: String?, action: TranslationBarAction?)
        /// 已有结果：原文 | 译文、卷帘对比、复制译文；notice 代替「按住空格看原文」
        case result(showsTranslation: Bool, isWipeEnabled: Bool, notice: Notice?)
    }

    /// 「英语 → 简体中文」
    let languagePair: String
    let languages: [LanguageOption]
    let engine: TranslationEngineBadge?
    let content: Content
}

extension TranslationBarModel {
    /// 由会话与翻译设置派生；没有翻译时为 nil（不显示翻译条）。
    /// names / endonyms：语言名与语言选单各项的自称（每次鼠标移动都会重算模型，Locale 由调用方创建并缓存）
    @MainActor
    static func make(
        for session: ScreenshotSession, provider: any TranslationProviding, names: TranslationLanguageNames,
        endonyms: [String: String]
    ) -> TranslationBarModel? {
        guard let run = session.translation else { return nil }
        let target = run.languages?.target ?? provider.targetLanguage
        let options = provider.selectableLanguages.map { code in
            LanguageOption(
                code: code, name: endonyms[code] ?? names.endonym(code), isSelected: code == target,
                isDisabled: run.languages?.source.map { TranslationLanguageNames.sameLanguage($0, code) } ?? false)
        }
        return TranslationBarModel(
            languagePair: names.pair(source: run.languages?.source, target: target), languages: options,
            engine: run.engine, content: content(for: run, session: session, provider: provider, names: names))
    }

    @MainActor
    private static func content(
        for run: TranslationRun, session: ScreenshotSession, provider: any TranslationProviding,
        names: TranslationLanguageNames
    ) -> Content {
        switch run.status {
        case .recognizing:
            return .progress(TranslationBarText.recognizing)
        case .translating(let done, let total):
            return .progress(total == 0 ? TranslationBarText.preparing : TranslationBarText.progress(done, total))
        case .ready, .partial:
            return .result(
                showsTranslation: session.showsTranslation, isWipeEnabled: session.isWipeEnabled,
                notice: notice(for: run, session: session))
        case .failed(let failure):
            let message = TranslationBarText.message(for: failure, run: run, names: names)
            let action = failureAction(failure, provider: provider)
            return .failure(message: message, actionTitle: action?.title, action: action?.action)
        case .noText:
            return .failure(message: TranslationBarText.noText, actionTitle: nil, action: nil)
        case .needsTargetLanguage:
            let source = run.languages?.source.map(names.name)
            return .failure(message: TranslationBarText.chooseTarget(source: source), actionTitle: nil, action: nil)
        }
    }

    /// 选区超出识别区域优先提示重译；否则部分未翻译时提示重试
    private static func notice(for run: TranslationRun, session: ScreenshotSession) -> Notice? {
        if session.isTranslationStale {
            return Notice(
                message: TranslationBarText.selectionChanged, actionTitle: TranslationBarText.translateAgain,
                action: .retranslateSelection)
        }
        guard case .partial = run.status else { return nil }
        return Notice(message: TranslationBarText.partial, actionTitle: TranslationBarText.retry, action: .retry)
    }

    /// 可以去某处解决的失败给「去设置」「下载语言」；语言组合不支持靠语言选单；其余给「重试」
    @MainActor
    private static func failureAction(_ failure: TranslationFailure, provider: any TranslationProviding)
        -> (title: String, action: TranslationBarAction)?
    {
        if provider.canResolve(failure) {
            let title =
                failure == .languageNotInstalled
                ? TranslationBarText.downloadLanguages : TranslationBarText.openSettings
            return (title, .resolve(failure))
        }
        return failure == .unsupportedLanguages ? nil : (TranslationBarText.retry, .retry)
    }
}

/// 语言的显示名
struct TranslationLanguageNames {
    /// 界面语言（跟随 App 实际使用的本地化）
    private let interface = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    /// 用界面语言写的名称（英语、简体中文）
    func name(_ code: String) -> String {
        interface.localizedString(forIdentifier: code) ?? code
    }

    /// 该语言自己的写法（English、日本語），用于语言选单
    func endonym(_ code: String) -> String {
        Locale(identifier: code).localizedString(forIdentifier: code) ?? name(code)
    }

    /// 「英语 → 简体中文」；原文语言未知时只写目标；都未知时为「自动」
    func pair(source: String?, target: String?) -> String {
        switch (source, target) {
        case (let source?, let target?): "\(name(source)) \u{2192} \(name(target))"
        case (nil, let target?): name(target)
        default: TranslationBarText.automatic
        }
    }

    /// 两个 BCP-47 标识是否同一种语言（zh-Hans / zh-Hant 按文字区分，其余只比语言部分）
    static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let key = { (code: String) -> String in
            let parts = code.lowercased().split(separator: "-")
            guard let language = parts.first else { return code }
            return language == "zh" ? parts.prefix(2).joined(separator: "-") : String(language)
        }
        return key(lhs) == key(rhs)
    }
}
