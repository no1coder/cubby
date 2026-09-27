import Foundation

/// 图片文字索引的保存规则（纯逻辑；Vision 识别与调度执行在 App 层 ImageTextIndexer）
public enum ImageTextIndexPolicy {
    /// 每张图片最多保存的字符数：足以覆盖整屏文字，又不让历史文件膨胀
    public static let maxTextLength = 10_000
    /// 识别前的像素面积上限（约 4K：3840×2160）：更大的图片先等比缩小，控制耗时与内存
    public static let maxPixelArea = 3840 * 2160

    /// 识别结果 → 要保存的文字：去掉首尾空白并截断到 maxTextLength 个字符。
    /// 疑似密钥时返回空串：不保存文字，但标记为已识别，避免每次启动重复识别
    public static func storableText(_ recognized: String) -> String {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SecretDetector.containsSecret(trimmed) else { return "" }
        return trimmed.count > maxTextLength ? String(trimmed.prefix(maxTextLength)) : trimmed
    }

    /// 超大图片等比缩放后的最长边（像素）；不需要缩放或尺寸非法时返回 nil
    public static func recognitionMaxPixelSize(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let area = Double(width) * Double(height)
        guard area > Double(maxPixelArea) else { return nil }
        let scale = (Double(maxPixelArea) / area).squareRoot()
        return max(Int((Double(max(width, height)) * scale).rounded(.down)), 1)
    }
}

/// 图片文字索引的调度（纯逻辑，可注入时间）：决定下一步识别哪张图片、何时识别。
/// - 关闭或暂停记录时停止；
/// - 队列按历史顺序（最新在前），只取未识别（recognizedText 为 nil）且本次运行未失败的图片；
/// - 本次运行中新记录的图片立即识别；启动前已有的图片（回填）先等启动延迟，之后逐条间隔进行
public struct ImageTextIndexSchedule: Equatable, Sendable {
    /// 启动后多久开始回填，避开启动高峰（秒）
    public let startupDelay: TimeInterval
    /// 回填时相邻两次识别之间的最小间隔（秒）
    public let backfillInterval: TimeInterval

    public static let standard = ImageTextIndexSchedule(startupDelay: 10, backfillInterval: 2)

    public init(startupDelay: TimeInterval, backfillInterval: TimeInterval) {
        self.startupDelay = startupDelay
        self.backfillInterval = backfillInterval
    }

    /// 调度所需的外部状态
    public struct State: Equatable, Sendable {
        public let isEnabled: Bool
        public let isPaused: Bool
        /// 索引器本次启动的时间：此后记录的图片视为新图片
        public let sessionStart: Date
        public let now: Date
        /// 上一次识别结束的时间（成功或失败）；nil 表示本次运行尚未识别过
        public let lastFinished: Date?
        /// 本次运行中识别失败、不再重试的条目
        public let skipped: Set<UUID>

        public init(
            isEnabled: Bool,
            isPaused: Bool,
            sessionStart: Date,
            now: Date,
            lastFinished: Date?,
            skipped: Set<UUID>
        ) {
            self.isEnabled = isEnabled
            self.isPaused = isPaused
            self.sessionStart = sessionStart
            self.now = now
            self.lastFinished = lastFinished
            self.skipped = skipped
        }
    }

    public enum Step: Equatable, Sendable {
        /// 已关闭或暂停记录：停止，等设置变化
        case stop
        /// 没有待识别的图片：等历史变化
        case idle
        /// 回填节流：等待指定秒数后重新规划
        case wait(TimeInterval)
        /// 识别该条目
        case recognize(ClipItem)
    }

    public func nextStep(items: [ClipItem], state: State) -> Step {
        guard state.isEnabled, !state.isPaused else { return .stop }
        guard let item = items.first(where: { Self.needsRecognition($0, skipping: state.skipped) }) else {
            return .idle
        }
        guard item.createdAt < state.sessionStart else { return .recognize(item) }
        let remaining = backfillWait(state)
        return remaining > 0 ? .wait(remaining) : .recognize(item)
    }

    /// 待识别的图片（按历史顺序）
    public static func pending(in items: [ClipItem], skipping skipped: Set<UUID>) -> [ClipItem] {
        items.filter { needsRecognition($0, skipping: skipped) }
    }

    private static func needsRecognition(_ item: ClipItem, skipping skipped: Set<UUID>) -> Bool {
        item.kind == .image && item.recognizedText == nil && !skipped.contains(item.id)
    }

    /// 回填还需等待的秒数：启动延迟与逐条间隔取较长者；各自限制在自身时长内，时钟回拨时不会无限等待
    private func backfillWait(_ state: State) -> TimeInterval {
        let sinceStart = state.now.timeIntervalSince(state.sessionStart)
        let startup = min(max(startupDelay - sinceStart, 0), startupDelay)
        let sinceLast = state.lastFinished.map { state.now.timeIntervalSince($0) } ?? .infinity
        let interval = min(max(backfillInterval - sinceLast, 0), backfillInterval)
        return max(startup, interval)
    }
}
