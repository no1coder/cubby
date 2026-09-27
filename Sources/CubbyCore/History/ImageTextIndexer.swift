import Foundation
import Observation
import os

/// 从图片文件识别文字（App 层以本机 Vision 实现并注入；测试注入假实现）
public protocol ImageTextRecognizing: Sendable {
    /// maxPixelSize 非 nil 时先把图片等比缩小到该最长边（像素）再识别；没有文字时返回空串
    func recognizeText(at url: URL, maxPixelSize: Int?) async throws -> String
}

/// 历史图片的文字索引，让图片可以按图中文字搜索。截图与普通剪贴板图片一样：入历史后尽快识别；
/// 启动前已有、尚未识别的图片在启动后空闲时逐条回填。调度规则见 ImageTextIndexSchedule（纯逻辑），这里负责执行：
/// - 观察设置（开关、暂停记录）与历史变化，串行识别（同一时刻最多一张），结果经 ClipStore 写回；
///   回填结果攒够一批或空闲时合并写盘，新图片的结果立即写回；
/// - 暂停记录时停止（进行中的结果照常保存）；关闭开关时停止、丢弃进行中的结果并清除全部已保存的识别文字；
///   重新开启后重新回填；
/// - 退出时 stop()：先写回已攒的结果，进行中的识别丢弃，下次启动继续；
/// - 历史只读（文件来自更新版本等）时不索引；日志只记录耗时与数量，绝不记录识别出的文字。
@MainActor
public final class ImageTextIndexer {
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    /// 回填结果攒够这么多条再写盘
    static let batchSize = 8

    private let store: ClipStore
    private let settings: AppSettings
    private let recognizer: any ImageTextRecognizing
    private let schedule: ImageTextIndexSchedule
    private let now: () -> Date
    private let sleep: Sleep
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ImageTextIndexer")

    /// 本次启动的时间：之后记录的图片视为新图片；nil 表示尚未启动或已停止
    private var sessionStart: Date?
    private var lastFinished: Date?
    /// 本次运行中识别失败的条目，不再重试（下次启动再试）
    private var failed: Set<UUID> = []
    /// 正在识别的条目（包括已被取消、Vision 仍在收尾的）：规划时跳过，避免重复识别
    private var inFlight: Set<UUID> = []
    /// 已识别、等待合并写回的结果
    private var pending: [UUID: String] = [:]
    private var loop: Task<Void, Never>?
    /// 当前循环正在识别：此时历史变化不打断，识别结束后循环会自行重新规划
    private var isRecognizing = false
    private var indexedCount = 0
    private var hasStarted = false

    public init(
        store: ClipStore,
        settings: AppSettings,
        recognizer: any ImageTextRecognizing,
        schedule: ImageTextIndexSchedule = .standard,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.store = store
        self.settings = settings
        self.recognizer = recognizer
        self.schedule = schedule
        self.now = now
        self.sleep = sleep
    }

    /// 开始索引。只能启动一次（stop 之后不再启动）
    public func start() {
        guard !hasStarted, store.canPersist else { return }
        hasStarted = true
        sessionStart = now()
        observe({ [settings] in _ = (settings.indexesImageText, settings.isPaused) }) { [weak self] in
            self?.settingsDidChange()
        }
        observe({ [store] in _ = store.revision }) { [weak self] in
            self?.historyDidChange()
        }
        settingsDidChange()
    }

    /// 退出前调用：写回已攒的结果，中断进行中的识别（其结果丢弃，下次启动继续）
    public func stop() {
        guard sessionStart != nil else { return }
        flushPending()
        sessionStart = nil
        cancelLoop()
    }

    // MARK: - 状态变化

    private func settingsDidChange() {
        guard sessionStart != nil else { return }
        guard settings.indexesImageText else {
            cancelLoop()
            pending = [:]
            failed = []
            // 关闭即清除（启动时发现已关闭也清一次，覆盖关闭后未及写盘就退出的情况）
            store.clearRecognizedText()
            return
        }
        if settings.isPaused {
            cancelLoop()
            flushPending()
        } else if !isRecognizing {
            restartLoop()
        }
    }

    /// 历史变化（新图片、删除、清空……）：打断等待并重新规划，新图片因此能立即识别
    private func historyDidChange() {
        guard sessionStart != nil, !isRecognizing else { return }
        restartLoop()
    }

    private func restartLoop() {
        loop?.cancel()
        isRecognizing = false
        loop = Task(priority: .utility) { [weak self] in await self?.runLoop() }
    }

    private func cancelLoop() {
        loop?.cancel()
        loop = nil
        isRecognizing = false
    }

    // MARK: - 执行

    private func runLoop() async {
        while !Task.isCancelled {
            guard let state = currentState() else { return }
            switch schedule.nextStep(items: store.history.items, state: state) {
            case .stop:
                flushPending()
                return
            case .idle:
                flushPending()
                logCompletion()
                return
            case .wait(let seconds):
                try? await sleep(seconds)
            case .recognize(let item):
                await recognize(item)
            }
        }
    }

    private func currentState() -> ImageTextIndexSchedule.State? {
        sessionStart.map {
            ImageTextIndexSchedule.State(
                isEnabled: settings.indexesImageText,
                isPaused: settings.isPaused,
                sessionStart: $0,
                now: now(),
                lastFinished: lastFinished,
                skipped: failed.union(inFlight).union(pending.keys)
            )
        }
    }

    private func recognize(_ item: ClipItem) async {
        guard let image = item.image, let url = store.imageURL(for: item) else {
            failed.insert(item.id)
            return
        }
        isRecognizing = true
        inFlight.insert(item.id)
        let started = ContinuousClock.now
        let maxPixelSize = ImageTextIndexPolicy.recognitionMaxPixelSize(width: image.width, height: image.height)
        let outcome: Result<String, any Error>
        do {
            outcome = .success(try await recognizer.recognizeText(at: url, maxPixelSize: maxPixelSize))
        } catch {
            outcome = .failure(error)
        }
        inFlight.remove(item.id)
        // 被取消时标记已由 cancelLoop / restartLoop 重置（可能已属于新一轮循环），不再改动
        let wasCancelled = Task.isCancelled
        if !wasCancelled { isRecognizing = false }
        lastFinished = now()
        // 已停止或已关闭：丢弃；暂停或被新一轮循环取代时结果仍然有效
        guard sessionStart != nil, settings.indexesImageText else { return }
        let milliseconds = Int((ContinuousClock.now - started) / .milliseconds(1))
        finish(item, outcome: outcome, milliseconds: milliseconds, flushNow: wasCancelled)
    }

    /// 记录结果：疑似密钥或没有文字时保存空串（标记已识别）；失败的条目本次运行不再重试
    private func finish(_ item: ClipItem, outcome: Result<String, any Error>, milliseconds: Int, flushNow: Bool) {
        switch outcome {
        case .success(let text):
            pending[item.id] = ImageTextIndexPolicy.storableText(text)
            indexedCount += 1
            logger.debug("Indexed image text in \(milliseconds, privacy: .public) ms")
            let isNew = sessionStart.map { item.createdAt >= $0 } ?? true
            if isNew || flushNow || pending.count >= Self.batchSize {
                flushPending()
            }
        case .failure(let error) where error is CancellationError:
            // 识别器在开始前发现已取消：不算失败，之后重新规划时再识别
            break
        case .failure(let error):
            failed.insert(item.id)
            logger.error("Failed to recognize text in an image: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        let texts = pending
        pending = [:]
        store.setRecognizedTexts(texts)
    }

    private func logCompletion() {
        guard indexedCount > 0 else { return }
        logger.info("Image text index is up to date (\(self.indexedCount) images indexed this session)")
        indexedCount = 0
    }

    // MARK: - 观察

    /// 读取的值变化后回调一次并重新订阅（与 AppDelegate 的设置监听同一模式）
    private func observe(
        _ read: @escaping @MainActor @Sendable () -> Void,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        withObservationTracking {
            read()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.sessionStart != nil else { return }
                self.observe(read, onChange: onChange)
                onChange()
            }
        }
    }
}
