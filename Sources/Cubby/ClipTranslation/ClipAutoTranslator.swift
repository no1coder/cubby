import CubbyCore
import Foundation
import Observation
import os

/// 复制时自动翻译（docs/CLIP-TRANSLATION-DESIGN.md §6，默认关）：新记录的文本条目按 ClipAutoTranslateDecision 判定，
/// 只用本机系统翻译，且语言包已下载（绝不触发下载）；串行、utility 优先级；排队只留最新一条；
/// 复制后 0.5 s 开始、两次间隔 ≥ 1 s（ClipAutoTranslateQueue）；单次 10 s 超时；
/// 关闭开关、暂停记录或进入低电量模式时取消进行中与排队的任务。失败静默，日志只记次数
@MainActor
final class ClipAutoTranslator {
    /// 结果计数（只记次数，不记内容）
    private struct Counts {
        var translated = 0
        var skipped = 0
        var failed = 0
    }

    private enum Outcome {
        case translated
        case skipped
        case failed
    }

    /// 后台翻译的产物
    private struct Translated: Sendable {
        let document: ClipTranslationDocument
        let translations: [String?]
        let markup: Bool
    }

    private let store: ClipStore
    private let settings: AppSettings
    private let provider: any ClipTranslationProviding
    private let preferredLanguages: @MainActor () -> [String]
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ClipAutoTranslate")
    private var queue = ClipAutoTranslateQueue.idle
    /// 等待下一步的计时
    private var timer: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var counts = Counts()
    /// 低电量模式的通知（与应用同生命周期，不需要移除）
    private var powerObserver: (any NSObjectProtocol)?

    init(
        store: ClipStore,
        settings: AppSettings,
        provider: any ClipTranslationProviding,
        preferredLanguages: @escaping @MainActor () -> [String] = { Locale.preferredLanguages }
    ) {
        self.store = store
        self.settings = settings
        self.provider = provider
        self.preferredLanguages = preferredLanguages
        observeSettings()
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.conditionsChanged() }
        }
    }

    /// AppDelegate.capture 的后台记录完成后，把入历史的条目排队（记录失败或被忽略时什么也不做）
    func track(_ recording: Task<ClipItem?, Never>) {
        Task { [weak self] in
            guard let item = await recording.value else { return }
            self?.enqueue(item)
        }
    }

    /// 排队一个新复制的条目：只看状态与内容的初筛不通过的不排队（以免顶掉排队中的合格条目）
    func enqueue(_ item: ClipItem) {
        guard ClipAutoTranslateDecision.precheck(item, conditions: conditions) == nil else { return }
        queue = queue.enqueueing(item.id, copiedAt: Date())
        advance()
    }

    // MARK: - 调度

    private var conditions: ClipAutoTranslatePolicy.Conditions {
        ClipAutoTranslatePolicy.Conditions(
            isEnabled: settings.translatesClipsOnCopy, isPaused: settings.isPaused,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private func advance() {
        timer?.cancel()
        timer = nil
        switch queue.nextStep(now: Date()) {
        case .idle, .busy:
            return
        case .wait(let seconds):
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.advance()
            }
        case .start(let id):
            queue = queue.starting()
            running = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                self.record(await self.translate(id))
                self.running = nil
                self.queue = self.queue.finishing(at: Date())
                self.advance()
            }
        }
    }

    /// 关闭开关、暂停记录或进入低电量模式：取消进行中的翻译，丢弃排队的条目
    private func conditionsChanged() {
        guard !conditions.allowsRunning else { return }
        timer?.cancel()
        timer = nil
        running?.cancel()
        queue = queue.cancellingPending()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.translatesClipsOnCopy
            _ = settings.isPaused
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeSettings()
                self?.conditionsChanged()
            }
        }
    }

    // MARK: - 翻译

    private func translate(_ id: UUID) async -> Outcome {
        guard let item = store.item(id: id), let text = item.text else { return .skipped }
        let decision = await Self.decide(
            item, shared: provider.targetLanguage, preferred: preferredLanguages(), conditions: conditions)
        guard case .translate(let languages) = decision, await provider.isInstalled(languages), !Task.isCancelled
        else { return .skipped }
        let formats = item.formatsName == nil ? [:] : store.formats(for: item)
        let engine = provider.makeOnDeviceEngine()
        do {
            let translated = try await CaptureDeadline.run(.seconds(ClipAutoTranslatePolicy.timeout)) {
                try await Self.translate(text, formats: formats, engine: engine, languages: languages)
            }
            // 期间关闭了开关、暂停了记录、删除了条目或已有了该语言的译文（例如用户手动翻译过）：不写入
            guard !Task.isCancelled, conditions.allowsRunning,
                store.item(id: id).map({ $0.translation(for: languages.target) == nil }) == true
            else { return .skipped }
            let entry = translated.document.cacheEntry(
                target: languages.target, source: languages.source, engineName: engine.displayName, isOnDevice: true,
                createdAt: Date(), translations: translated.translations, markup: translated.markup)
            return store.setTranslation(entry, for: id) ? .translated : .failed
        } catch {
            return Task.isCancelled ? .skipped : .failed
        }
    }

    @concurrent
    private static func decide(
        _ item: ClipItem, shared: String?, preferred: [String], conditions: ClipAutoTranslatePolicy.Conditions
    ) async -> ClipAutoTranslateDecision {
        ClipAutoTranslateDecision.decide(for: item, shared: shared, preferred: preferred, conditions: conditions)
    }

    /// 构建文档并翻译全部可翻译段；有段没有译出（或没有可翻译的段）时视为失败，部分结果不缓存
    @concurrent
    private static func translate(
        _ text: String, formats: [String: Data], engine: any TranslationEngine, languages: TranslationLanguages
    ) async throws -> Translated {
        let document = ClipTranslationDocument.make(text: text, formats: formats)
        let batch = ClipTranslationBatch(document: document, input: .plainText)
        let arrived = try await ClipTextTranslation.run(batch, engine: engine, languages: languages, onSegment: nil)
        guard !arrived.isEmpty, arrived.count == batch.blocks.count else { throw TranslationFailure.invalidResponse }
        return Translated(document: document, translations: batch.translations(arrived), markup: batch.storesMarkup)
    }

    private func record(_ outcome: Outcome) {
        switch outcome {
        case .translated: counts.translated += 1
        case .skipped: counts.skipped += 1
        case .failed: counts.failed += 1
        }
        logger.info(
            """
            Auto-translate: translated=\(self.counts.translated) skipped=\(self.counts.skipped) \
            failed=\(self.counts.failed)
            """)
    }
}
