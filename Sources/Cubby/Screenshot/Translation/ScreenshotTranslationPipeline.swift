import CoreGraphics
import CubbyCore
import Foundation
import os

/// 覆盖层做截图翻译所需的服务：翻译设置与引擎 + 文字识别。
/// 只在 macOS 26+ 且 App 提供了两者时存在（协调器据此决定是否显示翻译按钮）
@MainActor
struct ScreenshotTranslationServices {
    let provider: any TranslationProviding
    let recognizer: any TranslationTextRecognizing
}

/// 截图翻译的流水线（docs/TRANSLATION-DESIGN.md §2 / §4.3 T1）：
/// 识别 → 过滤（马赛克、密钥、无字母、已是目标语言）→ 目标语言 → 创建引擎 → 逐块消费引擎的流 →
/// 每块在后台排版 → 回报给会话（`TranslationEvent`）。
///
/// 同一时刻只有一个任务：开始新任务先取消旧的；旧任务迟到的回报按代次丢弃（会话也只认进行中的那次运行）。
/// 重的活（识别、语言判断、排版）都不在主线程；主线程只转发回报。
/// 发送前的过滤除了效果里带的遮挡区域，还会再取一次当前的马赛克区域（识别期间新画的马赛克同样生效）。
@MainActor
final class ScreenshotTranslationPipeline {
    typealias Emit = @MainActor (TranslationEvent) -> Void

    private let services: ScreenshotTranslationServices
    private let preferredLanguages: @MainActor () -> [String]
    /// 当前会话里马赛克覆盖的区域（全局点）
    private let hiddenRegions: @MainActor () -> [CGRect]
    /// 当前选区（全局点）：排版时「向同色空白扩展」不越过它，否则靠近选区边缘的译文在导出时会被裁掉
    private let selection: @MainActor () -> CGRect?
    private let onEvent: Emit
    private var task: Task<Void, Never>?
    /// 每开始 / 取消一次递增：旧任务的回报一律丢弃
    private var generation = 0
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ScreenshotTranslation")

    init(
        services: ScreenshotTranslationServices,
        hiddenRegions: @escaping @MainActor () -> [CGRect],
        selection: @escaping @MainActor () -> CGRect? = { nil },
        preferredLanguages: @escaping @MainActor () -> [String] = { SystemLanguages.preferred },
        onEvent: @escaping Emit
    ) {
        self.services = services
        self.hiddenRegions = hiddenRegions
        self.selection = selection
        self.preferredLanguages = preferredLanguages
        self.onEvent = onEvent
    }

    /// 执行 reducer 的翻译副作用；capture 提供各屏的冻结帧
    func perform(_ effect: TranslationEffect, capture: CaptureSession) {
        switch effect {
        case .cancel:
            cancel()
        case .recognize(let run, let selection, let screenID, let hidden):
            withFrame(screenID, run: run, capture: capture) { frame, emit in
                await self.recognizing(run, frame: frame, selection: selection, hidden: hidden, emit: emit)
            }
        case .translate(let run, let blocks, let screenID, let hidden):
            withFrame(screenID, run: run, capture: capture) { frame, emit in
                await self.translating(run, blocks: blocks, frame: frame, hidden: hidden, emit: emit)
            }
        case .retry(let run, let blocks, let screenID, let languages, let hidden):
            withFrame(screenID, run: run, capture: capture) { frame, emit in
                await self.retrying(run, blocks: blocks, languages: languages, hidden: hidden, frame: frame, emit: emit)
            }
        }
    }

    /// 取消进行中的任务（Esc、会话结束、换语言前）
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    // MARK: - 任务

    /// 取消旧任务，用该屏的冻结帧开始新任务；找不到帧（不应发生）时按无法完成处理
    private func withFrame(
        _ screenID: UInt32,
        run: TranslationRunID,
        capture: CaptureSession,
        _ work: @escaping @MainActor (FrozenFrame, @escaping Emit) async -> Void
    ) {
        cancel()
        let current = generation
        let emit: Emit = { [weak self] event in
            guard let self, self.generation == current, !Task.isCancelled else { return }
            self.onEvent(event)
        }
        guard let frame = capture.frame(for: screenID) else {
            logger.error("No frozen frame for the translation")
            emit(.failed(run, .invalidResponse))
            return
        }
        task = Task { await work(frame, emit) }
    }

    /// 识别选区里的文字；识别出错按没有文字处理（日志只记错误码）
    private func recognizing(
        _ run: TranslationRunID, frame: FrozenFrame, selection: CGRect, hidden: [CGRect], emit: @escaping Emit
    ) async {
        let blocks: [TextBlock]
        do {
            blocks = try await services.recognizer.blocks(in: frame, selection: selection)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Text recognition for translation failed: \((error as NSError).code, privacy: .public)")
            emit(.recognized(run, []))
            return
        }
        emit(.recognized(run, blocks))
        guard !blocks.isEmpty, !Task.isCancelled else { return }
        await translating(run, blocks: blocks, frame: frame, hidden: hidden, emit: emit)
    }

    /// 过滤与判断语言（后台），再开始翻译
    private func translating(
        _ run: TranslationRunID, blocks: [TextBlock], frame: FrozenFrame, hidden: [CGRect], emit: @escaping Emit
    ) async {
        let chosen = services.provider.targetLanguage
        let preferred = preferredLanguages()
        let hidden = hidden + hiddenRegions()
        let prepared = await Task.detached(priority: .userInitiated) {
            TranslationPreparation.prepare(blocks, chosen: chosen, preferred: preferred, hidden: hidden)
        }.value
        guard !Task.isCancelled else { return }
        guard let languages = prepared.languages else {
            emit(.needsTargetLanguage(run))
            return
        }
        guard !prepared.candidates.isEmpty else {
            emit(.nothingToTranslate(run))
            return
        }
        await streaming(run, blocks: prepared.candidates, languages: languages, frame: frame, emit: emit)
    }

    /// 部分失败后的重试：发送前按最新的遮挡区域再过滤一次；都被遮住了就直接结束
    private func retrying(
        _ run: TranslationRunID, blocks: [TextBlock], languages: TranslationLanguages, hidden: [CGRect],
        frame: FrozenFrame, emit: @escaping Emit
    ) async {
        let sendable = TranslationCandidates.translatable(
            blocks, target: languages.target, hidden: hidden + hiddenRegions())
        guard !sendable.isEmpty else {
            emit(.finished(run))
            return
        }
        await streaming(run, blocks: sendable, languages: languages, frame: frame, emit: emit)
    }

    /// 创建引擎并消费它的流：每块在后台排版后回报；流以错误结束时回报失败
    private func streaming(
        _ run: TranslationRunID, blocks: [TextBlock], languages: TranslationLanguages, frame: FrozenFrame,
        emit: @escaping Emit
    ) async {
        let engine: any TranslationEngine
        switch services.provider.makeEngine() {
        case .failure(let failure):
            emit(.failed(run, failure))
            return
        case .success(let made):
            engine = made
        }
        let badge = TranslationEngineBadge(name: engine.displayName, sendsTextOffDevice: engine.sendsTextOffDevice)
        emit(.started(run, TranslationPlan(blockIDs: blocks.map(\.id), languages: languages, engine: badge)))
        let byID = Dictionary(blocks.map { ($0.id, $0) }) { first, _ in first }
        logger.info("Translating \(blocks.count, privacy: .public) block(s)")
        do {
            for try await item in engine.translate(blocks, languages: languages) {
                guard let block = byID[item.blockID] else { continue }
                let text = item.text
                let limit = selection()
                let placed = await Task.detached(priority: .userInitiated) {
                    TranslationPlacer.place(block, translation: text, in: frame, within: limit)
                }.value
                guard !Task.isCancelled else { return }
                emit(.arrived(run, placed))
            }
            guard !Task.isCancelled else { return }
            emit(.finished(run))
        } catch is CancellationError {
            return
        } catch let failure as TranslationFailure {
            logger.notice("Translation failed: \(String(describing: failure), privacy: .public)")
            emit(.failed(run, failure))
        } catch {
            logger.error("Translation stream ended with an unexpected error")
            emit(.failed(run, .invalidResponse))
        }
    }
}

/// 翻译前的准备（纯函数，后台执行）：判断语言、挑出需要翻译的块
enum TranslationPreparation {
    /// 语言判断取样的最大字符数（足够判断，又不让长文拖慢）
    static let sampleLimit = 4000

    struct Prepared: Sendable {
        /// nil = 自动模式下找不到与原文不同的目标语言
        let languages: TranslationLanguages?
        let candidates: [TextBlock]
    }

    /// 取样只用没被马赛克挡住的块；候选由 `TranslationCandidates` 按目标语言与遮挡过滤
    nonisolated static func prepare(
        _ blocks: [TextBlock], chosen: String?, preferred: [String], hidden: [CGRect]
    ) -> Prepared {
        let visible = blocks.filter { block in !hidden.contains { $0.intersects(block.frame) } }
        let sample = String(visible.map(\.text).joined(separator: "\n").prefix(sampleLimit))
        guard
            let languages = TranslationTargetResolver.languages(chosen: chosen, preferred: preferred, sample: sample)
        else { return Prepared(languages: nil, candidates: []) }
        let candidates = TranslationCandidates.translatable(blocks, target: languages.target, hidden: hidden)
        return Prepared(languages: languages, candidates: candidates)
    }
}
