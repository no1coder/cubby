#if DEBUG
import AppKit
import CubbyCore

/// 面板 E2E 与翻译走查用的桩翻译服务：确定性的流式延迟、可配置的失败、密钥拦截与缓存，不联网。
/// 译文取自演示条目的手写译文（PanelE2EFixtures），没有时生成「[目标语言] 原文」
@MainActor
final class PanelE2EStubTranslator: ClipTranslating {
    struct Engine: Equatable, Sendable {
        let name: String
        let isOnDevice: Bool
        let host: String?

        static let system = Engine(name: PanelE2EStubTranslator.systemEngineName, isOnDevice: true, host: nil)
        /// 走查截图：中文界面下的系统引擎名（「系统翻译」，与真实服务的本地化名称一致）
        static let localizedSystem = Engine(
            name: Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
                ? "\u{7CFB}\u{7EDF}\u{7FFB}\u{8BD1}" : PanelE2EStubTranslator.systemEngineName,
            isOnDevice: true, host: nil)
        /// 与真实服务一致：大模型的显示名是「服务商 · 模型」
        static let cloud = Engine(name: "DeepSeek · deepseek-chat", isOnDevice: false, host: "api.deepseek.com")
    }

    nonisolated static let systemEngineName = "System Translation"

    var engine = Engine.system
    /// plan 直接失败（未配置、语言包未下载等）
    var planFailure: TranslationFailure?
    /// 第一段到达后以此失败结束
    var streamFailure: TranslationFailure?
    /// 可由用户去处理的失败（显示「去设置 / 下载语言」）
    var resolvable: [TranslationFailure] = [.notConfigured, .unauthorized, .languageNotInstalled]
    /// 收到开始后第一段之前的等待（图片为识别文字的时间）
    var startDelay: Duration = .milliseconds(80)
    var segmentDelay: Duration = .milliseconds(80)
    var isRecordingPaused = false
    /// false：图片里没有可翻译的文字（空结果、不缓存，与 C3 的约定一致）
    var imageHasText = true
    /// 下一次 translate 拒绝发送（什么都不发出）；planOutdated 时同时把引擎换成另一种（模拟设置被改）
    var refuseNext: ClipTranslationRefusal?
    /// ⇄ 对调拒绝发送（云端引擎 + 疑似密钥时真实服务的行为）
    var refusesReverse = false
    /// 缓存的分段算法已变：缓存命中时整条作为一段重放（真实服务的约定）
    var replaysCacheAsOneSegment = false
    private(set) var refusals: [ClipTranslationRefusal] = []

    /// 调用记录（脚本断言用）
    private(set) var translateCalls: [(itemID: UUID, target: String, confirmedSecret: Bool, cached: Bool)] = []
    private(set) var reverseCalls: [TranslationLanguages] = []
    private(set) var terminatedEarly = 0
    private(set) var saved: [ClipTranslationResult] = []
    private(set) var resolved: [TranslationFailure] = []
    private(set) var setTargetCalls: [(language: String?, pasteTarget: String?)] = []

    private var cache: Set<String> = []
    private var remembered: [String: String] = [:]
    private var chosenTarget: String?
    private let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    // MARK: - ClipTranslating

    var selectableLanguages: [String] {
        ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
    }

    func eligibility(of item: ClipItem) -> ClipTranslationEligibility {
        switch item.kind {
        case .link: return .unsupported(.link)
        case .color: return .unsupported(.color)
        case .file: return .unsupported(.file)
        case .image: return .eligible
        case .text:
            guard let text = item.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .unsupported(.noText)
            }
            return TextHeuristics.looksLikeCode(text) ? .unsupported(.code) : .eligible
        }
    }

    func plan(
        for item: ClipItem, target: String?, pasteTarget: String?
    ) -> Result<ClipTranslationPlan, TranslationFailure> {
        if let planFailure { return .failure(planFailure) }
        let source = Self.detectedSource(item)
        let resolved =
            target ?? pasteTarget.flatMap { remembered[$0] } ?? chosenTarget
            ?? (source.hasPrefix("zh") ? "en" : "zh-Hans")
        let text = item.text ?? ""
        return .success(
            ClipTranslationPlan(
                languages: TranslationLanguages(source: source, target: resolved), detectedSource: source,
                engineName: engine.name, sendsTextOffDevice: !engine.isOnDevice, host: engine.host,
                needsSecretConfirmation: !engine.isOnDevice && SecretDetector.containsSecret(text),
                isCached: isCached(item, target: resolved)))
    }

    func translate(_ item: ClipItem, plan: ClipTranslationPlan, confirmedSecret: Bool) -> AsyncThrowingStream<
        ClipTranslationEvent, any Error
    > {
        let target = plan.languages.target
        if let refusal = takeRefusal() {
            return stream { _ in throw refusal }
        }
        translateCalls.append((item.id, target, confirmedSecret, plan.isCached))
        return stream { [self] continuation in
            if item.kind == .image {
                try await emitImage(item, plan: plan, into: continuation)
                guard imageHasText else { return }
            } else {
                try await emitText(item, plan: plan, into: continuation)
            }
            cache.insert(Self.cacheKey(item.id, target))
        }
    }

    func translate(text: String, languages: TranslationLanguages) -> AsyncThrowingStream<
        ClipTranslationEvent, any Error
    > {
        if refusesReverse {
            refusals.append(.secretNotConfirmed)
            return stream { _ in throw ClipTranslationRefusal.secretNotConfirmed }
        }
        reverseCalls.append(languages)
        let reversed = Self.reverseTranslation(of: text, to: languages.target)
        return stream { [self] continuation in
            let segments = [ClipTranslationSegment(index: 0, original: AttributedString(text), isTranslatable: true)]
            continuation.yield(.started(segments: segments))
            try await Task.sleep(for: startDelay)
            continuation.yield(.segment(index: 0, translation: AttributedString(reversed)))
            continuation.yield(.finished(result(plain: reversed, rich: nil, image: nil, fromCache: false)))
        }
    }

    func setTarget(_ language: String?, rememberFor pasteTarget: String?) {
        setTargetCalls.append((language, pasteTarget))
        guard let pasteTarget else {
            chosenTarget = language
            return
        }
        remembered[pasteTarget] = language
        if language == nil { chosenTarget = nil }
    }

    func rememberedTarget(for pasteTarget: String) -> String? {
        remembered[pasteTarget]
    }

    func saveAsNewItem(_ result: ClipTranslationResult) -> Bool {
        guard !isRecordingPaused else { return false }
        saved.append(result)
        return true
    }

    func canResolve(_ failure: TranslationFailure) -> Bool {
        resolvable.contains(failure)
    }

    func resolve(_ failure: TranslationFailure) async -> Bool {
        resolved.append(failure)
        return true
    }

    /// 真正「发送」过的翻译（不含缓存命中）
    var sentCalls: [(itemID: UUID, target: String, confirmedSecret: Bool, cached: Bool)] {
        translateCalls.filter { !$0.cached }
    }

    /// 忘记本次运行里翻译过的条目（条目上预置的缓存不受影响）
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - 流

    private typealias Continuation = AsyncThrowingStream<ClipTranslationEvent, any Error>.Continuation

    /// 在主线程按脚本产生事件；消费方取消时结束任务，并记下「提前结束」
    private func stream(
        _ body: @escaping @MainActor (Continuation) async throws -> Void
    ) -> AsyncThrowingStream<ClipTranslationEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await body(continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] termination in
                task.cancel()
                guard case .cancelled = termination else { return }
                Task { @MainActor in self?.terminatedEarly += 1 }
            }
        }
    }

    /// 取出一次性的拒绝；计划过期时换引擎，重新 plan 才能拿到新计划
    private func takeRefusal() -> ClipTranslationRefusal? {
        guard let refusal = refuseNext else { return nil }
        refuseNext = nil
        refusals.append(refusal)
        if refusal == .planOutdated {
            engine = engine.isOnDevice ? .cloud : .system
        }
        return refusal
    }

    private func emitText(_ item: ClipItem, plan: ClipTranslationPlan, into continuation: Continuation) async throws {
        if plan.isCached, replaysCacheAsOneSegment {
            try emitWholeCached(item, plan: plan, into: continuation)
            return
        }
        let entry = PanelE2EFixtures.entry(for: item.id)
        let markdown = entry?.text ?? item.text ?? ""
        let paragraphs = PanelE2EFixtures.paragraphs(markdown)
        let segments = paragraphs.enumerated().map { index, paragraph in
            ClipTranslationSegment(
                index: index, original: Self.attributed(paragraph), isTranslatable: !paragraph.hasPrefix("http"))
        }
        continuation.yield(.started(segments: segments))
        let target = plan.languages.target
        let translated = paragraphs.enumerated().map { index, paragraph in
            entry?.translations[target].flatMap { $0.indices.contains(index) ? $0[index] : nil }
                ?? "[\(target)] \(paragraph)"
        }
        let fromCache = plan.isCached
        for (index, text) in translated.enumerated() where segments[index].isTranslatable {
            if !fromCache { try await Task.sleep(for: index == 0 ? startDelay : segmentDelay) }
            continuation.yield(.segment(index: index, translation: Self.attributed(text)))
            if let streamFailure { throw streamFailure }
        }
        let isRich = entry?.isRich ?? false
        let plain = zip(segments, translated)
            .map { $0.isTranslatable ? PanelE2EFixtures.plainText(markdown: $1) : String($0.original.characters) }
            .joined(separator: "\n\n")
        // 整篇一起解析：每个块的段落意图 identity 各不相同，列表项按顺序编号
        let rich = isRich ? Self.attributed(translated.joined(separator: "\n\n")) : nil
        continuation.yield(.finished(result(plain: plain, rich: rich, image: nil, fromCache: fromCache)))
    }

    private func emitImage(_ item: ClipItem, plan: ClipTranslationPlan, into continuation: Continuation) async throws {
        continuation.yield(.started(segments: []))
        guard imageHasText else {
            try await Task.sleep(for: startDelay)
            continuation.yield(.finished(result(plain: "", rich: nil, image: nil, fromCache: false)))
            return
        }
        let target = plan.languages.target
        let texts =
            PanelE2EFixtures.imageTranslations[target] ?? PanelE2EFixtures.imageTexts.map { "[\(target)] \($0)" }
        if !plan.isCached {
            try await Task.sleep(for: startDelay)
            for block in PanelE2EFixtures.blocks(texts: texts, fontScale: Self.translatedFontScale) {
                try await Task.sleep(for: segmentDelay)
                continuation.yield(.imageBlock(block, original: PanelE2EFixtures.imageTexts[block.blockID]))
                if let streamFailure { throw streamFailure }
            }
        }
        let url = try renderTranslatedImage(texts: texts, target: target)
        continuation.yield(
            .finished(result(plain: texts.joined(separator: "\n"), rich: nil, image: url, fromCache: plan.isCached)))
    }

    private func renderTranslatedImage(texts: [String], target: String) throws -> URL {
        let url = outputDirectory.appendingPathComponent("translated-\(target).png")
        guard let source = CGImageSourceCreateWithData(try PanelE2EFixtures.imagePNG() as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw PanelE2EFixtures.FixtureError.drawingFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let blocks = PanelE2EFixtures.blocks(texts: texts, fontScale: Self.translatedFontScale)
        let environment = RenderEnvironment(
            origin: .zero, scale: PanelE2EFixtures.imageScale,
            targetPixelSize: CGSize(width: image.width, height: image.height), pixelatedFrame: nil, frameOrigin: .zero)
        TranslationPainter.draw(blocks, in: context, environment: environment)
        guard let rendered = context.makeImage() else { throw PanelE2EFixtures.FixtureError.drawingFailed }
        try PanelE2EFixtures.png(rendered, scale: PanelE2EFixtures.imageScale).write(to: url)
        return url
    }

    /// 分段算法变了的缓存：原文整条为一段，译文整条一次到达，没有富文本
    private func emitWholeCached(_ item: ClipItem, plan: ClipTranslationPlan, into continuation: Continuation) throws {
        let original = item.text ?? ""
        let whole =
            PanelE2EFixtures.plainTranslation(PanelE2EFixtures.key(for: item.id) ?? "", plan.languages.target)
            ?? "[\(plan.languages.target)] \(original)"
        continuation.yield(
            .started(segments: [
                ClipTranslationSegment(index: 0, original: AttributedString(original), isTranslatable: true)
            ]))
        continuation.yield(.segment(index: 0, translation: AttributedString(whole)))
        continuation.yield(.finished(result(plain: whole, rich: nil, image: nil, fromCache: true)))
    }

    // MARK: - 辅助

    /// 译文比原文略小（中文、日文在同样的框里更紧凑）
    private static let translatedFontScale: CGFloat = 0.9

    private func result(plain: String, rich: AttributedString?, image: URL?, fromCache: Bool) -> ClipTranslationResult {
        ClipTranslationResult(
            plainText: plain, richText: rich, imageURL: image, engineName: engine.name,
            isOnDevice: engine.isOnDevice, fromCache: fromCache)
    }

    /// 与真实服务一致：缓存只对出自同一引擎的译文有效（换引擎即视为未缓存）
    private func isCached(_ item: ClipItem, target: String) -> Bool {
        if cache.contains(Self.cacheKey(item.id, target)) { return true }
        guard let entry = item.translations?.entry(for: target) else { return false }
        return entry.engineName == engine.name && entry.isOnDevice == engine.isOnDevice
    }

    private static func cacheKey(_ id: UUID, _ target: String) -> String {
        "\(id.uuidString)|\(target)"
    }

    /// 源语言：演示条目按标注，其余按文字粗判
    static func detectedSource(_ item: ClipItem) -> String {
        if let source = PanelE2EFixtures.entry(for: item.id)?.source { return source }
        let text = item.text ?? ""
        if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "ja" }
        if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return "zh-Hans" }
        return "en"
    }

    /// ⇄：把译文「译回」源语言。演示条目返回原文，其余加标记
    private static func reverseTranslation(of text: String, to target: String) -> String {
        for entry in PanelE2EFixtures.entries {
            for (language, segments) in entry.translations {
                let joined = segments.map(PanelE2EFixtures.plainText(markdown:)).joined(separator: "\n\n")
                if joined == text, let original = entry.text, language != target {
                    return entry.isRich ? PanelE2EFixtures.plainText(markdown: original) : original
                }
            }
        }
        return "[\(target)] \(text)"
    }

    /// 受限 Markdown → 带段落 / 行内意图的 AttributedString
    static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)))
            ?? AttributedString(markdown)
    }
}
#endif
