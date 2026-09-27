import Foundation

/// 疑似密钥的发送前检查（docs/CLIP-TRANSLATION-DESIGN.md §8，纯函数）：检查的是引擎实际会收到的文字
/// （`ClipTranslationDocument.sentTexts(markup:)`），而不是条目的纯文本——富文本条目发送的内容来自 HTML / RTF 格式，
/// 可能与纯文本不同。大模型收受限 Markdown；系统翻译收段落纯文本（行内代码的 `{N}` 保护只会让发送的更少，
/// 占位符被改坏后的重译发送的正是这些纯文本），所以扫描保护之前的文字是保守的
public enum ClipSecretGate {
    /// 云端引擎且要发送的文字疑似含密钥：须由用户点「仍然翻译」确认后才可发送。
    /// 逐段检查，并检查按换行拼接的全文（同一次请求里相邻的段一起发送）
    public static func needsConfirmation(
        _ document: ClipTranslationDocument, input: ClipTranslationBatch.Input, sendsTextOffDevice: Bool
    ) -> Bool {
        guard sendsTextOffDevice else { return false }
        let texts = document.sentTexts(markup: input == .markup)
        return texts.contains(where: SecretDetector.containsSecret)
            || SecretDetector.containsSecret(texts.joined(separator: "\n"))
    }
}
