import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 晾衣绳何时显示（docs/UI-UPGRADE-PLAN.md 第 5 节）：顶边停留、快捷键切换、挂图后短暂滑下，离开 0.6 秒收起
@Suite("ClotheslineReveal 显示与收起")
struct ClotheslineRevealTests {
    typealias Reveal = ClotheslineReveal
    typealias Conditions = ClotheslineReveal.Conditions

    /// 1440 × 1080 的屏幕，绳窗口在菜单栏下方
    private static let screenTop: CGFloat = 1080
    private static let area = CGRect(x: 0, y: 800, width: 1440, height: 250)
    private let edge = CGPoint(x: 700, y: 1079)
    private let inside = CGPoint(x: 700, y: 900)
    private let away = CGPoint(x: 700, y: 300)
    private let normal = Conditions(dwell: 0.5)

    private func sample(
        _ location: CGPoint, at now: TimeInterval, top: CGFloat = screenTop, area: CGRect = area
    ) -> Reveal.PointerSample {
        Reveal.PointerSample(location: location, screenTopY: top, lineArea: area, now: now)
    }

    /// 依次喂入指针位置，返回最后的状态
    private func run(
        _ steps: [(CGPoint, TimeInterval)], from start: Reveal = .hidden, conditions: Conditions? = nil
    ) -> Reveal {
        steps.reduce(start) { state, step in
            state.updated(with: sample(step.0, at: step.1), conditions: conditions ?? normal)
        }
    }

    /// 指针在顶边停留足够久、刚显示出来的状态（时间 0…0.5）
    private var shownByEdge: Reveal {
        run([(edge, 0), (edge, 0.5)])
    }

    // MARK: - 常量与初始状态

    @Test("规则常量与设计一致")
    func constants() {
        #expect(Reveal.edgeBand == 2)
        #expect(Reveal.leaveDelay == 0.6)
        #expect(Reveal.peekDuration == 2.5)
    }

    @Test("初始为收起")
    func startsHidden() {
        #expect(!Reveal.hidden.isShown)
        #expect(Reveal.hidden.reason == nil)
    }

    // MARK: - 顶边停留

    @Test("停留未满时长不显示，恰好满时长时显示")
    func dwellThreshold() {
        #expect(!run([(edge, 0), (edge, 0.25), (edge, 0.49)]).isShown)
        let shown = run([(edge, 10), (edge, 10.5)])
        #expect(shown.isShown)
        #expect(shown.reason == .edge)
    }

    @Test("第一次到达顶边只开始计时，不会立即显示")
    func firstSampleOnlyStartsTimer() {
        #expect(!run([(edge, 0)]).isShown)
    }

    @Test("停留时长取自设置", arguments: [0.3, 0.8, 1.2])
    func customDwell(_ dwell: TimeInterval) {
        let conditions = Conditions(dwell: dwell)
        #expect(!run([(edge, 0), (edge, dwell - 0.01)], conditions: conditions).isShown)
        #expect(run([(edge, 0), (edge, dwell)], conditions: conditions).isShown)
    }

    @Test("停留时长为 0 或负数时到达顶边即显示", arguments: [0.0, -1.0])
    func zeroDwell(_ dwell: TimeInterval) {
        #expect(run([(edge, 0)], conditions: Conditions(dwell: dwell)).isShown)
    }

    @Test("停留中途离开顶边会重新计时")
    func movingAwayResetsDwell() {
        let steps: [(CGPoint, TimeInterval)] = [(edge, 0), (edge, 0.3), (away, 0.35), (edge, 0.4), (edge, 0.85)]
        #expect(!run(steps).isShown)
        #expect(run(steps + [(edge, 0.9)]).isShown)
    }

    @Test("沿着顶边左右移动不打断计时")
    func movingAlongEdgeKeepsDwell() {
        #expect(run([(CGPoint(x: 10, y: 1079), 0), (CGPoint(x: 1300, y: 1080), 0.5)]).isShown)
    }

    @Test(
        "顶边范围：距顶 2pt 以内（含）算顶边，更低或高出本屏顶边都不算",
        arguments: [
            (1080.0, true), (1079.5, true), (1078.0, true), (1077.99, false), (1000.0, false), (1081.0, false),
        ])
    func edgeBand(_ y: CGFloat, _ isEdge: Bool) {
        let point = CGPoint(x: 700, y: y)
        #expect(run([(point, 0), (point, 0.5)]).isShown == isEdge)
    }

    @Test("多块屏幕：按指针所在屏幕的顶边判断")
    func multipleScreens() {
        let tallTop: CGFloat = 1440
        let tallArea = CGRect(x: 1440, y: 1160, width: 1920, height: 250)
        let onTall = CGPoint(x: 2000, y: 1439)
        let tall = [onTall, onTall].enumerated().reduce(Reveal.hidden) { state, step in
            state.updated(
                with: sample(step.element, at: Double(step.offset) * 0.5, top: tallTop, area: tallArea),
                conditions: normal)
        }
        #expect(tall.isShown)

        // 同样的高度在较高的屏幕上离顶边很远
        let low = CGPoint(x: 2000, y: 1079)
        let notEdge = [low, low].enumerated().reduce(Reveal.hidden) { state, step in
            state.updated(
                with: sample(step.element, at: Double(step.offset) * 0.5, top: tallTop, area: tallArea),
                conditions: normal)
        }
        #expect(!notEdge.isShown)
    }

    // MARK: - 离开收起

    @Test("离开绳子区域满 0.6 秒收起，未满时仍显示")
    func leaveDelay() {
        let entered = run([(inside, 1)], from: shownByEdge)
        #expect(run([(away, 2), (away, 2.59)], from: entered).isShown)
        let hidden = run([(away, 2), (away, 2.6)], from: entered)
        #expect(!hidden.isShown)
        #expect(hidden.reason == nil)
    }

    @Test("离开后 0.6 秒内回来保持显示，再次离开重新计时")
    func reenteringKeepsShown() {
        let steps: [(CGPoint, TimeInterval)] = [(inside, 1), (away, 2), (inside, 2.3), (away, 2.5), (away, 3.0)]
        #expect(run(steps, from: shownByEdge).isShown)
        #expect(!run(steps + [(away, 3.1)], from: shownByEdge).isShown)
    }

    @Test("指针一直停在顶边（菜单栏处）时不收起")
    func restingAtEdgeKeepsShown() {
        #expect(run([(edge, 5), (edge, 60)], from: shownByEdge).isShown)
    }

    @Test("收起后回到顶边要重新停留满时长")
    func hiddenNeedsFullDwellAgain() {
        let hidden = run([(away, 1), (away, 1.6)], from: shownByEdge)
        #expect(!hidden.isShown)
        #expect(!run([(edge, 2), (edge, 2.4)], from: hidden).isShown)
        #expect(run([(edge, 2), (edge, 2.5)], from: hidden).isShown)
    }

    // MARK: - 快捷键 / 菜单切换

    @Test("切换：收起 → 显示 → 收起")
    func toggling() {
        let shown = Reveal.hidden.toggled(now: 0, conditions: normal)
        #expect(shown.isShown)
        #expect(shown.reason == .toggle)
        #expect(!shown.toggled(now: 1, conditions: normal).isShown)
    }

    @Test("切换显示后指针从未进入绳子区域时一直显示，直到再次切换")
    func toggleStaysUntilEntered() {
        let shown = Reveal.hidden.toggled(now: 0, conditions: normal)
        let later = run([(away, 0.1), (away, 5), (away, 120)], from: shown)
        #expect(later.isShown)
        #expect(!later.toggled(now: 121, conditions: normal).isShown)
    }

    @Test("切换显示后指针进入再离开：0.6 秒后收起")
    func toggleHidesAfterEnteringAndLeaving() {
        let shown = Reveal.hidden.toggled(now: 0, conditions: normal)
        let steps: [(CGPoint, TimeInterval)] = [(away, 1), (inside, 2), (away, 3)]
        #expect(run(steps + [(away, 3.59)], from: shown).isShown)
        #expect(!run(steps + [(away, 3.6)], from: shown).isShown)
    }

    @Test("切换时指针已在绳子区域：离开后照常收起")
    func toggleWithPointerInside() {
        let shown = Reveal.hidden.toggled(now: 0, conditions: normal)
        #expect(!run([(inside, 0.05), (away, 1), (away, 1.6)], from: shown).isShown)
    }

    @Test("顶边触发的显示也能被切换收起")
    func toggleHidesEdgeReveal() {
        #expect(!shownByEdge.toggled(now: 1, conditions: normal).isShown)
    }

    @Test("在顶边切换收起后，指针不离开顶边就不会再次滑下")
    func toggleHideSuppressesEdgeUntilExit() {
        let hidden = run([(edge, 1)], from: shownByEdge).toggled(now: 1, conditions: normal)
        #expect(!run([(edge, 1.1), (edge, 3), (edge, 10)], from: hidden).isShown)
        // 离开顶边后重新停留即可
        #expect(run([(edge, 1.1), (away, 2), (edge, 3), (edge, 3.5)], from: hidden).isShown)
    }

    @Test(
        "关闭、绳上为空或处于全屏空间时切换不显示",
        arguments: [
            Conditions(isEnabled: false, dwell: 0.5),
            Conditions(isEmpty: true, dwell: 0.5),
            Conditions(isFullScreenSpace: true, dwell: 0.5),
        ])
    func toggleBlocked(_ conditions: Conditions) {
        #expect(!Reveal.hidden.toggled(now: 0, conditions: conditions).isShown)
    }

    // MARK: - 挂图后短暂滑下

    @Test("挂图后滑下 2.5 秒，指针不在绳上时到时收起")
    func peekExpires() {
        let peek = Reveal.hidden.peeking(now: 0, conditions: normal)
        #expect(peek.isShown)
        #expect(peek.reason == .peek)
        #expect(run([(away, 0.1), (away, 2.49)], from: peek).isShown)
        #expect(!run([(away, 0.1), (away, 2.5)], from: peek).isShown)
    }

    @Test("短暂滑下期间指针停在绳上：到时不收起，离开 0.6 秒后才收起")
    func peekWithHover() {
        let peek = Reveal.hidden.peeking(now: 0, conditions: normal)
        let hovering = run([(inside, 1), (inside, 2.5), (inside, 10)], from: peek)
        #expect(hovering.isShown)
        #expect(run([(away, 10.5), (away, 11.09)], from: hovering).isShown)
        #expect(!run([(away, 10.5), (away, 11.1)], from: hovering).isShown)
    }

    @Test("短暂滑下期间进入后很快离开：仍显示到 2.5 秒")
    func peekHoldsUntilExpiryEvenAfterLeaving() {
        let peek = Reveal.hidden.peeking(now: 0, conditions: normal)
        let steps: [(CGPoint, TimeInterval)] = [(inside, 0.5), (away, 1), (away, 1.7)]
        #expect(run(steps, from: peek).isShown)
        #expect(!run(steps + [(away, 2.5)], from: peek).isShown)
    }

    @Test("挂图即说明绳上有图：滑下不看 isEmpty")
    func peekIgnoresEmptyFlag() {
        #expect(Reveal.hidden.peeking(now: 0, conditions: Conditions(isEmpty: true, dwell: 0.5)).isShown)
    }

    @Test(
        "关闭或处于全屏空间时挂图不滑下",
        arguments: [
            Conditions(isEnabled: false, dwell: 0.5),
            Conditions(isFullScreenSpace: true, dwell: 0.5),
        ])
    func peekBlocked(_ conditions: Conditions) {
        #expect(!Reveal.hidden.peeking(now: 0, conditions: conditions).isShown)
    }

    @Test("切换显示时挂图：保持切换的规则，不会 2.5 秒后收起")
    func peekWhileToggledKeepsToggle() {
        let shown = Reveal.hidden.toggled(now: 0, conditions: normal).peeking(now: 1, conditions: normal)
        #expect(shown.reason == .toggle)
        #expect(run([(away, 2), (away, 10)], from: shown).isShown)
    }

    @Test("顶边显示时挂图：至少再显示 2.5 秒")
    func peekWhileEdgeShownExtends() {
        let shown = run([(inside, 0.6)], from: shownByEdge).peeking(now: 1, conditions: normal)
        #expect(shown.reason == .edge)
        #expect(run([(away, 1.1), (away, 3.49)], from: shown).isShown)
        #expect(!run([(away, 1.1), (away, 3.5)], from: shown).isShown)
    }

    @Test("短暂滑下时再切换：收起")
    func toggleDuringPeekHides() {
        #expect(!Reveal.hidden.peeking(now: 0, conditions: normal).toggled(now: 1, conditions: normal).isShown)
    }

    // MARK: - 不显示的情形

    @Test(
        "关闭、绳上为空或全屏空间时顶边停留不触发",
        arguments: [
            Conditions(isEnabled: false, dwell: 0.5),
            Conditions(isEmpty: true, dwell: 0.5),
            Conditions(isFullScreenSpace: true, dwell: 0.5),
        ])
    func edgeBlocked(_ conditions: Conditions) {
        #expect(!run([(edge, 0), (edge, 0.5), (edge, 5)], conditions: conditions).isShown)
    }

    @Test(
        "显示中变为关闭、绳上为空或全屏空间时立即收起",
        arguments: [
            Conditions(isEnabled: false, dwell: 0.5),
            Conditions(isEmpty: true, dwell: 0.5),
            Conditions(isFullScreenSpace: true, dwell: 0.5),
        ])
    func blockedWhileShownHides(_ conditions: Conditions) {
        let toggled = Reveal.hidden.toggled(now: 0, conditions: normal)
        let peek = Reveal.hidden.peeking(now: 0, conditions: normal)
        for shown in [shownByEdge, toggled, peek] {
            let next = shown.updated(with: sample(inside, at: 0.6), conditions: conditions)
            #expect(!next.isShown)
            #expect(next == .hidden)
        }
    }

    @Test("离开全屏空间后，顶边停留从那一刻重新计时")
    func leavingFullScreenRestartsDwell() {
        let fullScreen = Conditions(isFullScreenSpace: true, dwell: 0.5)
        let blocked = run([(edge, 0), (edge, 1)], conditions: fullScreen)
        #expect(!run([(edge, 1.2)], from: blocked).isShown)
        #expect(run([(edge, 1.2), (edge, 1.7)], from: blocked).isShown)
    }

    @Test("绳上从空变为有图后，顶边停留从那一刻开始计时")
    func becomingNonEmptyStartsDwell() {
        let empty = run([(edge, 0), (edge, 3)], conditions: Conditions(isEmpty: true, dwell: 0.5))
        #expect(!run([(edge, 3.1)], from: empty).isShown)
        #expect(run([(edge, 3.1), (edge, 3.6)], from: empty).isShown)
    }
}
