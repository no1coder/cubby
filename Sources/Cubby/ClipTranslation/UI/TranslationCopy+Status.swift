import CubbyCore
import Foundation

// 隐私行（A6）、工具条状态、底栏统计、列表上的角标 / 预览 / HUD（A7）文案

extension TranslationCopy {
    // MARK: - 隐私行

    /// 隐私行的文字与是否为云端（云端用云图标与浅蓝色）
    static func privacy(for card: TranslationCard) -> (text: String, isCloud: Bool, isLocked: Bool) {
        if case .unsupported = card.phase {
            return (String(localized: "Nothing will be sent", comment: "Translation card privacy line"), false, true)
        }
        guard let plan = card.plan else {
            let text =
                card.phase == .failed(.notConfigured)
                ? String(
                    localized: "Not sent · no translation service set up",
                    comment: "Translation card privacy line")
                : String(localized: "Nothing was sent", comment: "Translation card privacy line")
            return (text, false, true)
        }
        guard plan.sendsTextOffDevice else {
            return (
                String(
                    localized: "Translated on this Mac; nothing leaves it",
                    comment: "Translation card privacy line"),
                false, true
            )
        }
        return (cloudPrivacy(card, plan: plan), true, card.phase == .needsSecretConfirmation)
    }

    private static func cloudPrivacy(_ card: TranslationCard, plan: ClipTranslationPlan) -> String {
        let host = plan.host ?? plan.engineName
        if plan.isCached, !card.isReversed {
            return String(localized: "Cached · not sent this time", comment: "Translation card privacy line")
        }
        switch card.phase {
        case .needsSecretConfirmation:
            return String(
                localized: "Not sent · looks like it contains a secret",
                comment: "Translation card privacy line")
        case .holding, .alreadyTarget, .cancelled:
            return String(localized: "Will be sent to \(host)", comment: "Translation card privacy line")
        default:
            return String(localized: "Sent to \(host)", comment: "Translation card privacy line")
        }
    }

    // MARK: - 工具条状态

    static var holdingStatus: String {
        String(localized: "Sending after a moment…", comment: "Translation card status: cloud engine dwell")
    }

    static func waitingStatus(_ card: TranslationCard) -> String {
        if card.isImage {
            return String(
                localized: "card.recognizingText", defaultValue: "Recognizing text…",
                comment: "Translation card status for images while the text in the image is being recognized")
        }
        if let plan = card.plan, plan.sendsTextOffDevice {
            let engine = shortEngineName(plan.engineName)
            return String(localized: "Connecting to \(engine)…", comment: "Translation card status")
        }
        return translating
    }

    static var translating: String {
        String(localized: "Translating…", comment: "Translation card status")
    }

    static func imageProgress(_ count: Int) -> String {
        String(localized: "Translating… \(count) done", comment: "Translation card status for images: blocks done")
    }

    static var dragDivider: String {
        String(localized: "Drag the divider to compare", comment: "Translation card status for images")
    }

    /// 「按住 [⌥] 看原文」拆成键帽前后两段（不同语言语序一致）
    static var holdOptionBefore: String {
        String(
            localized: "Hold",
            comment: "Translation card status: “Hold [⌥] to see the original”, before the key cap")
    }

    static var holdOptionAfter: String {
        String(
            localized: "to see the original",
            comment: "Translation card status: “Hold [⌥] to see the original”, after the key cap")
    }

    static var peekingBefore: String {
        String(
            localized: "Original · release",
            comment: "Translation card status while holding Option: “Original · release [⌥] to go back”")
    }

    static var peekingAfter: String {
        String(
            localized: "to go back", comment: "Translation card status while holding Option, after the key cap")
    }

    static var imagePeekChip: String {
        String(localized: "Original · release ⌥ to go back", comment: "Chip over an image while holding Option")
    }

    static var originalChip: String {
        String(localized: "Original", comment: "Chip on the left of the wipe divider")
    }

    static var translationChip: String {
        String(localized: "Translated", comment: "Chip on the right of the wipe divider")
    }

    static var bubbleTitle: String {
        String(localized: "Original", comment: "Title of the bubble showing a block's original text")
    }

    static var dividerLabel: String {
        String(
            localized: "Wipe position: original on the left, translation on the right",
            comment: "Accessibility label of the wipe divider")
    }

    // MARK: - 底栏统计

    /// 译文长度：中日韩按字数，其他语言按词数
    static func length(of text: String, language: String?) -> String {
        let code = language.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 } ?? ""
        if ["zh", "ja", "ko"].contains(code) {
            let count = text.unicodeScalars.lazy.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
            return String(localized: "\(count) characters", comment: "Length of a text item")
        }
        let count = text.split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-") }.count
        return String(localized: "\(count) words", comment: "Length of a translation in words")
    }

    static func imageBlockCount(_ count: Int) -> String {
        String(localized: "\(count) text blocks", comment: "Number of translated text blocks in an image")
    }

    static var cached: String {
        String(localized: "Cached", comment: "Translation came from the cache")
    }

    static func timing(engine: String, elapsed: Duration) -> String {
        let seconds = elapsed.formatted(
            .units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: 1)))
        return "\(engine) \(seconds)"
    }

    static var holdingDetail: String {
        String(
            localized: "Sends only after you stay on an item for a moment",
            comment: "Translation card footer during the cloud dwell")
    }

    static var sentWaiting: String {
        String(localized: "Sent, waiting for the first words…", comment: "Translation card footer")
    }

    static var recognizingOnDevice: String {
        String(localized: "Recognizing text on this Mac…", comment: "Translation card footer for images")
    }

    // MARK: - 列表

    static var chip: String {
        String(
            localized: "card.translatedChip", defaultValue: "Tr",
            comment: "Tiny chip on a card that has a cached translation. Keep it to 1–2 characters.")
    }

    static func chipTooltip(_ languages: [String]) -> String {
        let names = languages.map(languageName).formatted(.list(type: .and))
        return String(localized: "Translated: \(names) (cached)", comment: "Tooltip of the translation chip on a card")
    }

    static var translatedAccessibility: String {
        String(localized: "Has translation", comment: "VoiceOver: the card has a cached translation")
    }

    static func lineTooltip(_ language: String) -> String {
        String(
            localized: "Translation · \(languageName(language))",
            comment: "Tooltip of the translation line on a card")
    }

    static func peekMeta(_ peek: TranslationPeek) -> String {
        guard let plan = peek.plan else { return peekTitle }
        let parts = [
            peekTitle, languageName(plan.languages.target), shortEngineName(plan.engineName),
            plan.isCached ? cached : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    static var peekTitle: String {
        String(localized: "Translation preview", comment: "Card meta while holding Option")
    }

    /// isOptionHeld：「松开 ⌥ 恢复」只在 ⌥ 还按着时才有意义
    static func peekTail(_ peek: TranslationPeek, isOptionHeld: Bool) -> String? {
        if peek.pasteOnDone {
            return String(localized: "pastes when done…", comment: "Card meta while holding Option and Return")
        }
        switch peek.phase {
        case .done: return String(localized: "↩ pastes this translation", comment: "Card meta while holding Option")
        case .holding: return holdingStatus
        case .note where isOptionHeld:
            return String(localized: "release ⌥ to restore", comment: "Card meta while holding Option")
        default: return nil
        }
    }

    // MARK: - HUD（A7）

    static func pastedHUD(_ result: ClipTranslationResult, plainText: Bool, pasted: Bool) -> String {
        let engine = spacedName(engineLabel(shortEngineName(result.engineName), isOnDevice: result.isOnDevice))
        if !pasted {
            return plainText
                ? String(
                    localized: "Translation copied as plain text (\(engine))",
                    comment: "HUD after copying a translation instead of pasting it")
                : String(
                    localized: "Translation copied (\(engine))",
                    comment: "HUD after copying a translation instead of pasting it")
        }
        if result.fromCache {
            return String(
                localized: "Pasted translation · from cache (\(engine))",
                comment: "HUD after pasting a cached translation")
        }
        return plainText
            ? String(localized: "Translated with \(engine) and pasted as plain text", comment: "HUD after ⌥↩ / ↩")
            : String(localized: "Translated with \(engine) and pasted", comment: "HUD after ⌥↩ / ↩")
    }
}
