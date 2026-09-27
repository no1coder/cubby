import Foundation
import os

/// 大模型请求的超时（§3.6），按每次请求计：首字节（响应头）与整体
public struct LLMTimeouts: Equatable, Sendable {
    public let firstByte: Duration
    public let total: Duration

    public init(firstByte: Duration, total: Duration) {
        self.firstByte = firstByte
        self.total = total
    }

    public static let standard = LLMTimeouts(firstByte: .seconds(20), total: .seconds(90))
}

/// 兼容 OpenAI Chat Completions 的流式翻译引擎（docs/TRANSLATION-DESIGN.md §3.6）。
/// 分批顺序请求，逐块交付译文；日志只记块数、字符数、耗时与状态码，不记原文、译文与密钥
public struct LLMTranslationEngine: TranslationEngine {
    public let configuration: LLMConfiguration
    private let session: URLSession
    private let timeouts: LLMTimeouts
    /// 提示词的场景：截图（默认）或剪贴板文本
    private let prompt: LLMTranslationPrompt.Profile
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Translation")

    public init(
        configuration: LLMConfiguration, session: URLSession, timeouts: LLMTimeouts = .standard,
        prompt: LLMTranslationPrompt.Profile = .screenshot
    ) {
        self.configuration = configuration
        self.session = session
        self.timeouts = timeouts
        self.prompt = prompt
    }

    public var displayName: String {
        configuration.displayName
    }

    public var sendsTextOffDevice: Bool {
        configuration.endpoint.sendsTextOffDevice
    }

    public func translate(
        _ blocks: [TextBlock], languages: TranslationLanguages
    ) -> AsyncThrowingStream<BlockTranslation, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let started = ContinuousClock.now
                do {
                    let translated = try await translateAll(blocks, languages: languages) { continuation.yield($0) }
                    Self.log(blocks, translated: translated, since: started, outcome: "finished")
                    continuation.finish()
                } catch {
                    let mapped = LLMFailureMapping.map(error)
                    Self.log(blocks, translated: nil, since: started, outcome: Self.outcomeName(mapped))
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 顺序处理各批，返回成功的块数；前一批的最后几块作为下一批的上下文。
    /// 超时按请求计算（每批首字节与整体各自计时），多批的长截图不会因累计时长失败
    private func translateAll(
        _ blocks: [TextBlock], languages: TranslationLanguages, yield: @escaping @Sendable (BlockTranslation) -> Void
    ) async throws -> Int {
        var translated = 0
        var previous: [TextBlock] = []
        for batch in LLMTranslationPrompt.batches(blocks) {
            let context = Array(previous.suffix(LLMTranslationPrompt.contextBlockCount))
            translated += try await CaptureDeadline.run(timeouts.total) {
                try await translateBatch(batch, context: context, languages: languages, yield: yield)
            }
            previous = batch
        }
        return translated
    }

    /// 一次请求：流式（SSE）或普通 JSON 响应都能处理；一块都没解析出来时视为返回内容无法识别
    private func translateBatch(
        _ batch: [TextBlock], context: [TextBlock], languages: TranslationLanguages,
        yield: @Sendable (BlockTranslation) -> Void
    ) async throws -> Int {
        let body = ChatCompletionRequest(
            model: configuration.model, stream: true,
            messages: LLMTranslationPrompt.messages(
                for: batch, context: context, languages: languages, profile: prompt))
        let request = LLMHTTP.request(
            configuration.endpoint, path: "chat/completions", method: "POST", accept: "text/event-stream",
            body: try JSONEncoder().encode(body))
        let (bytes, response) = try await LLMHTTP.openStream(request, session: session, firstByte: timeouts.firstByte)
        var parser = TranslationLineParser(blocks: batch)
        if LLMHTTP.isJSON(response) {
            ChatStreamEvent.completionContent(try await LLMHTTP.collect(bytes)).map {
                parser.consume($0).forEach(yield)
            }
        } else {
            try await readEvents(bytes, into: &parser, yield: yield)
        }
        parser.finish().forEach(yield)
        guard parser.deliveredCount > 0 else { throw TranslationFailure.invalidResponse }
        return parser.deliveredCount
    }

    /// 逐字节解码 SSE，直到 [DONE] 或流结束；流中的错误事件立即结束本次翻译
    private func readEvents(
        _ bytes: URLSession.AsyncBytes, into parser: inout TranslationLineParser,
        yield: @Sendable (BlockTranslation) -> Void
    ) async throws {
        var decoder = SSELineDecoder()
        for try await byte in bytes {
            guard let payload = decoder.consume(byte) else { continue }
            if try Self.handle(payload, parser: &parser, yield: yield) { return }
        }
        if let payload = decoder.finish() {
            _ = try Self.handle(payload, parser: &parser, yield: yield)
        }
    }

    /// 处理一个事件；遇到 [DONE] 返回 true
    private static func handle(
        _ payload: String, parser: inout TranslationLineParser, yield: @Sendable (BlockTranslation) -> Void
    ) throws -> Bool {
        switch ChatStreamEvent.decode(payload) {
        case .content(let text):
            parser.consume(text).forEach(yield)
            return false
        case .done: return true
        case .failure(let failure): throw failure
        case .ignored: return false
        }
    }

    private static func log(
        _ blocks: [TextBlock], translated: Int?, since started: ContinuousClock.Instant, outcome: String
    ) {
        let elapsed = (ContinuousClock.now - started).components
        let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        let characters = blocks.reduce(0) { $0 + $1.text.count }
        logger.info(
            """
            LLM translation \(outcome, privacy: .public): blocks=\(blocks.count) chars=\(characters) \
            translated=\(translated ?? -1) ms=\(milliseconds)
            """)
    }

    /// 日志用的结果名（状态码可记，其他内容不记）
    private static func outcomeName(_ error: any Error) -> String {
        guard let failure = error as? TranslationFailure else { return "cancelled" }
        switch failure {
        case .server(let status): return "failed(server \(status))"
        default: return "failed(\(failure))"
        }
    }
}
