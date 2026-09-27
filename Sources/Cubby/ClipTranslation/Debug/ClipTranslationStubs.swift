#if DEBUG
import CubbyCore
import Foundation
import os

/// 剪贴板翻译自检（--clip-translation-selftest）用的桩：不联网、确定性的逐块译文，记录每次请求发出的文字与取消
final class ClipStubLog: Sendable {
    private struct State {
        var requests: [[String]] = []
        var cancellations = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var requests: [[String]] {
        state.withLock { $0.requests }
    }

    var cancellations: Int {
        state.withLock { $0.cancellations }
    }

    func record(_ texts: [String]) {
        state.withLock { $0.requests.append(texts) }
    }

    func recordCancellation() {
        state.withLock { $0.cancellations += 1 }
    }
}

/// 桩引擎：每块等 delay 后返回 transform(原文)；failAfter 块之后以 failure 结束
struct ClipStubEngine: TranslationEngine {
    var displayName = "Stub Engine"
    var sendsTextOffDevice = false
    var delay: Duration = .milliseconds(5)
    var failAfter: Int?
    var failure = TranslationFailure.network
    var transform: @Sendable (String, Int) -> String = { text, _ in "[T] " + text }
    let log: ClipStubLog

    func translate(
        _ blocks: [TextBlock], languages: TranslationLanguages
    ) -> AsyncThrowingStream<BlockTranslation, any Error> {
        log.record(blocks.map(\.text))
        let attempt = log.requests.count
        return AsyncThrowingStream { continuation in
            let task = Task {
                for (offset, block) in blocks.enumerated() {
                    if let failAfter, offset >= failAfter {
                        continuation.finish(throwing: failure)
                        return
                    }
                    try? await Task.sleep(for: delay)
                    if Task.isCancelled {
                        log.recordCancellation()
                        return continuation.finish()
                    }
                    continuation.yield(BlockTranslation(blockID: block.id, text: transform(block.text, attempt)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 桩 provider：引擎与接收方式可替换；语言包是否已下载可设定
@MainActor
final class ClipStubProvider: ClipTranslationProviding {
    var targetLanguage: String?
    let selectableLanguages = ["zh-Hans", "en", "ja"]
    var engine: ClipStubEngine
    var input = ClipTranslationBatch.Input.plainText
    var host: String?
    var onDevice: ClipStubEngine
    var installed = true
    var setupFailure: TranslationFailure?

    init(log: ClipStubLog) {
        engine = ClipStubEngine(log: log)
        onDevice = ClipStubEngine(displayName: "Stub On-Device", log: log)
    }

    func makeEngine() -> Result<any TranslationEngine, TranslationFailure> {
        makeClipEngine(prompt: .screenshot).map(\.engine)
    }

    func makeClipEngine(prompt: LLMTranslationPrompt.Profile) -> Result<ClipEngine, TranslationFailure> {
        if let setupFailure { return .failure(setupFailure) }
        return .success(ClipEngine(engine: engine, input: input, host: host))
    }

    func makeOnDeviceEngine() -> any TranslationEngine {
        onDevice
    }

    func isInstalled(_ languages: TranslationLanguages) async -> Bool {
        installed && languages.source != nil
    }

    func canResolve(_ failure: TranslationFailure) -> Bool {
        failure == .notConfigured
    }

    func resolve(_ failure: TranslationFailure) async -> Bool {
        false
    }
}

/// 收集一次翻译流的事件与结束时的错误
struct ClipCollectedEvents {
    var started: [ClipTranslationSegment]?
    var segments: [Int: AttributedString] = [:]
    var imageBlocks: [TranslatedBlock] = []
    var result: ClipTranslationResult?
    var error: (any Error)?

    static func collect(_ stream: AsyncThrowingStream<ClipTranslationEvent, any Error>) async -> ClipCollectedEvents {
        var collected = ClipCollectedEvents()
        do {
            for try await event in stream {
                collected.record(event)
            }
        } catch {
            collected.error = error
        }
        return collected
    }

    mutating func record(_ event: ClipTranslationEvent) {
        switch event {
        case .started(let segments): started = segments
        case .segment(let index, let translation): segments[index] = translation
        case .imageBlock(let block, _): imageBlocks.append(block)
        case .finished(let result): self.result = result
        }
    }
}
#endif
