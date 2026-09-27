import CubbyCore
import Foundation

/// 截图翻译界面的文案（英文 key，zh-Hans 在 String Catalog 中；措辞见 docs/TRANSLATION-DESIGN.md §2）
enum TranslationBarText {
    // MARK: - 工具栏

    static var toolbarTranslate: String {
        String(localized: "Translate (⇧⌘T)", comment: "Screenshot toolbar tooltip")
    }

    static var toolbarShowOriginal: String {
        String(localized: "Show Original (⇧⌘T)", comment: "Screenshot toolbar tooltip when a translation is shown")
    }

    static var toolbarShowTranslation: String {
        String(localized: "Show Translation (⇧⌘T)", comment: "Screenshot toolbar tooltip when the original is shown")
    }

    static var toolbarLabel: String {
        String(localized: "Translate", comment: "Screenshot toolbar button accessibility label")
    }

    // MARK: - 进行中

    static var recognizing: String {
        String(localized: "Recognizing text…", comment: "Screenshot translation bar status")
    }

    static var preparing: String {
        String(localized: "Translating…", comment: "Screenshot translation bar status before the first block")
    }

    static func progress(_ done: Int, _ total: Int) -> String {
        String(
            localized: "Translating \(done)/\(total)",
            comment: "Screenshot translation bar status. %1$lld = translated blocks, %2$lld = all blocks")
    }

    static var escToCancel: String {
        String(localized: "Esc to cancel translation", comment: "Screenshot translation bar hint while translating")
    }

    // MARK: - 结果

    static var original: String {
        String(localized: "Original", comment: "Screenshot translation bar: show the original text (export version)")
    }

    static var translation: String {
        String(localized: "Translated", comment: "Screenshot translation bar: show the translation (export version)")
    }

    static var exportVersionLabel: String {
        String(localized: "Export version", comment: "Accessibility label of the original / translation switch")
    }

    static var exportVersionHelp: String {
        String(
            localized: "Decides which version Done, Save and Pin export",
            comment: "Tooltip of the original / translation switch in the screenshot translation bar")
    }

    static var compare: String {
        String(localized: "Compare", comment: "Screenshot translation bar: wipe comparison toggle")
    }

    static var compareHelp: String {
        String(
            localized: "Drag the divider to compare the original and the translation (view only, not exported)",
            comment: "Tooltip of the wipe comparison toggle")
    }

    static var copyTranslation: String {
        String(localized: "Copy Translation", comment: "Screenshot translation bar button")
    }

    static var copyTranslationHelp: String {
        String(
            localized: "Copy all translated text in reading order",
            comment: "Tooltip of the copy translation button")
    }

    static var holdSpace: String {
        String(localized: "Hold Space to see the original", comment: "Screenshot translation bar hint")
    }

    static var copiedTranslation: String {
        String(localized: "Copied translation", comment: "HUD after copying the screenshot translation")
    }

    static var partial: String {
        String(localized: "Some text wasn't translated", comment: "Screenshot translation bar after a partial failure")
    }

    static var selectionChanged: String {
        String(
            localized: "Selection changed",
            comment: "Screenshot translation bar when the selection now includes text that wasn't translated")
    }

    static var translateAgain: String {
        String(localized: "Translate Again", comment: "Screenshot translation bar button after the selection changed")
    }

    // MARK: - 失败

    static var retry: String {
        String(localized: "Retry", comment: "Screenshot translation bar button")
    }

    static var openSettings: String {
        String(localized: "Open Settings", comment: "Screenshot translation bar button for setup problems")
    }

    static var downloadLanguages: String {
        String(localized: "Download Languages", comment: "Screenshot translation bar button")
    }

    static var noText: String {
        String(localized: "No text to translate", comment: "Screenshot translation bar when nothing can be translated")
    }

    static func chooseTarget(source: String?) -> String {
        guard let source else {
            return String(
                localized: "Choose a target language",
                comment: "Screenshot translation bar when no target language could be picked automatically")
        }
        return String(
            localized: "The text is already in \(source). Choose a target language",
            comment: "Screenshot translation bar. %@ = language of the text")
    }

    static func message(for failure: TranslationFailure, run: TranslationRun, names: TranslationLanguageNames)
        -> String
    {
        switch failure {
        case .notConfigured:
            String(localized: "Translation isn't set up", comment: "Screenshot translation failure")
        case .unauthorized:
            String(localized: "The API key is invalid or not allowed", comment: "Screenshot translation failure")
        case .rateLimited:
            String(localized: "Too many requests or no quota left", comment: "Screenshot translation failure")
        case .network:
            networkMessage(engine: run.engine?.name)
        case .server(let status):
            String(
                localized: "The service is temporarily unavailable (\(status))",
                comment: "Screenshot translation failure. %lld = HTTP status code")
        case .unsupportedLanguages:
            String(localized: "This language pair isn't supported", comment: "Screenshot translation failure")
        case .languageNotInstalled:
            String(
                localized: "Download \(names.pair(source: run.languages?.source, target: run.languages?.target)) first",
                comment: "Screenshot translation failure. %@ = language pair, for example English → Chinese")
        case .invalidResponse:
            String(localized: "Couldn't read the translation", comment: "Screenshot translation failure")
        }
    }

    private static func networkMessage(engine: String?) -> String {
        guard let engine else {
            return String(
                localized: "Can't connect to the translation service", comment: "Screenshot translation failure")
        }
        return String(
            localized: "Can't connect to \(engine)", comment: "Screenshot translation failure. %@ = service name")
    }

    // MARK: - 语言与引擎

    static var automatic: String {
        String(localized: "Automatic", comment: "Screenshot translation bar when the languages are not known yet")
    }

    static var languageMenuHelp: String {
        String(
            localized: "Target language (saved for next time)",
            comment: "Tooltip of the language menu in the screenshot translation bar")
    }

    static func onDevice(_ engine: String) -> String {
        String(
            localized: "\(engine) translates on this Mac",
            comment: "Tooltip of the engine chip for an on-device engine. %@ = engine name")
    }

    static func offDevice(_ engine: String) -> String {
        String(
            localized: "Recognized text is sent to \(engine). Images are not uploaded",
            comment: "Tooltip of the engine chip for a cloud engine. %@ = engine name")
    }

    // MARK: - 卷帘、按住空格、悬停

    static var wipeLabel: String {
        String(
            localized: "Wipe position: original on the left, translation on the right",
            comment: "Accessibility label of the wipe divider")
    }

    static var peekChip: String {
        String(
            localized: "Original · Release Space for the translation",
            comment: "Chip shown while holding Space over a translated screenshot")
    }

    static var bubbleTitle: String {
        String(localized: "Original", comment: "Title of the bubble that shows a block's original text")
    }
}
