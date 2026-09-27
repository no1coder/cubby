import AppKit
import CubbyCore

/// 覆盖层期间的本地键盘监听（§3.4.5）：把 keyDown / keyUp / flagsChanged 交给 Core 的 `ScreenshotKeyboard` 解释
///
/// 解释规则（组字放行、空格作修饰键、非编辑阶段吞掉所有按键、编辑时只放行编辑类 ⌘ 组合）都在 Core，有单元测试；
/// 这里只负责监听、取出 NSEvent 的字段、按结果吞掉或放行事件。
@MainActor
final class OverlayKeyboard {
    /// 事件的上下文：当前阶段、编辑器是否在组字
    struct Context {
        let phase: ScreenshotPhase
        let isComposingText: Bool
    }

    var context: () -> Context = { Context(phase: .hovering, isComposingText: false) }
    var owns: (NSWindow?) -> Bool = { _ in false }
    var onOutput: ((ScreenshotKeyOutput) -> Void)?

    private var monitor: Any?
    private var state = ScreenshotKeyboard()

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        state.reset()
    }

    /// 焦点离开期间（例如系统弹窗抢走 key）的松开事件到不了 Cubby：覆盖层重新成为 key 时调用，
    /// 修饰键以系统当前状态为准，空格视为已松开；有变化才上报
    func resynchronize() {
        emit(state.resynchronize(flags: NSEvent.modifierFlags, phase: context().phase))
    }

    /// 返回 true 表示已处理、不再传递。
    /// 修饰键与空格的松开不看窗口：按住期间 key 可能已转到 Cubby 的其他窗口，松开落在那里也要同步，
    /// 否则会话里会残留按下状态（例如一直是正方形约束、一直在平移选区）
    private func handle(_ event: NSEvent) -> Bool {
        let context = context()
        let decision: ScreenshotKeyDecision
        switch event.type {
        case .flagsChanged:
            decision = state.flagsChanged(event.modifierFlags, phase: context.phase)
        case .keyDown:
            let input = ScreenshotKeyInput(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                isRepeat: event.isARepeat,
                isOverlayWindow: owns(event.window)
            )
            decision = state.keyDown(input, phase: context.phase, isComposingText: context.isComposingText)
        case .keyUp:
            decision = state.keyUp(keyCode: event.keyCode, phase: context.phase)
        default:
            return false
        }
        return emit(decision)
    }

    @discardableResult
    private func emit(_ decision: ScreenshotKeyDecision) -> Bool {
        decision.outputs.forEach { onOutput?($0) }
        return decision.consumed
    }
}
