#if DEBUG
import AppKit
import CubbyCore

/// 检查类步骤：失败时记录并继续（后续检查仍有诊断价值）；取值出错（例如没有会话）同样记为失败
extension E2EStep {
    /// 条件检查
    static func expect(_ title: String, _ predicate: @escaping @MainActor (E2EContext) throws -> Bool) -> E2EStep {
        E2EStep(title: title, kind: .check) { context in
            do {
                context.record(title, try predicate(context))
            } catch {
                context.record(title, false, detail: "\(error)")
            }
        }
    }

    /// 相等检查：失败时打印期望值与实际值
    static func expectEqual<Value: Equatable & Sendable>(
        _ title: String, _ expected: @escaping @MainActor (E2EContext) throws -> Value?,
        _ actual: @escaping @MainActor (E2EContext) throws -> Value?
    ) -> E2EStep {
        E2EStep(title: title, kind: .check) { context in
            do {
                let wanted = try expected(context)
                let got = try actual(context)
                context.record(
                    title, wanted != nil && wanted == got, detail: "expected \(show(wanted)), got \(show(got))")
            } catch {
                context.record(title, false, detail: "\(error)")
            }
        }
    }

    static func expectEqual<Value: Equatable & Sendable>(
        _ title: String, _ expected: Value, _ actual: @escaping @MainActor (E2EContext) throws -> Value?
    ) -> E2EStep {
        expectEqual(title, { _ in expected }, actual)
    }

    /// 最终一致的检查：在超时内轮询，适合异步出口（剪贴板、历史、文件、HUD）
    static func eventually(
        _ title: String, timeout: Duration = .seconds(5),
        _ predicate: @escaping @MainActor (E2EContext) -> Bool, detail: (@MainActor (E2EContext) -> String)? = nil
    ) -> E2EStep {
        E2EStep(title: title, kind: .check) { context in
            let ok = await context.poll(timeout: timeout) { predicate(context) }
            context.record(title, ok, detail: detail?(context) ?? "not satisfied within \(timeout)")
        }
    }

    // MARK: - 常用检查

    static func expectPhase(_ phase: ScreenshotPhase) -> E2EStep {
        expectEqual("phase is \(phase)", phase) { try $0.requireSession().phase }
    }

    /// 协调器回到空闲（覆盖层已结束，输出已交付或放弃）
    static var expectIdle: E2EStep {
        eventually("session ended (coordinator idle)") { !$0.world.isActive }
    }

    /// 覆盖层仍在屏幕上接收输入
    static var expectPresented: E2EStep {
        expect("overlay still presented") { $0.world.isOverlayPresented }
    }

    /// 出现一个新的 HUD（不是之前已记录的那个），且文本包含 text
    static func expectHUD(containing text: String, timeout: Duration = .seconds(5)) -> E2EStep {
        let title = "HUD shows \"\(text)\""
        return E2EStep(title: title, kind: .check) { context in
            // 记下轮询期间出现过的新提示，失败时一并打印
            var seen: [String] = []
            let ok = await context.poll(timeout: timeout) {
                guard let hud = E2EInspect.visibleHUD(), hud.view !== context.markedHUD else { return false }
                if seen.last != hud.text {
                    seen.append(hud.text)
                }
                return hud.text.contains(text)
            }
            context.record(title, ok, detail: "new HUDs seen: \(seen.isEmpty ? "none" : seen.joined(separator: " | "))")
        }
    }

    /// 记录当前 HUD，之后的 expectHUD 只接受新出现的提示
    static var markHUD: E2EStep {
        remember("current HUD") { context in
            context.markedHUD = E2EInspect.visibleHUD()?.view
        }
    }

    /// 记录剪贴板、历史与保存目录的当前状态（之后比较增量）
    static var markOutputs: E2EStep {
        remember("outputs") { context in
            context.numbers["changeCount"] = context.world.pasteboard.changeCount
            context.numbers["history"] = context.world.history.count
            context.numbers["files"] = context.world.savedFiles.count
            context.markedHUD = E2EInspect.visibleHUD()?.view
        }
    }

    /// 剪贴板没有被写入
    static var expectPasteboardUnchanged: E2EStep {
        expectEqual("pasteboard untouched", { $0.numbers["changeCount"] }) { $0.world.pasteboard.changeCount }
    }

    /// 历史条数相对 markOutputs 的增量
    static func expectHistoryDelta(_ delta: Int, settle: Duration = .milliseconds(600)) -> E2EStep {
        E2EStep(title: "history grew by \(delta)", kind: .check) { context in
            let base = context.numbers["history"] ?? 0
            let ok = await context.poll(timeout: .seconds(5)) { context.world.history.count == base + delta }
            // 等后台记录全部落定，确认不会再多出来
            try? await Task.sleep(for: settle)
            let final = context.world.history.count - base
            context.record("history grew by \(delta)", ok && final == delta, detail: "grew by \(final)")
        }
    }

    private static func show<Value>(_ value: Value?) -> String {
        value.map { "\($0)" } ?? "nil"
    }
}
#endif
