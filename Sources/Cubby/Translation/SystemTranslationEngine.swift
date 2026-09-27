import CubbyCore
import Foundation
import Translation
import os

/// 系统翻译（Apple 本机，docs/TRANSLATION-DESIGN.md §3.7）：只用已安装的语言包，文字不离开这台 Mac。
/// 批量接口的异步序列逐块返回，按 clientIdentifier（块 id）对回
@available(macOS 26, *)
struct SystemTranslationEngine: TranslationEngine {
    /// 语言包缺失时记下语言对，供「下载语言」使用（TranslationFailure 不携带语言）
    let missingLanguages: MissingLanguagePair

    var displayName: String {
        String(localized: "System Translation", comment: "Translation engine name shown in the translation bar")
    }

    var sendsTextOffDevice: Bool {
        false
    }

    func translate(
        _ blocks: [TextBlock], languages: TranslationLanguages
    ) -> AsyncThrowingStream<BlockTranslation, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(blocks, languages: languages) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.failure(for: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ blocks: [TextBlock], languages: TranslationLanguages, yield: @Sendable (BlockTranslation) -> Void
    ) async throws {
        guard !blocks.isEmpty else { return }
        let target = Locale.Language(identifier: languages.target)
        let source = try await Self.source(for: languages, blocks: blocks, target: target)
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            missingLanguages.record(LanguagePair(source: source, target: target))
            throw TranslationFailure.languageNotInstalled
        case .unsupported:
            throw TranslationFailure.unsupportedLanguages
        @unknown default:
            throw TranslationFailure.unsupportedLanguages
        }
        do {
            try await stream(blocks, source: source, target: target, yield: yield)
        } catch let error where TranslationError.notInstalled ~= error {
            // 检查之后语言包被移除等情况：同样记下语言对，供「下载语言」使用
            missingLanguages.record(LanguagePair(source: source, target: target))
            throw error
        }
    }

    /// 批量请求的异步序列逐块返回；按 clientIdentifier 对回块 id，重复与未知的忽略
    private func stream(
        _ blocks: [TextBlock], source: Locale.Language, target: Locale.Language,
        yield: @Sendable (BlockTranslation) -> Void
    ) async throws {
        let session = SessionHandle(TranslationSession(installedSource: source, target: target))
        let requests = blocks.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id)) }
        let ids = Set(blocks.map(\.id))
        var delivered: Set<Int> = []
        try await withTaskCancellationHandler {
            for try await response in session.value.translate(batch: requests) {
                guard let id = response.clientIdentifier.flatMap(Int.init), ids.contains(id),
                    delivered.insert(id).inserted, !response.targetText.isEmpty
                else { continue }
                yield(BlockTranslation(blockID: id, text: response.targetText))
            }
        } onCancel: {
            session.cancel()
        }
    }

    /// 源语言：已知则用之；否则按检测候选逐个尝试第一个受支持的（§3.4）
    private static func source(
        for languages: TranslationLanguages, blocks: [TextBlock], target: Locale.Language
    ) async throws -> Locale.Language {
        if let known = languages.source { return Locale.Language(identifier: known) }
        let sample = blocks.map(\.text).joined(separator: "\n")
        let availability = LanguageAvailability()
        for candidate in TranslationTargetResolver.sourceCandidates(sample) {
            let language = Locale.Language(identifier: candidate.language)
            if await availability.status(from: language, to: target) != .unsupported { return language }
        }
        throw TranslationFailure.unsupportedLanguages
    }

    /// 系统错误 → TranslationFailure；取消保持为 CancellationError
    static func failure(for error: any Error) -> any Error {
        if error is CancellationError || error is TranslationFailure { return error }
        if TranslationError.notInstalled ~= error { return TranslationFailure.languageNotInstalled }
        if TranslationError.alreadyCancelled ~= error { return CancellationError() }
        let unsupported: [TranslationError] = [
            .unsupportedSourceLanguage, .unsupportedTargetLanguage, .unsupportedLanguagePairing,
            .unableToIdentifyLanguage,
        ]
        if unsupported.contains(where: { $0 ~= error }) { return TranslationFailure.unsupportedLanguages }
        Logger(subsystem: "io.github.no1coder.Cubby", category: "Translation")
            .error("System translation failed: \(String(describing: type(of: error)), privacy: .public)")
        return TranslationFailure.invalidResponse
    }
}

/// TranslationSession 不是 Sendable；它的 cancel() 正是为从其他任务取消而设计的，
/// 这里只在翻译任务内迭代、在取消处理器中调用 cancel()
@available(macOS 26, *)
private final class SessionHandle: @unchecked Sendable {
    let value: TranslationSession

    init(_ value: TranslationSession) {
        self.value = value
    }

    func cancel() {
        value.cancel()
    }
}

/// 系统翻译的语言对
struct LanguagePair: Sendable {
    let source: Locale.Language
    let target: Locale.Language
}

/// 最近一次缺少语言包的语言对（线程安全）：引擎在后台记录，TranslationService 在主线程取走
final class MissingLanguagePair: Sendable {
    private let pair = OSAllocatedUnfairLock<LanguagePair?>(initialState: nil)

    func record(_ languages: LanguagePair) {
        pair.withLock { $0 = languages }
    }

    /// 取走并清空，避免之后的「下载语言」用上过期的语言对
    func take() -> LanguagePair? {
        pair.withLock { current in
            defer { current = nil }
            return current
        }
    }
}
