import CubbyCore
import Foundation

/// 文本条目翻译的后台部分（docs/CLIP-TRANSLATION-DESIGN.md §7）：构建翻译文档（HTML / RTF 解析不上主线程）、
/// 把各段送给引擎并逐段回报、由到达的译文生成结果。主线程只负责读取格式、写缓存与转发事件
enum ClipTextTranslation {
    /// 构建好的文档与「对照」视图用的各段原文
    struct Prepared: Sendable {
        let document: ClipTranslationDocument
        let segments: [ClipTranslationSegment]
    }

    /// 构建翻译文档：富文本格式能解析出结构时按段落，否则按纯文本分段
    @concurrent
    static func prepare(text: String, formats: [String: Data]) async -> Prepared {
        let document = ClipTranslationDocument.make(text: text, formats: formats)
        let segments = document.segments.map { segment in
            ClipTranslationSegment(
                index: segment.index, original: document.original(at: segment.index),
                isTranslatable: segment.isTranslatable)
        }
        return Prepared(document: document, segments: segments)
    }

    /// 把一批段送给引擎，逐段回报（段序号、显示用的译文；不需要显示时传 nil），返回全部到达的译文（段序号 → 缓存文字）。
    /// 占位符被引擎改坏的段在第一轮结束后不带保护重译一次；任务取消时抛出 CancellationError
    @concurrent
    static func run(
        _ batch: ClipTranslationBatch, engine: any TranslationEngine, languages: TranslationLanguages,
        onSegment: (@Sendable (Int, AttributedString) -> Void)?
    ) async throws -> [Int: String] {
        var arrived: [Int: String] = [:]
        let report: (Int, String) -> Void = { index, text in
            arrived[index] = text
            onSegment?(index, batch.document.translation(text, at: index, markup: batch.storesMarkup))
        }
        let retries = try await consume(batch, engine: engine, languages: languages, report: report)
        if !retries.isEmpty {
            _ = try await consume(batch.retrying(retries), engine: engine, languages: languages, report: report)
        }
        return arrived
    }

    /// 缓存命中的重放事件：分段与当前文档一致时逐段重放；不一致（例如格式读取失败、按纯文本分段）而计划已承诺
    /// 「已缓存、不联网」（promised）时退化为原文、译文各一整段（设计文档 §2.1）；否则为 nil，应重新翻译
    @concurrent
    static func replay(_ entry: ClipTranslation, prepared: Prepared, promised: Bool) async -> [ClipTranslationEvent]? {
        let document = prepared.document
        let markup = entry.usesInlineMarkup == true
        if document.isAligned(with: entry) {
            let segments = entry.segments.enumerated().compactMap { index, stored in
                stored.map {
                    ClipTranslationEvent.segment(
                        index: index, translation: document.translation($0, at: index, markup: markup))
                }
            }
            let result = makeResult(
                document, translations: entry.segments, markup: markup, engineName: entry.engineName,
                isOnDevice: entry.isOnDevice, fromCache: true)
            return [.started(segments: prepared.segments)] + segments + [.finished(result)]
        }
        guard promised else { return nil }
        let original = ClipTranslationSegment(
            index: 0, original: AttributedString(document.plainText(translations: [], markup: false)),
            isTranslatable: true)
        let result = ClipTranslationResult(
            plainText: entry.plainText, richText: nil, imageURL: nil, engineName: entry.engineName,
            isOnDevice: entry.isOnDevice, fromCache: true)
        return [
            .started(segments: [original]), .segment(index: 0, translation: AttributedString(entry.plainText)),
            .finished(result),
        ]
    }

    /// 完整结果：纯文本（未翻译的段用原文）与富文本条目保留结构的译文
    @concurrent
    static func result(
        _ document: ClipTranslationDocument, translations: [String?], markup: Bool, engine: ClipEngine
    ) async -> ClipTranslationResult {
        makeResult(
            document, translations: translations, markup: markup, engineName: engine.displayName,
            isOnDevice: !engine.sendsTextOffDevice, fromCache: false)
    }

    // MARK: - 内部

    /// 消费一次引擎的流；返回占位符被改坏、需要重译的段
    private static func consume(
        _ batch: ClipTranslationBatch, engine: any TranslationEngine, languages: TranslationLanguages,
        report: (Int, String) -> Void
    ) async throws -> [Int] {
        guard !batch.blocks.isEmpty else { return [] }
        var retries: [Int] = []
        for try await translation in engine.translate(batch.blocks, languages: languages) {
            switch batch.arrival(translation) {
            case .translated(let index, let text): report(index, text)
            case .needsRetry(let index): retries.append(index)
            case nil: continue
            }
        }
        // 任务取消时引擎的流直接结束（不抛错），这里补上
        try Task.checkCancellation()
        return retries
    }

    private static func makeResult(
        _ document: ClipTranslationDocument, translations: [String?], markup: Bool, engineName: String,
        isOnDevice: Bool, fromCache: Bool
    ) -> ClipTranslationResult {
        ClipTranslationResult(
            plainText: document.plainText(translations: translations, markup: markup),
            richText: document.richText(translations: translations, markup: markup), imageURL: nil,
            engineName: engineName, isOnDevice: isOnDevice, fromCache: fromCache)
    }
}
