import CubbyCore
import Foundation

// 不支持、失败、密钥、取消等状态的文案（卡片状态页、⌥↩ 行内提示、按住 ⌥ 预览共用）

extension TranslationCopy {
    // MARK: - 不支持

    static func unsupportedTitle(_ reason: ClipTranslationUnsupportedReason) -> String {
        switch reason {
        case .code: String(localized: "Code snippets aren't translated", comment: "Translation unsupported")
        case .link: String(localized: "Links can't be translated", comment: "Translation unsupported")
        case .color: String(localized: "Colors can't be translated", comment: "Translation unsupported")
        case .file: String(localized: "Files can't be translated", comment: "Translation unsupported")
        case .noText: String(localized: "No text to translate", comment: "Translation unsupported")
        case .tooLong: String(localized: "Text is too long to translate", comment: "Translation unsupported")
        case .imageTooLarge: String(localized: "Image is too large to translate", comment: "Translation unsupported")
        case .unavailable: String(localized: "Translation needs macOS 26 or later", comment: "Translation unsupported")
        }
    }

    static var unsupportedDetail: String {
        String(
            localized:
                "Translation works on text, rich text and text in images. Code, links, colors and files stay as they are.",
            comment: "Translation card: explanation below an unsupported item")
    }

    static var noTextDetail: String {
        String(
            localized: "Nothing in this item needs translating.",
            comment: "Translation card: explanation when an item (for example an image) has no text to translate")
    }

    // MARK: - 失败（卡片状态页）

    /// 状态页的标题与说明
    static func failure(_ failure: TranslationFailure, plan: ClipTranslationPlan?) -> (title: String, detail: String) {
        let engine =
            plan.map { shortEngineName($0.engineName) }
            ?? String(localized: "The service", comment: "Engine name when unknown")
        switch failure {
        case .notConfigured:
            return (
                String(localized: "No translation service set up", comment: "Translation failure title"),
                String(
                    localized:
                        "Set one up in Settings › Translation. System Translation works on this Mac, free and offline.",
                    comment: "Translation failure detail")
            )
        case .unauthorized:
            return (
                String(localized: "\(engine) rejected the API key", comment: "Translation failure title"),
                String(
                    localized: "The key may have expired or been mistyped. Nothing was translated or cached.",
                    comment: "Translation failure detail")
            )
        case .rateLimited:
            return (
                String(localized: "\(engine) is limiting requests", comment: "Translation failure title"),
                String(localized: "Wait a moment, then try again.", comment: "Translation failure detail")
            )
        case .network:
            return (
                String(localized: "Can't reach \(plan?.host ?? engine)", comment: "Translation failure title"),
                String(
                    localized: "Check your network or proxy settings. Nothing was cached.",
                    comment: "Translation failure detail")
            )
        case .server(let status):
            return (
                String(localized: "\(engine) returned an error (\(status))", comment: "Translation failure title"),
                String(localized: "Try again in a moment.", comment: "Translation failure detail")
            )
        default:
            return otherFailure(failure, plan: plan)
        }
    }

    private static func otherFailure(
        _ failure: TranslationFailure, plan: ClipTranslationPlan?
    ) -> (title: String, detail: String) {
        switch failure {
        case .unsupportedLanguages:
            return (
                String(localized: "This language pair isn't supported", comment: "Translation failure title"),
                String(localized: "Choose a different target language above.", comment: "Translation failure detail")
            )
        case .languageNotInstalled:
            return (
                String(
                    localized: "Download the “\(pairName(plan))” languages first", comment: "Translation failure title"),
                String(
                    localized:
                        "System Translation runs on this Mac. A language needs a download the first time; after that it works offline.",
                    comment: "Translation failure detail")
            )
        default:
            return (
                String(localized: "Couldn't read the translation", comment: "Translation failure title"),
                String(
                    localized: "The service returned something unexpected. Nothing was cached.",
                    comment: "Translation failure detail")
            )
        }
    }

    /// 「英语 → 简体中文」
    static func pairName(_ plan: ClipTranslationPlan?) -> String {
        let source = plan?.detectedSource.map(languageName) ?? autoDetect
        let target = plan.map { languageName($0.languages.target) } ?? ""
        return "\(source) → \(target)"
    }

    static func resolveAction(_ failure: TranslationFailure) -> String {
        failure == .languageNotInstalled
            ? String(localized: "Download Languages", comment: "Button: download translation languages")
            : String(localized: "Go to Settings", comment: "Button: open translation settings")
    }

    static var retry: String {
        String(localized: "Retry", comment: "Button")
    }

    static var translateAnyway: String {
        String(localized: "Translate Anyway", comment: "Button: send text that looks like a secret")
    }

    // MARK: - 密钥、已是目标语言、取消

    static func secretTitle() -> String {
        String(localized: "Looks like it contains a secret, not sent", comment: "Translation card state title")
    }

    static func secretDetail(_ plan: ClipTranslationPlan?) -> String {
        let engine = plan.map { shortEngineName($0.engineName) } ?? ""
        return String(
            localized:
                "Translating with \(engine) would send the whole text to \(plan?.host ?? engine). Nothing was sent.",
            comment: "Translation card: why a suspected secret was not sent")
    }

    static func alreadyTargetTitle(_ language: String) -> String {
        String(localized: "Already in \(languageName(language))", comment: "Translation card state title")
    }

    static var alreadyTargetDetail: String {
        String(
            localized: "Choose a different target language from the menu above.",
            comment: "Translation card state detail")
    }

    static var cancelledTitle: String {
        String(localized: "Translation canceled", comment: "Translation card state title and footer toast")
    }

    static var cancelledDetail: String {
        String(localized: "Nothing was cached.", comment: "Translation card state detail after canceling")
    }

    static var peekSecretNote: String {
        String(
            localized: "Looks like a secret, not sent · ⌘T to review",
            comment: "Hold-Option translation preview: suspected secret")
    }

    // MARK: - ⌥↩ 行内提示（一行，简短）

    static func inlineIssue(_ issue: InlineTranslationIssue, plan: ClipTranslationPlan?) -> String {
        switch issue {
        case .failure(.notConfigured):
            String(localized: "No translation service set up", comment: "Translation failure title")
        case .failure(.languageNotInstalled):
            String(localized: "Languages not downloaded", comment: "Inline translation error on a card")
        case .failure(.network):
            String(
                localized: "Can't reach \(plan?.host ?? plan.map { shortEngineName($0.engineName) } ?? "")",
                comment: "Translation failure title")
        case .failure(let failure):
            self.failure(failure, plan: plan).title
        case .timedOut:
            String(
                localized: "Translation timed out · ⌘T opens the card",
                comment: "Inline translation error on a card")
        case .needsSecretConfirmation(let engine):
            String(
                localized: "Looks like a secret, not sent to \(engine)",
                comment: "Inline translation error on a card")
        case .alreadyTarget(let language):
            String(
                localized: "Already in \(languageName(language)) · ⌘T to choose a language",
                comment: "Inline translation note on a card")
        case .pasteFailed:
            String(localized: "Couldn't paste the translation", comment: "Inline translation error on a card")
        case .nothingToTranslate:
            unsupportedTitle(.noText)
        }
    }

    static func inlineProgress(done: Int, total: Int) -> String {
        total > 0
            ? String(
                localized: "Translating \(done)/\(total) · esc to cancel",
                comment: "Inline progress on a card after ⌥↩: segments done / total")
            : String(localized: "Translating… · esc to cancel", comment: "Inline progress on a card after ⌥↩")
    }
}
