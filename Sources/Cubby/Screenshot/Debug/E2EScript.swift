#if DEBUG
import AppKit
import CubbyCore

/// 一条端到端脚本：名称、说明、环境选项与声明式的步骤列表
struct E2EScenario {
    let name: String
    let summary: String
    var options = E2EWorld.Options()
    let steps: [E2EStep]
}

/// 脚本中的一步：动作（出错即中止本脚本）或检查（记录结果后继续）
struct E2EStep {
    enum Kind {
        case action
        case check
    }

    let title: String
    let kind: Kind
    let body: @MainActor (E2EContext) async throws -> Void
}

/// 脚本中的点：主屏局部点，或运行时按会话状态计算的全局点
struct E2EPoint {
    let resolve: @MainActor (E2EContext) throws -> CGPoint

    /// 主屏局部点（相对主屏左上角）
    static func at(_ x: CGFloat, _ y: CGFloat) -> E2EPoint {
        E2EPoint { context in context.global(CGPoint(x: x, y: y)) }
    }

    /// 当前选区某个手柄的中心，再偏移 (dx, dy)
    static func handle(_ handle: SelectionHandle, dx: CGFloat = 0, dy: CGFloat = 0) -> E2EPoint {
        E2EPoint { context in
            let center = handle.center(in: try context.requireSelection())
            return CGPoint(x: center.x + dx, y: center.y + dy)
        }
    }

    /// 主屏局部点，y 从屏幕底边往上量（合成桌面的色板与文字贴着底部绘制）
    static func fromBottom(_ x: CGFloat, _ distance: CGFloat) -> E2EPoint {
        E2EPoint { context in context.global(CGPoint(x: x, y: context.world.screen.frame.height - distance)) }
    }

    /// 全局点由闭包计算（例如贴图窗口的中心）
    static func computed(_ body: @escaping @MainActor (E2EContext) throws -> CGPoint) -> E2EPoint {
        E2EPoint(resolve: body)
    }

}

enum E2EScriptError: Error, CustomStringConvertible {
    case missing(String)
    case noSession
    case noSelection
    case timedOut(String)
    case unavailable(String)

    var description: String {
        switch self {
        case .missing(let key): "nothing remembered for \(key)"
        case .noSession: "no screenshot session"
        case .noSelection: "the session has no selection"
        case .timedOut(let what): "timed out waiting for \(what)"
        case .unavailable(let what): "\(what) is unavailable"
        }
    }
}

/// 脚本运行时的上下文：环境、驱动器、跨步骤的记录与检查结果
@MainActor
final class E2EContext {
    let world: E2EWorld
    let driver: E2EEventDriver
    /// 跨步骤记录的点、矩形、数值与标识
    var rects: [String: CGRect] = [:]
    var numbers: [String: Int] = [:]
    var strings: [String: String] = [:]
    /// 标记时可见的 HUD 内容视图。强引用：旧视图释放后新视图可能复用同一地址，按标识比较会误判为「旧提示」
    var markedHUD: NSView?
    var annotations: [String: Annotation] = [:]
    /// 抢走焦点的窗口（模拟系统弹窗）；脚本结束时关闭
    var focusThief: NSWindow?
    private(set) var passed = 0
    private(set) var failures: [String] = []

    init(world: E2EWorld, driver: E2EEventDriver) {
        self.world = world
        self.driver = driver
    }

    /// 当前（或最近一次）覆盖层的会话
    var session: ScreenshotSession? {
        world.overlay?.session
    }

    var scale: CGFloat {
        world.screen.scale
    }

    func global(_ local: CGPoint) -> CGPoint {
        CGPoint(x: world.screen.frame.minX + local.x, y: world.screen.frame.minY + local.y)
    }

    func requireSession() throws -> ScreenshotSession {
        guard let session else { throw E2EScriptError.noSession }
        return session
    }

    func requireSelection() throws -> CGRect {
        guard let selection = try requireSession().selection else { throw E2EScriptError.noSelection }
        return selection
    }

    // MARK: - 结果

    func record(_ title: String, _ ok: Bool, detail: @autoclosure () -> String = "") {
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

    /// 轮询直到条件成立或超时；返回最终是否成立
    func poll(timeout: Duration, _ condition: @MainActor () throws -> Bool) async rethrows -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if try condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return try condition()
    }
}

/// 标准输出（立即刷新：进程以 exit 结束，缓冲区里的内容不能丢）
enum E2EReport {
    static func line(_ text: String) {
        print(text)
        fflush(stdout)
    }
}
#endif
