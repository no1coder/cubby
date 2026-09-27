import CubbyCore
import Foundation

/// 事件的转发（AsyncThrowingStream.Continuation.yield，可在任意线程调用）
typealias ClipTranslationEmit = @Sendable (ClipTranslationEvent) -> Void

// MARK: - 翻译流水线（docs/CLIP-TRANSLATION-DESIGN.md §5、§7）

extension ClipTranslationService {
    /// 文本：started（各段原文）→ 每段译文到达时 segment → finished（写入缓存之后）。
    /// 图片：started（空）→ 每块排版后 imageBlock → 渲染并缓存译后 PNG → finished。
    /// 已缓存（同一目标语言、同一引擎）时立即重放、不联网。取消消费任务即取消引擎的流；
    /// 出错（含有段 / 块没有译出）时以 TranslationFailure 结束，已到达的部分不缓存；
    /// 拒绝发送时以 ClipTranslationRefusal 结束
    func translate(_ item: ClipItem, plan: ClipTranslationPlan, confirmedSecret: Bool) -> AsyncThrowingStream<
        ClipTranslationEvent, any Error
    > {
        let current = store.item(id: item.id) ?? item
        return stream { service, emit in
            switch current.payload {
            case .text(let text):
                try await service.translateText(
                    current, text: text, plan: plan, confirmedSecret: confirmedSecret, emit: emit)
            case .image:
                try await service.translateImage(current, plan: plan, emit: emit)
            case .files:
                throw TranslationFailure.invalidResponse
            }
        }
    }

    /// ⇄ 对调：把一段文字按纯文本分段译到指定语言；不读、不写缓存
    func translate(text: String, languages: TranslationLanguages) -> AsyncThrowingStream<
        ClipTranslationEvent, any Error
    > {
        stream { service, emit in
            let engine = try service.provider.makeClipEngine(prompt: .clipboardText).get()
            let prepared = await ClipTextTranslation.prepare(text: text, formats: [:])
            // 对调没有「仍然翻译」的确认：整段或要发送的文字疑似含密钥时不发往云端
            if engine.sendsTextOffDevice,
                SecretDetector.containsSecret(text)
                    || ClipSecretGate.needsConfirmation(
                        prepared.document, input: engine.input, sendsTextOffDevice: true)
            {
                throw ClipTranslationRefusal.secretNotConfirmed
            }
            emit(.started(segments: prepared.segments))
            let batch = ClipTranslationBatch(document: prepared.document, input: engine.input)
            let arrived = try await ClipTextTranslation.run(batch, engine: engine.engine, languages: languages) {
                emit(.segment(index: $0, translation: $1))
            }
            try Self.checkComplete(arrived, expected: batch.blocks.count)
            let result = await ClipTextTranslation.result(
                prepared.document, translations: batch.translations(arrived), markup: batch.storesMarkup,
                engine: engine)
            emit(.finished(result))
        }
    }

    // MARK: - 文本

    private func translateText(
        _ item: ClipItem, text: String, plan: ClipTranslationPlan, confirmedSecret: Bool,
        emit: @escaping ClipTranslationEmit
    ) async throws {
        let engine = try engine(matching: plan, for: item)
        let formats = item.formatsName == nil ? [:] : store.formats(for: item)
        let prepared = await ClipTextTranslation.prepare(text: text, formats: formats)
        try Task.checkCancellation()
        let document = prepared.document
        documents = documents.inserting(document, for: item)
        let target = plan.languages.target
        let cached = cachedTranslation(of: item, target: target, engine: engine)
        try Self.checkCachePromise(plan, cached: cached)
        if let cached,
            let replay = await ClipTextTranslation.replay(cached, prepared: prepared, promised: plan.isCached)
        {
            replay.forEach(emit)
            return
        }
        try checkSecret(document, engine: engine, confirmed: confirmedSecret)
        emit(.started(segments: prepared.segments))
        let batch = ClipTranslationBatch(document: document, input: engine.input)
        let arrived = try await ClipTextTranslation.run(batch, engine: engine.engine, languages: plan.languages) {
            emit(.segment(index: $0, translation: $1))
        }
        try Self.checkComplete(arrived, expected: batch.blocks.count)
        let translations = batch.translations(arrived)
        let result = await ClipTextTranslation.result(
            document, translations: translations, markup: batch.storesMarkup, engine: engine)
        try Task.checkCancellation()
        if !arrived.isEmpty {
            store.setTranslation(
                document.cacheEntry(
                    target: target, source: plan.languages.source, engineName: engine.displayName,
                    isOnDevice: !engine.sendsTextOffDevice, createdAt: Date(), translations: translations,
                    markup: batch.storesMarkup),
                for: item.id)
        }
        emit(.finished(result))
    }

    // MARK: - 图片

    private func translateImage(_ item: ClipItem, plan: ClipTranslationPlan, emit: @escaping ClipTranslationEmit)
        async throws
    {
        let engine = try engine(matching: plan, for: item)
        emit(.started(segments: []))
        let target = plan.languages.target
        let cached = cachedTranslation(of: item, target: target, engine: engine)
        try Self.checkCachePromise(plan, cached: cached)
        if let entry = cached, let url = store.translatedImageURL(for: entry) {
            emit(.finished(imageResult(entry.plainText, url: url, engine: engine, fromCache: true)))
            return
        }
        guard let url = store.imageURL(for: item), let source = await ClipImageTranslation.load(url) else {
            throw TranslationFailure.invalidResponse
        }
        let blocks = try await recognize(source)
        let candidates = await ClipImageTranslation.candidates(blocks, target: target)
        try Task.checkCancellation()
        guard !candidates.isEmpty else {
            // 没有可翻译的文字：空结果、不缓存（面板显示「没有可翻译的文字」）
            emit(.finished(imageResult("", url: nil, engine: engine, fromCache: false)))
            return
        }
        let placed = try await streamBlocks(candidates, engine: engine, languages: plan.languages, source: source) {
            emit(.imageBlock($0, original: $1))
        }
        try Self.checkComplete(placed, expected: candidates.count)
        let entry = ClipTranslation(
            target: target, source: plan.languages.source, engineName: engine.displayName,
            isOnDevice: !engine.sendsTextOffDevice, createdAt: Date(), segmentation: ClipTextSegmenter.version,
            segments: ClipTranslatedImage.segments(blockIDs: blocks.map(\.id), translations: placed.mapValues(\.text)))
        let imageURL = try await storeImage(source, blocks: Array(placed.values), entry: entry, for: item.id)
        emit(.finished(imageResult(entry.plainText, url: imageURL, engine: engine, fromCache: false)))
    }

    /// 渲染整图并写入缓存，返回译后 PNG 在图片目录中的地址。译后图片只存在于缓存里（不写临时文件）：
    /// 缓存失败（条目已删除、写盘失败）时按失败结束，什么都不留下
    private func storeImage(
        _ source: ClipImageTranslation.Source, blocks: [TranslatedBlock], entry: ClipTranslation, for id: UUID
    ) async throws -> URL {
        guard let png = await ClipImageTranslation.render(source, blocks: blocks) else {
            throw TranslationFailure.invalidResponse
        }
        try Task.checkCancellation()
        guard let stored = await store.setTranslation(entry, imagePNG: png, for: id),
            let url = store.translatedImageURL(for: stored)
        else {
            logger.error("Caching the translated image failed")
            throw TranslationFailure.invalidResponse
        }
        try Task.checkCancellation()
        return url
    }

    /// 识别图中文字；识别出错按没有文字处理（与截图翻译一致，日志只记错误码），取消照常抛出
    private func recognize(_ source: ClipImageTranslation.Source) async throws -> [TextBlock] {
        do {
            return try await recognizer.blocks(in: source.frame, selection: source.selection)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Text recognition for translation failed: \((error as NSError).code, privacy: .public)")
            return []
        }
    }

    /// 消费引擎的流：每块在后台排版后回报（版面、该块原文）；返回全部版面（块 id → 版面）
    private func streamBlocks(
        _ blocks: [TextBlock], engine: ClipEngine, languages: TranslationLanguages,
        source: ClipImageTranslation.Source, onBlock: (TranslatedBlock, String) -> Void
    ) async throws -> [Int: TranslatedBlock] {
        let byID = Dictionary(blocks.map { ($0.id, $0) }) { first, _ in first }
        var placed: [Int: TranslatedBlock] = [:]
        for try await arrival in engine.engine.translate(blocks, languages: languages) {
            guard let block = byID[arrival.blockID], placed[block.id] == nil else { continue }
            let layout = await ClipImageTranslation.place(block, translation: arrival.text, in: source.frame)
            try Task.checkCancellation()
            placed[block.id] = layout
            onBlock(layout, block.text)
        }
        try Task.checkCancellation()
        return placed
    }

    private func imageResult(_ text: String, url: URL?, engine: ClipEngine, fromCache: Bool) -> ClipTranslationResult {
        ClipTranslationResult(
            plainText: text, richText: nil, imageURL: url, engineName: engine.displayName,
            isOnDevice: !engine.sendsTextOffDevice, fromCache: fromCache)
    }

    // MARK: - 公共

    /// 在主线程上运行一次翻译并把事件转发到流；取消流（消费任务被取消）即取消翻译任务
    private func stream(
        _ work: @escaping @MainActor (ClipTranslationService, @escaping ClipTranslationEmit) async throws -> Void
    ) -> AsyncThrowingStream<ClipTranslationEvent, any Error> {
        AsyncThrowingStream { continuation in
            // 任务持有服务直到翻译结束或被取消（任务不存放在服务里，没有循环引用）
            let task = Task { @MainActor in
                do {
                    try await work(self, { continuation.yield($0) })
                    continuation.finish()
                } catch {
                    if !(error is CancellationError) {
                        self.logger.notice("Clip translation failed: \(String(describing: error), privacy: .public)")
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 与计划一致的引擎：计划之后设置被改（本机 ↔ 云端，或换了云端主机）时不发送——隐私行显示的与实际不符，
    /// 为主机 A 做的「仍然翻译」确认也不能带到主机 B
    private func engine(matching plan: ClipTranslationPlan, for item: ClipItem) throws -> ClipEngine {
        let engine = try provider.makeClipEngine(prompt: Self.prompt(for: item)).get()
        guard engine.sendsTextOffDevice == plan.sendsTextOffDevice, engine.host == plan.host else {
            throw ClipTranslationRefusal.planOutdated
        }
        return engine
    }

    /// 云端引擎、要发送的文字疑似含密钥且用户没有点「仍然翻译」：不发送（面板应先让用户确认，这里是最后一道防线）。
    /// 检查的是该引擎实际会收到的文字（ClipSecretGate），不是条目的纯文本
    private func checkSecret(_ document: ClipTranslationDocument, engine: ClipEngine, confirmed: Bool) throws {
        guard !confirmed,
            ClipSecretGate.needsConfirmation(
                document, input: engine.input, sendsTextOffDevice: engine.sendsTextOffDevice)
        else { return }
        throw ClipTranslationRefusal.secretNotConfirmed
    }

    /// 计划承诺「已缓存、不联网」，缓存却已不在（例如期间清除了全部译文）：重新 plan，
    /// 不能跳过计划里没有做的疑似密钥确认直接联网
    private static func checkCachePromise(_ plan: ClipTranslationPlan, cached: ClipTranslation?) throws {
        if plan.isCached, cached == nil { throw ClipTranslationRefusal.planOutdated }
    }

    /// 每个送出的段 / 块都要译出：引擎的流正常结束却漏了某些（大模型的回复缺行、系统翻译返回空文字）
    /// 按回复不可用处理，部分结果不缓存、不粘贴（设计文档 §1.3、§4、§5.3）
    private static func checkComplete<Value>(_ arrived: [Int: Value], expected: Int) throws {
        guard arrived.count >= expected else { throw TranslationFailure.invalidResponse }
    }
}
