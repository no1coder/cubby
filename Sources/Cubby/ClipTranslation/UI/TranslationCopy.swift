import CubbyCore
import Foundation

/// 翻译界面的文案（英文键 + String Catalog）；失败与不支持的说明见 TranslationCopy+Issues.swift
enum TranslationCopy {
    // MARK: - 语言

    /// 界面语言下的语言名（「英语」「简体中文」）：与设置页同一张语言表
    static func languageName(_ code: String) -> String {
        TranslationLanguageCatalog.localizedName(of: code)
    }

    /// 语言的自称（语言选单：English、简体中文、日本語）
    static func nativeLanguageName(_ code: String) -> String {
        TranslationLanguageCatalog.nativeName(of: code)
    }

    /// 中日文界面里夹在汉字之间的拉丁文名称两侧加空格（「已用 DeepSeek 翻译并粘贴」），中文名称不加
    static func spacedName(_ name: String) -> String {
        let interface = TranslationLanguageCatalog.interfaceLocale.identifier
        guard interface.hasPrefix("zh") || interface.hasPrefix("ja") else { return name }
        let isLatin: (Character?) -> Bool = { $0.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false }
        return (isLatin(name.first) ? " " : "") + name + (isLatin(name.last) ? " " : "")
    }

    static var autoDetect: String {
        String(localized: "Auto-detect", comment: "Translation card language pill: source language is unknown")
    }

    static var autoDetectedSuffix: String {
        String(
            localized: "(auto-detected)",
            comment:
                "Translation card language pill, after the detected source language, e.g. “English (auto-detected)”")
    }

    // MARK: - 引擎

    /// 引擎的简称：大模型的显示名是「服务商 · 模型」，徽标、HUD、状态里只用服务商（「已用 DeepSeek 翻译并粘贴」）；
    /// 完整名称留在悬停说明与引擎选单里
    static func shortEngineName(_ name: String) -> String {
        name.components(separatedBy: " · ").first ?? name
    }

    /// HUD 与底栏里的引擎名：本机引擎注明「本机」
    static func engineLabel(_ name: String, isOnDevice: Bool) -> String {
        isOnDevice
            ? String(
                localized: "\(name) (on this Mac)",
                comment: "Engine name for an on-device engine, e.g. System Translation (on this Mac)")
            : name
    }

    static func engineTooltip(_ plan: ClipTranslationPlan) -> String {
        plan.sendsTextOffDevice
            ? String(
                localized: "\(plan.engineName): text is sent to \(plan.host ?? plan.engineName) · click for options",
                comment: "Tooltip of the engine chip on the translation card for a cloud engine")
            : String(
                localized: "\(plan.engineName): translated on this Mac, offline · click for options",
                comment: "Tooltip of the engine chip on the translation card for an on-device engine")
    }

    static func engineMenuHeader(_ plan: ClipTranslationPlan) -> String {
        plan.sendsTextOffDevice
            ? String(
                localized: "\(plan.engineName) · sends text to \(plan.host ?? plan.engineName)",
                comment: "Engine menu header for a cloud engine")
            : String(
                localized: "\(plan.engineName) · on this Mac", comment: "Engine menu header for an on-device engine")
    }

    static var translationSettings: String {
        String(localized: "Translation Settings…", comment: "Engine menu item on the translation card")
    }

    // MARK: - 卡片头部

    static var cardTitle: String {
        String(localized: "Translate", comment: "Context menu item and title of the translation card")
    }

    static var targetLanguageTooltip: String {
        String(localized: "Target language", comment: "Tooltip of the language pill on the translation card")
    }

    static func swapTooltip(isImage: Bool, canSwap: Bool, blockedBySecret: Bool = false) -> String {
        if isImage {
            return String(localized: "Swap (not available for images)", comment: "Tooltip of the swap button")
        }
        if blockedBySecret { return swapRefusedForSecret }
        return canSwap
            ? String(localized: "Swap", comment: "Tooltip of the swap button: translate the translation back")
            : String(localized: "Swap (after the translation finishes)", comment: "Tooltip of the swap button")
    }

    static var swapRefusedForSecret: String {
        String(
            localized: "Swap isn't available for text that looks like a secret with a cloud engine",
            comment: "Swap button tooltip and card flash: nothing is sent")
    }

    static var sourceLanguageMenuNote: String {
        String(
            localized: "Source language",
            comment: "Language menu: shown next to the language the text is already in")
    }

    static func rememberTargetMenuItem(app: String) -> String {
        String(
            localized: "Always translate to this when pasting into \(app)",
            comment: "Language menu checkbox. %@ = the app the panel pastes into")
    }

    static func rememberFlash(target: String?, app: PasteTarget?) -> TranslationFlash {
        let appName = app?.name ?? ""
        guard let target else {
            return TranslationFlash(
                message: String(
                    localized: "Target language follows the system again",
                    comment: "Flash after turning off the per-app target language"),
                isWarning: false)
        }
        return TranslationFlash(
            message: String(
                localized: "Pasting into \(appName) will always translate to \(languageName(target))",
                comment: "Flash after remembering a target language for the paste target app"),
            isWarning: false)
    }

    // MARK: - 视图切换

    static func modeTitle(_ mode: TranslationViewMode) -> String {
        switch mode {
        case .translation: String(localized: "Translated", comment: "Translation card view: translation only")
        case .sideBySide:
            String(
                localized: "card.mode.compare", defaultValue: "Compare",
                comment: "Translation card view: original and translation side by side. Keep it short.")
        case .original: String(localized: "Original", comment: "Translation card view: original only")
        }
    }

    static func sideBySideTooltip(isImage: Bool) -> String {
        isImage
            ? String(
                localized: "Wipe: drag the divider to compare",
                comment: "Tooltip of the Side by Side view for images")
            : String(
                localized: "Paragraph by paragraph: hover to highlight its original",
                comment: "Tooltip of the Side by Side view for text")
    }

    static var modePickerLabel: String {
        String(localized: "View (← / → to switch)", comment: "Accessibility label of the translation card view picker")
    }

    // MARK: - 底栏按钮与提示

    /// 卡片底栏的三个按钮：英文要短（440pt 宽的卡片里与统计并排），中文沿用原型「复制译文 / 存为新条目 / 粘贴译文」
    static var copyButton: String {
        String(
            localized: "card.copyButton", defaultValue: "Copy",
            comment: "Translation card button: copy the translation. Keep it short.")
    }

    static var saveButton: String {
        String(
            localized: "card.saveButton", defaultValue: "Save",
            comment: "Translation card button: save the translation as a new history item. Keep it short.")
    }

    static var pasteButton: String {
        String(
            localized: "card.pasteButton", defaultValue: "Paste",
            comment: "Translation card primary button: paste the translation. Keep it short.")
    }

    static var pasteWhenDoneButton: String {
        String(
            localized: "card.pasteWhenDoneButton", defaultValue: "Paste When Done",
            comment: "Translation card primary button while translating. Keep it short.")
    }

    /// 右键菜单「复制译文」
    static var copyMenuItem: String {
        String(localized: "Copy Translation", comment: "Context menu item: copy the cached translation")
    }

    static var copyTooltip: String {
        String(localized: "Copy Translation (⌘C)", comment: "Tooltip")
    }

    static var saveTooltip: String {
        String(localized: "Save as New Item (⌘S)", comment: "Tooltip")
    }

    static var pausedTooltip: String {
        String(localized: "Recording is paused", comment: "Tooltip of Save as New Item while recording is paused")
    }

    static func pasteTooltip(app: String?) -> String {
        guard let app else {
            return String(localized: "Copy the translation (↩) · plain text ⇧↩", comment: "Tooltip")
        }
        return String(
            localized: "Paste the translation into \(app) (↩) · plain text ⇧↩",
            comment: "Tooltip of Paste Translation. %@ = target app")
    }

    static func copiedFlash(isImage: Bool) -> String {
        isImage
            ? String(localized: "Copied the translated image", comment: "Flash on the translation card")
            : String(localized: "Copied the translation", comment: "Flash on the translation card")
    }

    static var copyFailed: String {
        String(localized: "Couldn't copy", comment: "Error when copying an item")
    }

    static var savedFlash: String {
        String(localized: "Saved as a new item", comment: "Flash on the translation card")
    }

    static var saveFailed: String {
        String(
            localized: "Couldn't save · recording may be paused",
            comment: "Flash when Save as New Item was refused (paused, secret or too long)")
    }

    static var saveNeedsTranslation: String {
        String(localized: "Save after the translation finishes", comment: "Flash on the translation card")
    }

    static func noTranslationYet(_ phase: TranslationCardPhase?) -> String {
        switch phase {
        case .some(let phase) where phase.isWorking:
            String(localized: "Still translating", comment: "Flash on the translation card")
        case .needsSecretConfirmation:
            String(
                localized: "Not translated: looks like it contains a secret", comment: "Flash on the translation card")
        default:
            String(localized: "No translation yet", comment: "Flash on the translation card")
        }
    }
}
