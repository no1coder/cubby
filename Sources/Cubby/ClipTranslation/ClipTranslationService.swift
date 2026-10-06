import AppKit
import CubbyCore
import Foundation
import ImageIO
import os

/// 剪贴板条目翻译的正式实现（docs/CLIP-TRANSLATION-DESIGN.md §10.2 C3）：面板（C2）通过 ClipTranslating 调用。
/// 引擎与设置复用截图翻译的 TranslationService（同一个实例）；译文缓存在 ClipStore 的条目上。
/// 翻译的流水线见 ClipTranslationService+Run
@MainActor
final class ClipTranslationService: ClipTranslating {
    let store: ClipStore
    let settings: AppSettings
    let provider: any ClipTranslationProviding
    let recognizer: any TranslationTextRecognizing
    let preferredLanguages: @MainActor () -> [String]
    let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ClipTranslation")
    /// 最近构建过的翻译文档：plan 据此按实际发送的文字判断富文本条目的疑似密钥
    var documents = ClipDocumentCache()

    init(
        store: ClipStore,
        settings: AppSettings,
        provider: any ClipTranslationProviding,
        recognizer: any TranslationTextRecognizing,
        preferredLanguages: @escaping @MainActor () -> [String] = { SystemLanguages.preferred }
    ) {
        self.store = store
        self.settings = settings
        self.provider = provider
        self.recognizer = recognizer
        self.preferredLanguages = preferredLanguages
    }

    /// 历史来源：图标取 Cubby 自身，名称显示「译文」（搜索「译文」即可找到存下的全部译文）
    static var translationSource: SourceApp {
        SourceApp(
            bundleID: Bundle.main.bundleIdentifier,
            name: String(localized: "Translated Text", comment: "Source name of saved translations in the history"))
    }

    var selectableLanguages: [String] {
        provider.selectableLanguages
    }

    func eligibility(of item: ClipItem) -> ClipTranslationEligibility {
        guard #available(macOS 26, *) else { return .unsupported(.unavailable) }
        guard let reason = ClipTranslationEligibilityCheck.unsupportedReason(for: item) else { return .eligible }
        return .unsupported(Self.unsupportedReason(reason))
    }

    func plan(
        for item: ClipItem, target: String?, pasteTarget: String?
    ) -> Result<ClipTranslationPlan, TranslationFailure> {
        let current = store.item(id: item.id) ?? item
        return provider.makeClipEngine(prompt: Self.prompt(for: current)).map { engine in
            let languages = ClipTranslationTargets.languages(
                explicit: target, remembered: pasteTarget.flatMap(settings.clipTranslationTarget(for:)),
                shared: provider.targetLanguage, preferred: preferredLanguages(), sample: Self.sample(of: current))
            return ClipTranslationPlan(
                languages: languages, detectedSource: languages.source, engineName: engine.displayName,
                engineShortName: engine.shortName, sendsTextOffDevice: engine.sendsTextOffDevice, host: engine.host,
                needsSecretConfirmation: needsSecretConfirmation(current, engine: engine),
                isCached: cachedTranslation(of: current, target: languages.target, engine: engine) != nil)
        }
    }

    /// rememberFor 为 nil：写入与截图共享的目标语言；非 nil：只改该粘贴目标应用记住的语言（nil = 忘记），不动共享的目标
    func setTarget(_ language: String?, rememberFor pasteTarget: String?) {
        if let pasteTarget {
            settings.rememberClipTranslationTarget(language, for: pasteTarget)
        } else {
            provider.targetLanguage = language
        }
    }

    func rememberedTarget(for pasteTarget: String) -> String? {
        settings.clipTranslationTarget(for: pasteTarget)
    }

    /// 文本存为纯文本（富文本条目同样只存纯文本），图片存译后 PNG；暂停记录、疑似密钥（按设置）或超出大小时不保存
    func saveAsNewItem(_ result: ClipTranslationResult) -> Bool {
        guard !settings.isPaused else { return false }
        let content: ClipContent
        if let url = result.imageURL {
            guard let image = Self.imageContent(at: url) else { return false }
            content = image
        } else {
            let text = result.plainText
            guard !text.isEmpty, text.utf8.count <= CaptureLimits.maxTextBytes else { return false }
            content = .text(text)
        }
        guard settings.shouldRecord(content) else { return false }
        store.recordInBackground(content, source: Self.translationSource)
        return true
    }

    func canResolve(_ failure: TranslationFailure) -> Bool {
        provider.canResolve(failure)
    }

    func resolve(_ failure: TranslationFailure) async -> Bool {
        await provider.resolve(failure)
    }

    // MARK: - 缓存

    /// 可直接使用的缓存：该目标语言的译文出自同一引擎；文本与当前分段版本一致，图片的译后文件仍在
    func cachedTranslation(of item: ClipItem, target: String, engine: ClipEngine) -> ClipTranslation? {
        guard let entry = item.translation(for: target), engine.produced(entry) else { return nil }
        switch item.payload {
        case .text:
            return entry.imageName == nil && entry.segmentation == ClipTextSegmenter.version ? entry : nil
        case .image:
            let url = store.translatedImageURL(for: entry)
            return url.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } == true
                ? entry : nil
        case .files:
            return nil
        }
    }

    // MARK: - 内部

    /// 云端引擎且要发送的文字疑似含密钥（ClipSecretGate，扫描该引擎实际收到的文字）。纯文本条目当场分段（不解析格式）；
    /// 富文本条目的文档要在后台解析，尚未构建过时先按条目纯文本判断——翻译开始时 checkSecret 会按实际发送的文字
    /// 再查一次，不一致时以 secretNotConfirmed 结束（什么都没发出），面板随即请用户确认
    private func needsSecretConfirmation(_ item: ClipItem, engine: ClipEngine) -> Bool {
        guard engine.sendsTextOffDevice, let text = item.text else { return false }
        let known =
            item.formatsName == nil && text.utf16.count <= ClipTranslationEligibilityCheck.maxSourceLength
            ? ClipTranslationDocument.plain(text) : documents.document(for: item)
        guard let known else { return SecretDetector.containsSecret(text) }
        return ClipSecretGate.needsConfirmation(known, input: engine.input, sendsTextOffDevice: true)
    }

    /// 文本条目用剪贴板文本的提示词；图片里的文字多是界面与标签，沿用截图的提示词
    static func prompt(for item: ClipItem) -> LLMTranslationPrompt.Profile {
        item.image == nil ? .clipboardText : .screenshot
    }

    /// 检测源语言的取样：文本条目取正文；图片取已识别的文字（按图中文字搜索的索引），尚未识别时为空
    private static func sample(of item: ClipItem) -> String {
        String((item.text ?? item.recognizedText ?? "").prefix(ClipTranslationTargets.sampleLimit))
    }

    private static func unsupportedReason(_ reason: ClipUntranslatableReason) -> ClipTranslationUnsupportedReason {
        switch reason {
        case .link: .link
        case .file: .file
        case .color: .color
        case .code: .code
        case .noText: .noText
        case .tooLong: .tooLong
        case .imageTooLarge: .imageTooLarge
        }
    }

    /// 译后 PNG → 可入历史的图片内容（只读取尺寸，不整图解码）；读不到、过大或尺寸未知时为 nil
    private static func imageContent(at url: URL) -> ClipContent? {
        guard let png = try? Data(contentsOf: url), png.count <= CaptureLimits.maxImageBytes,
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        return .image(png: png, width: width, height: height)
    }
}
