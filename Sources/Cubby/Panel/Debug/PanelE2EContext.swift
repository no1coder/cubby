#if DEBUG
import AppKit
import CubbyCore

/// 一条面板脚本：名称、说明、环境选项与脚本体（动作抛错即中止本脚本，检查只记录结果）
struct PanelE2EScenario {
    let name: String
    let summary: String
    var options = PanelE2EWorld.Options()
    let run: @MainActor (PanelE2EContext) async throws -> Void
}

enum PanelE2EError: Error, CustomStringConvertible {
    case missingItem(String)
    case missingAnchor(String)
    case timedOut(String)

    var description: String {
        switch self {
        case .missingItem(let key): "no fixture item \(key)"
        case .missingAnchor(let name): "view \(name) is not on screen"
        case .timedOut(let what): "timed out waiting for \(what)"
        }
    }
}

/// 脚本运行时的上下文：环境、合成输入与检查结果
@MainActor
final class PanelE2EContext {
    let world: PanelE2EWorld
    let driver: E2EEventDriver
    private(set) var passed = 0
    private(set) var failures: [String] = []

    init(world: PanelE2EWorld, driver: E2EEventDriver) {
        self.world = world
        self.driver = driver
    }

    // MARK: - 状态

    var viewModel: PanelViewModel {
        world.viewModel
    }

    var translation: ClipTranslationController? {
        viewModel.translation
    }

    var card: TranslationCard? {
        translation?.card.card
    }

    var stub: PanelE2EStubTranslator? {
        world.translator
    }

    var detailWindow: NSWindow {
        world.panel.debugDetailWindow
    }

    var panelWindow: NSWindow {
        world.panel.debugPanelWindow
    }

    func item(_ key: String) throws -> ClipItem {
        guard let item = world.item(key) else { throw PanelE2EError.missingItem(key) }
        return item
    }

    // MARK: - 动作

    /// 显示面板并选中某条（按 key）
    func open(selecting key: String? = nil) async throws {
        world.panel.show()
        try await settle()
        if let key { try select(key) }
        try await settle()
    }

    func select(_ key: String) throws {
        viewModel.select(try item(key))
    }

    func press(_ key: E2EKey, _ flags: NSEvent.ModifierFlags = []) async throws {
        try await ensureKey()
        try await driver.press(key, flags: flags)
    }

    /// 别的应用（例如运行期间用户点了别处）抢走 key 时，像用户点回面板一样让面板重新成为 key
    private func ensureKey() async throws {
        guard world.panel.debugIsShown, !panelWindow.isKeyWindow else { return }
        panelWindow.makeKey()
        try await settle(.milliseconds(50))
        guard !panelWindow.isKeyWindow else { return }
        // 协作式激活：别的应用在前台且用户正在操作时，未激活应用的面板拿不到 key。
        // 与截图 E2E 相同，退而激活 Cubby 再让面板成为 key（只影响测试驱动，面板的按键路由不变）
        NSApp.activate()
        panelWindow.makeKey()
        try await settle(.milliseconds(100))
    }

    func command(_ character: Character, shift: Bool = false) async throws {
        try await press(.character(character), shift ? [.command, .shift] : .command)
    }

    /// 按住 / 松开 ⌥（flagsChanged）
    func holdOption(_ held: Bool) async throws {
        try await ensureKey()
        try await driver.setModifiers(held ? .option : [])
    }

    /// 点击锚点（先在主面板找，再在详情区找）
    func click(_ anchor: String) async throws {
        let point = try point(of: anchor)
        if ProcessInfo.processInfo.environment["CUBBY_E2E_VERBOSE"] == "1" {
            E2EReport.line("      . click \(anchor) at \(point): \(Self.hitChain(at: point))")
        }
        try await driver.click(at: point)
    }

    /// 点击位置命中的视图链与各自是否接受 first mouse（排查非 key 窗口里的点击，R1）
    private static func hitChain(at point: CGPoint) -> String {
        guard let window = E2EEventDriver.window(at: point), let content = window.contentView else {
            return "no window"
        }
        let windowPoint = window.convertPoint(fromScreen: ScreenTopologyProvider.toAppKit(point))
        var view = content.hitTest(content.convert(windowPoint, from: nil))
        var chain: [String] = []
        while let current = view {
            chain.append("\(type(of: current))(\(current.acceptsFirstMouse(for: nil)))")
            view = current.superview
        }
        return "\(type(of: window)) key=\(window.isKeyWindow): " + chain.joined(separator: " < ")
    }

    /// 锚点所在的窗口：「card.」开头的在详情区（翻译卡），其余在主面板
    func window(of anchor: String) -> NSWindow {
        anchor.hasPrefix("card.") ? detailWindow : panelWindow
    }

    func point(of anchor: String) throws -> CGPoint {
        let window = window(of: anchor)
        guard window.isVisible, let point = PanelE2EAnchors.shared.center(of: anchor, in: window) else {
            throw PanelE2EError.missingAnchor(anchor)
        }
        return point
    }

    func frame(of anchor: String, in window: NSWindow) throws -> CGRect {
        guard let frame = PanelE2EAnchors.shared.frame(of: anchor, in: window) else {
            throw PanelE2EError.missingAnchor(anchor)
        }
        return frame
    }

    /// 悬停：跟踪区域按真实光标位置判断，合成的 mouseMoved 触发不了它，所以把全局点直接交给详情区里
    /// 包含该点的跟踪视图（图片译文层、对照视图的指针跟踪）
    func hover(at point: CGPoint?) {
        let window = detailWindow
        let windowPoint = point.map { window.convertPoint(fromScreen: ScreenTopologyProvider.toAppKit($0)) }
        for view in Self.descendants(of: window.contentView) {
            let inside = windowPoint.map { view.bounds.contains(view.convert($0, from: nil)) } ?? true
            if let overlay = view as? TranslationOverlayNSView {
                overlay.debugHover(atWindowPoint: inside ? windowPoint : nil)
            } else if let tracker = view as? PointerTracker.TrackingView {
                tracker.debugMove(toWindowPoint: inside ? windowPoint : nil)
            }
        }
    }

    private static func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    func hasAnchor(_ anchor: String) -> Bool {
        PanelE2EAnchors.shared.contains(anchor)
    }

    /// 让出运行循环，等 SwiftUI 与布局更新
    func settle(_ duration: Duration = .milliseconds(120)) async throws {
        try await driver.flush()
        try? await Task.sleep(for: duration)
    }

    /// 等待条件成立，超时即中止脚本
    func wait(_ what: String, timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async throws {
        guard await poll(timeout: timeout, condition) else { throw PanelE2EError.timedOut(what) }
    }

    func waitForCard(_ phase: TranslationCardPhase, timeout: Duration = .seconds(5)) async throws {
        try await wait("card phase \(phase)", timeout: timeout) { self.card?.phase == phase }
    }

    // MARK: - 检查

    func check(_ title: String, _ ok: Bool, detail: @autoclosure () -> String = "") {
        if ok {
            passed += 1
            E2EReport.line("    PASS  \(title)")
        } else {
            let message = detail()
            let line = message.isEmpty ? title : "\(title) -- \(message)"
            failures.append(line)
            E2EReport.line("    FAIL  \(line)")
        }
    }

    func checkEqual<Value: Equatable>(_ title: String, _ expected: Value, _ actual: Value?) {
        check(title, actual == expected, detail: "expected \(expected), got \(actual.map { "\($0)" } ?? "nil")")
    }

    /// 最终一致的检查：在超时内轮询
    func eventually(
        _ title: String, timeout: Duration = .seconds(5), detail: @MainActor () -> String = { "" },
        _ condition: @MainActor () -> Bool
    ) async {
        let ok = await poll(timeout: timeout, condition)
        check(title, ok, detail: detail())
    }

    /// 新出现的 HUD 文案里包含 text
    func expectHUD(containing text: String) async {
        var seen = ""
        await eventually("HUD shows \"\(text)\"", detail: { "HUD: \(seen)" }) {
            seen = E2EInspect.visibleHUD()?.text ?? "none"
            return seen.contains(text)
        }
    }

    func poll(timeout: Duration, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
#endif
