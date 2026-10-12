import CoreGraphics
import Foundation

/// 晾衣绳是否显示的状态机（纯值，docs/UI-UPGRADE-PLAN.md 第 5 节）。
/// 应用约每秒 20 次轮询指针并调用 `updated(with:conditions:)`，快捷键 / 菜单调用 `toggled`，挂上新图片后调用 `peeking`；
/// 每次返回新的状态，内部不持有计时器。时间用单调递增的秒数（例如 `ProcessInfo.systemUptime`）。
///
/// 显示的三种方式：
/// - 切换（`.toggle`）：快捷键或菜单栏。指针还没进入过绳子区域时一直显示，直到再次切换；
///   进入过之后与其他方式一样，离开 `leaveDelay` 后收起。这样按下快捷键后指针还在别处时绳子不会自己消失。
/// - 顶边停留（`.edge`）：指针在本屏最顶部 `edgeBand` 以内连续停留 `dwell` 秒。
/// - 挂图后短暂滑下（`.peek`）：至少显示 `peekDuration` 秒；到时指针不在绳上就收起，在绳上则按离开规则收起。
///
/// 「在绳上」指指针在 `lineArea` 内或在顶边范围内（从顶边滑下后指针往往还停在菜单栏处）。
/// 关闭、全屏应用的空间、绳上为空（挂图滑下除外：挂图即说明不空）时一律收起。
/// 在顶边用切换收起后，指针要先离开顶边，停留才会重新计时，免得刚收起又滑下来。
public struct ClotheslineReveal: Equatable, Sendable {
    /// 当前显示的原因
    public enum Reason: Equatable, Sendable {
        case toggle
        case edge
        case peek
    }

    /// 每次调用时由应用提供的外部条件
    public struct Conditions: Equatable, Sendable {
        public let isEnabled: Bool
        /// 绳上没有图片
        public let isEmpty: Bool
        /// 当前是全屏应用的空间
        public let isFullScreenSpace: Bool
        /// 指针在顶边停留多久后滑下（秒，来自 AppSettings.clotheslineDwell）；负数按 0 处理
        public let dwell: TimeInterval

        public init(
            isEnabled: Bool = true,
            isEmpty: Bool = false,
            isFullScreenSpace: Bool = false,
            dwell: TimeInterval
        ) {
            self.isEnabled = isEnabled
            self.isEmpty = isEmpty
            self.isFullScreenSpace = isFullScreenSpace
            self.dwell = dwell
        }
    }

    /// 一次指针采样
    public struct PointerSample: Equatable, Sendable {
        /// 指针位置（AppKit 屏幕坐标，y 向上）
        public let location: CGPoint
        /// 指针所在屏幕的顶边 y（`NSScreen.frame.maxY`）
        public let screenTopY: CGFloat
        /// 绳子区域（绳窗口的 frame；可向上延伸到屏幕顶边，把菜单栏那一条也算作绳上）
        public let lineArea: CGRect
        /// 单调时间（秒）
        public let now: TimeInterval

        public init(location: CGPoint, screenTopY: CGFloat, lineArea: CGRect, now: TimeInterval) {
            self.location = location
            self.screenTopY = screenTopY
            self.lineArea = lineArea
            self.now = now
        }

        /// 在本屏顶部 edgeBand 以内（含边界）；高出本屏顶边说明在另一块屏幕上，不算
        var isAtTopEdge: Bool {
            location.y <= screenTopY && location.y >= screenTopY - ClotheslineReveal.edgeBand
        }

        var isOverLine: Bool {
            isAtTopEdge || lineArea.contains(location)
        }
    }

    /// 屏幕最顶部多少 pt 算「顶边」
    public static let edgeBand: CGFloat = 2
    /// 指针离开绳子区域多久后收起（秒）
    public static let leaveDelay: TimeInterval = 0.6
    /// 挂上新图片后至少显示多久（秒）
    public static let peekDuration: TimeInterval = 2.5
    /// 时间比较的容差：抵消浮点误差（例如 11.1 − 10.5 略小于 0.6）
    static let timeTolerance: TimeInterval = 1e-6

    public static let hidden = ClotheslineReveal()

    /// nil 表示收起
    public let reason: Reason?
    /// 收起时：指针从何时起连续停在顶边
    let edgeSince: TimeInterval?
    /// 显示时：指针从何时起不在绳上
    let outsideSince: TimeInterval?
    /// 显示后指针是否进入过绳子区域
    let hasEntered: Bool
    /// 挂图滑下：在此之前一定显示
    let peekUntil: TimeInterval?
    /// 在顶边用切换收起后，等指针离开顶边才重新计时停留
    let waitsForEdgeExit: Bool

    private init(
        reason: Reason? = nil,
        edgeSince: TimeInterval? = nil,
        outsideSince: TimeInterval? = nil,
        hasEntered: Bool = false,
        peekUntil: TimeInterval? = nil,
        waitsForEdgeExit: Bool = false
    ) {
        self.reason = reason
        self.edgeSince = edgeSince
        self.outsideSince = outsideSince
        self.hasEntered = hasEntered
        self.peekUntil = peekUntil
        self.waitsForEdgeExit = waitsForEdgeExit
    }

    public var isShown: Bool {
        reason != nil
    }

    // MARK: - 事件

    /// 一次指针采样后的状态
    public func updated(with sample: PointerSample, conditions: Conditions) -> ClotheslineReveal {
        guard Self.allowsShowing(conditions) else { return .hidden }
        return isShown ? updatedWhileShown(sample) : updatedWhileHidden(sample, dwell: conditions.dwell)
    }

    /// 快捷键 / 菜单切换：显示中（任何原因）则收起，收起时则显示（关闭、全屏空间或绳上为空时保持收起）
    public func toggled(now: TimeInterval, conditions: Conditions) -> ClotheslineReveal {
        if isShown {
            return ClotheslineReveal(waitsForEdgeExit: true)
        }
        guard Self.allowsShowing(conditions) else { return .hidden }
        return ClotheslineReveal(reason: .toggle)
    }

    /// 挂上新图片后短暂滑下（不看 isEmpty：刚挂上说明绳上有图）。已在显示时保持原因，只保证至少再显示 peekDuration
    public func peeking(now: TimeInterval, conditions: Conditions) -> ClotheslineReveal {
        guard conditions.isEnabled, !conditions.isFullScreenSpace else { return .hidden }
        return ClotheslineReveal(
            reason: reason ?? .peek, outsideSince: outsideSince, hasEntered: isShown && hasEntered,
            peekUntil: now + Self.peekDuration)
    }

    // MARK: - 内部规则

    private static func allowsShowing(_ conditions: Conditions) -> Bool {
        conditions.isEnabled && !conditions.isEmpty && !conditions.isFullScreenSpace
    }

    private static func hasElapsed(_ duration: TimeInterval, since start: TimeInterval, now: TimeInterval) -> Bool {
        now - start >= duration - timeTolerance
    }

    private func updatedWhileHidden(_ sample: PointerSample, dwell: TimeInterval) -> ClotheslineReveal {
        guard sample.isAtTopEdge else { return .hidden }
        guard !waitsForEdgeExit else { return self }
        let since = edgeSince ?? sample.now
        guard Self.hasElapsed(max(dwell, 0), since: since, now: sample.now) else {
            return ClotheslineReveal(edgeSince: since)
        }
        return ClotheslineReveal(reason: .edge, hasEntered: true)
    }

    private func updatedWhileShown(_ sample: PointerSample) -> ClotheslineReveal {
        let now = sample.now
        if sample.isOverLine {
            return ClotheslineReveal(reason: reason, hasEntered: true, peekUntil: activePeek(at: now))
        }
        let outside = outsideSince ?? now
        let keep = ClotheslineReveal(
            reason: reason, outsideSince: outside, hasEntered: hasEntered, peekUntil: activePeek(at: now))
        if keep.peekUntil != nil { return keep }
        guard hasEntered else {
            // 指针从未进入：切换的一直显示，挂图滑下的到时收起
            return reason == .toggle ? keep : .hidden
        }
        return Self.hasElapsed(Self.leaveDelay, since: outside, now: now) ? .hidden : keep
    }

    /// 尚未到时的挂图滑下截止时间
    private func activePeek(at now: TimeInterval) -> TimeInterval? {
        guard let peekUntil, !Self.hasElapsed(0, since: peekUntil, now: now) else { return nil }
        return peekUntil
    }
}
