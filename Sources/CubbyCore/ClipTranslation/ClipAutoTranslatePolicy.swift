import Foundation

/// 复制时自动翻译的资格（docs/CLIP-TRANSLATION-DESIGN.md §6，纯逻辑；默认关，只用本机系统翻译）。
/// 先用 `skipReason(for:target:conditions:)` 做只看内容与状态的检查，通过后再检测源语言，
/// 用 `languageSkipReason(source:confidence:target:)` 判定；调度见 ClipAutoTranslateQueue
public enum ClipAutoTranslatePolicy {
    /// 复制后等这么久再翻译（原型数值，§0.1 A10）
    public static let delayAfterCopy: TimeInterval = 0.5
    /// 相邻两次之间至少间隔（从上一次结束算起）
    public static let minimumInterval: TimeInterval = 1
    /// 单次翻译的超时
    public static let timeout: TimeInterval = 10
    /// 原文长度范围（UTF-16 码元）
    public static let lengthRange = 2...2000
    /// 源语言检测的最低置信度
    public static let minimumConfidence = 0.8

    /// 不自动翻译的原因
    public enum Skip: Equatable, Sendable {
        case disabled
        case paused
        case lowPowerMode
        /// 只翻译普通文本（链接、颜色、文件、图片都不自动）
        case unsupportedKind
        case code
        case length
        case noLetters
        case secret
        /// 已有该目标语言的缓存
        case cached
        /// 源语言检测不出或置信度不足
        case uncertainLanguage
        /// 原文已是目标语言
        case sameLanguage
    }

    /// 外部状态：设置开关、暂停记录、低电量模式（ProcessInfo.isLowPowerModeEnabled）
    public struct Conditions: Equatable, Sendable {
        public let isEnabled: Bool
        public let isPaused: Bool
        public let isLowPowerMode: Bool

        public init(isEnabled: Bool, isPaused: Bool, isLowPowerMode: Bool) {
            self.isEnabled = isEnabled
            self.isPaused = isPaused
            self.isLowPowerMode = isLowPowerMode
        }

        /// 可以运行：开启、未暂停、非低电量模式；否则应取消进行中与排队的任务
        public var allowsRunning: Bool {
            isEnabled && !isPaused && !isLowPowerMode
        }
    }

    /// 只看状态与内容的检查（检测源语言之前）；可以继续时为 nil
    public static func skipReason(for item: ClipItem, target: String, conditions: Conditions) -> Skip? {
        if !conditions.isEnabled { return .disabled }
        if conditions.isPaused { return .paused }
        if conditions.isLowPowerMode { return .lowPowerMode }
        guard item.kind == .text, let text = item.text else { return .unsupportedKind }
        if item.translation(for: target) != nil { return .cached }
        guard lengthRange.contains(text.utf16.count) else { return .length }
        guard text.contains(where: \.isLetter) else { return .noLetters }
        if TextHeuristics.looksLikeCode(text) { return .code }
        return SecretDetector.containsSecret(text) ? .secret : nil
    }

    /// 检测到源语言之后的检查；可以翻译时为 nil
    public static func languageSkipReason(source: String?, confidence: Double, target: String) -> Skip? {
        guard let source, confidence >= minimumConfidence else { return .uncertainLanguage }
        return ClipLanguageMatch.isSameLanguage(source, target) ? .sameLanguage : nil
    }
}

/// 语言标识的比较
public enum ClipLanguageMatch {
    /// 是否同一种语言：补全为最大形式后比较语言与文字（en-US 与 en-GB 相同；zh-Hans 与 zh-Hant 不同；zh 视为 zh-Hans）。
    /// 无法识别的标识一律视为不同
    public static func isSameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let left = maximal(lhs)
        let right = maximal(rhs)
        guard let code = left.languageCode, code == right.languageCode else { return false }
        return left.script == right.script
    }

    private static func maximal(_ identifier: String) -> Locale.Language {
        Locale.Language(identifier: Locale.Language(identifier: identifier).maximalIdentifier)
    }
}

/// 自动翻译的调度（不可变值，可注入时间）：串行执行；排队只留最新一条（连续复制时丢弃旧的）；
/// 复制后等 delayAfterCopy 才开始；两次之间至少间隔 minimumInterval（从上一次结束算起）
public struct ClipAutoTranslateQueue: Equatable, Sendable {
    /// 排队中的条目及其最早开始时间
    public struct Pending: Equatable, Sendable {
        public let id: UUID
        public let notBefore: Date
    }

    public let pending: Pending?
    /// 进行中的条目
    public let running: UUID?
    /// 上一次结束的时间（成功、失败或超时）
    public let lastFinished: Date?

    public static let idle = ClipAutoTranslateQueue(pending: nil, running: nil, lastFinished: nil)

    public enum Step: Equatable, Sendable {
        /// 没有排队的条目
        case idle
        /// 有进行中的翻译：等它结束
        case busy
        /// 等待指定秒数后重新规划
        case wait(TimeInterval)
        /// 开始翻译该条目
        case start(UUID)
    }

    private init(pending: Pending?, running: UUID?, lastFinished: Date?) {
        self.pending = pending
        self.running = running
        self.lastFinished = lastFinished
    }

    /// 新复制的条目排队（替换尚未开始的旧条目）
    public func enqueueing(_ id: UUID, copiedAt date: Date) -> ClipAutoTranslateQueue {
        ClipAutoTranslateQueue(
            pending: Pending(id: id, notBefore: date.addingTimeInterval(ClipAutoTranslatePolicy.delayAfterCopy)),
            running: running,
            lastFinished: lastFinished)
    }

    public func nextStep(now: Date) -> Step {
        guard let pending else { return .idle }
        guard running == nil else { return .busy }
        let sinceLast = lastFinished.map { now.timeIntervalSince($0) } ?? .infinity
        let interval = min(
            max(ClipAutoTranslatePolicy.minimumInterval - sinceLast, 0), ClipAutoTranslatePolicy.minimumInterval)
        let delay = min(max(pending.notBefore.timeIntervalSince(now), 0), ClipAutoTranslatePolicy.delayAfterCopy)
        let wait = max(interval, delay)
        return wait > 0 ? .wait(wait) : .start(pending.id)
    }

    /// 开始翻译排队的条目
    public func starting() -> ClipAutoTranslateQueue {
        ClipAutoTranslateQueue(pending: nil, running: pending?.id ?? running, lastFinished: lastFinished)
    }

    /// 进行中的翻译结束（任何结果）
    public func finishing(at date: Date) -> ClipAutoTranslateQueue {
        ClipAutoTranslateQueue(pending: pending, running: nil, lastFinished: date)
    }

    /// 关闭开关、暂停记录或进入低电量模式：丢弃排队的条目（进行中的由调用方取消后调用 finishing）
    public func cancellingPending() -> ClipAutoTranslateQueue {
        ClipAutoTranslateQueue(pending: nil, running: running, lastFinished: lastFinished)
    }
}
