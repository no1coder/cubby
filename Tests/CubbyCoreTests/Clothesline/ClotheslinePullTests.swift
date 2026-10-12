import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 从菜单栏往下拉显示晾衣绳：在菜单栏内刚按下左键，按住往下拖 pullDistance 以上
@Suite("ClotheslineReveal 往下拉")
struct ClotheslinePullTests {
    typealias Reveal = ClotheslineReveal
    typealias Conditions = ClotheslineReveal.Conditions

    private static let screenTop: CGFloat = 1080
    private static let menuBar: CGFloat = 24
    private static let area = CGRect(x: 0, y: 800, width: 1440, height: 250)
    private let normal = Conditions(dwell: 0.5)

    /// 一步：指针 y、左键是否按着
    private struct Step {
        let y: CGFloat
        let pressed: Bool
        var menuOpen = false
    }

    private func run(
        _ steps: [Step], from start: Reveal = .hidden, conditions: Conditions? = nil
    ) -> Reveal {
        var state = start
        for (index, step) in steps.enumerated() {
            let base = conditions ?? normal
            let sample = Reveal.PointerSample(
                location: CGPoint(x: 700, y: step.y), screenTopY: Self.screenTop, lineArea: Self.area,
                now: Double(index) * 0.05, isPressed: step.pressed, menuBarHeight: Self.menuBar)
            state = state.updated(
                with: sample,
                conditions: Conditions(
                    isEnabled: base.isEnabled, isEmpty: base.isEmpty, isFullScreenSpace: base.isFullScreenSpace,
                    dwell: base.dwell, revealsOnDwell: base.revealsOnDwell, isMenuOpen: step.menuOpen))
        }
        return state
    }

    @Test("在菜单栏内按下并往下拖够距离后显示")
    func pullShows() {
        let state = run([Step(y: 1070, pressed: false), Step(y: 1070, pressed: true), Step(y: 1040, pressed: true)])
        #expect(state.isShown)
        #expect(state.reason == .pull)
    }

    @Test("拖得不够远不显示，但仍在跟踪")
    func shortPullKeepsTracking() {
        let state = run([Step(y: 1070, pressed: true), Step(y: 1041, pressed: true)])
        #expect(!state.isShown)
        #expect(state.isTrackingPull)
    }

    @Test("中途松开就作废")
    func releaseCancels() {
        let state = run([
            Step(y: 1070, pressed: true), Step(y: 1060, pressed: true), Step(y: 1000, pressed: false),
            Step(y: 960, pressed: true),
        ])
        #expect(!state.isShown)
        #expect(!state.isTrackingPull)
    }

    @Test("在菜单栏下方按下再往下拖不算")
    func pressBelowMenuBarIgnored() {
        let state = run([Step(y: 1000, pressed: true), Step(y: 900, pressed: true)])
        #expect(!state.isShown)
    }

    @Test("在别处按下后拖进菜单栏再往下拖也不算")
    func pressElsewhereThenEnterIgnored() {
        let state = run([Step(y: 900, pressed: true), Step(y: 1075, pressed: true), Step(y: 1000, pressed: true)])
        #expect(!state.isShown)
    }

    @Test("弹出了菜单（按在菜单标题上）时作废，直到松开前都不再算")
    func menuOpenCancels() {
        let state = run([
            Step(y: 1070, pressed: true), Step(y: 1060, pressed: true, menuOpen: true),
            Step(y: 1070, pressed: true), Step(y: 1000, pressed: true),
        ])
        #expect(!state.isShown)
        let again = run(
            [Step(y: 1070, pressed: false), Step(y: 1070, pressed: true), Step(y: 1030, pressed: true)], from: state)
        #expect(again.isShown)
    }

    @Test("关掉顶边停留后仍能往下拉，停在顶边不再滑下")
    func pullWorksWithoutDwell() {
        let noDwell = Conditions(dwell: 0.5, revealsOnDwell: false)
        let resting = run(Array(repeating: Step(y: 1080, pressed: false), count: 40), conditions: noDwell)
        #expect(!resting.isShown)
        let pulled = run([Step(y: 1079, pressed: true), Step(y: 1040, pressed: true)], conditions: noDwell)
        #expect(pulled.reason == .pull)
    }

    @Test("关闭、绳上为空或全屏空间时往下拉也不显示")
    func pullRespectsConditions() {
        for conditions in [
            Conditions(isEnabled: false, dwell: 0.5), Conditions(isEmpty: true, dwell: 0.5),
            Conditions(isFullScreenSpace: true, dwell: 0.5),
        ] {
            #expect(!run([Step(y: 1070, pressed: true), Step(y: 1000, pressed: true)], conditions: conditions).isShown)
        }
    }

    @Test("拉下后指针离开绳子按离开规则收起")
    func pullHidesAfterLeaving() {
        let shown = run([Step(y: 1070, pressed: true), Step(y: 1040, pressed: true)])
        let away = CGPoint(x: 700, y: 300)
        func sample(_ now: TimeInterval) -> Reveal.PointerSample {
            Reveal.PointerSample(location: away, screenTopY: Self.screenTop, lineArea: Self.area, now: now)
        }
        let leaving = shown.updated(with: sample(1), conditions: normal)
        #expect(leaving.isShown)
        #expect(!leaving.updated(with: sample(1.6), conditions: normal).isShown)
    }

    @Test("快速拉动：刚按下的这一帧已出菜单栏时，以上一帧悬停在菜单栏的位置为起点")
    func fastPullUsesHoverPosition() {
        let state = run([Step(y: 1070, pressed: false), Step(y: 1040, pressed: true)])
        #expect(state.reason == .pull)
        let tracking = run([Step(y: 1070, pressed: false), Step(y: 1050, pressed: true)])
        #expect(tracking.isTrackingPull)
    }

    @Test("上一帧悬停在菜单栏下方时，快速拉动不算")
    func fastPullFromBelowIgnored() {
        #expect(!run([Step(y: 1040, pressed: false), Step(y: 1000, pressed: true)]).isTrackingPull)
    }

    @Test("tracksPull：只有会开始或继续跟踪的采样为真")
    func tracksPullPredicate() {
        func sample(_ y: CGFloat, pressed: Bool) -> Reveal.PointerSample {
            Reveal.PointerSample(
                location: CGPoint(x: 700, y: y), screenTopY: Self.screenTop, lineArea: Self.area, now: 0,
                isPressed: pressed, menuBarHeight: Self.menuBar)
        }
        #expect(Reveal.hidden.tracksPull(sample(1070, pressed: true)))
        #expect(!Reveal.hidden.tracksPull(sample(1070, pressed: false)))
        #expect(!Reveal.hidden.tracksPull(sample(900, pressed: true)))
        let hovering = run([Step(y: 1070, pressed: false)])
        #expect(hovering.tracksPull(sample(1040, pressed: true)))
        let shown = run([Step(y: 1070, pressed: true), Step(y: 1030, pressed: true)])
        #expect(!shown.tracksPull(sample(1070, pressed: true)))
    }

    @Test("拉下后一直按着，离开收起之后不会再次滑下，松开再拉才行")
    func holdingAfterHideDoesNotRetrigger() {
        let shown = run([Step(y: 1070, pressed: true), Step(y: 1030, pressed: true)])
        let away = CGPoint(x: 700, y: 300)
        func sample(_ y: CGFloat, _ now: TimeInterval, pressed: Bool) -> Reveal.PointerSample {
            Reveal.PointerSample(
                location: CGPoint(x: away.x, y: y), screenTopY: Self.screenTop, lineArea: Self.area, now: now,
                isPressed: pressed, menuBarHeight: Self.menuBar)
        }
        let hidden = [sample(300, 1, pressed: true), sample(300, 2, pressed: true)].reduce(shown) {
            $0.updated(with: $1, conditions: normal)
        }
        #expect(!hidden.isShown)
        let dragged = [sample(1070, 3, pressed: true), sample(1000, 3.1, pressed: true)].reduce(hidden) {
            $0.updated(with: $1, conditions: normal)
        }
        #expect(!dragged.isShown)
    }

    @Test("快捷键收起与挂图滑下保留按键状态：按着时不会被当成刚按下")
    func toggleAndPeekKeepPressedState() {
        let pressedElsewhere = run([Step(y: 900, pressed: true)])
        let toggled = pressedElsewhere.toggled(now: 1, conditions: normal).toggled(now: 1.1, conditions: normal)
        #expect(!run([Step(y: 1070, pressed: true), Step(y: 1000, pressed: true)], from: toggled).isShown)
        let peeked = pressedElsewhere.peeking(now: 1, conditions: normal)
        #expect(peeked.reason == .peek)
    }

    @Test("关掉顶边停留后，在顶边按下又松开不会滑下")
    func pressAndReleaseWithoutDwell() {
        let noDwell = Conditions(dwell: 0.5, revealsOnDwell: false)
        let state = run(
            [Step(y: 1080, pressed: true), Step(y: 1080, pressed: false), Step(y: 1080, pressed: false)],
            conditions: noDwell)
        #expect(!state.isShown)
    }

    @Test("菜单栏高度为 0（自动隐藏 / 副屏无菜单栏）时只认顶边，最大化窗口的标签页拖动不算")
    func zeroMenuBarFallsBackToEdge() {
        func pull(from y: CGFloat) -> Reveal {
            [(y, true), (y - 40, true)].reduce(Reveal.hidden) { state, step in
                state.updated(
                    with: Reveal.PointerSample(
                        location: CGPoint(x: 700, y: step.0), screenTopY: Self.screenTop, lineArea: Self.area, now: 0,
                        isPressed: step.1),
                    conditions: normal)
            }
        }
        #expect(pull(from: 1079).isShown)
        #expect(!pull(from: 1070).isShown)
    }
}
