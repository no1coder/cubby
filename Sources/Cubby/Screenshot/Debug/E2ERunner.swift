#if DEBUG
import AppKit
import CubbyCore

/// 截图端到端测试入口：`Cubby --e2e <名称|all>`（仅调试构建）
///
/// 每条脚本在独立的 E2EWorld 中运行（fixture 采集、命名剪贴板、/tmp/cubby-e2e-<pid> 下的历史与保存目录），
/// 逐步打印结果，最后输出汇总行 `E2E: N passed, M failed` 并以退出码 0（全部通过）或 1 结束。
@MainActor
enum ScreenshotE2E {
    private static let argument = "--e2e"
    /// 整个运行的上限：任何卡死都以失败退出，不会留下全屏覆盖层
    private static let watchdog: TimeInterval = 600
    /// 两条脚本之间的间隔：让上一条的 HUD 与窗口动画结束
    private static let pause: Duration = .milliseconds(300)

    /// CUBBY_E2E_VERBOSE=1：逐个打印动作步骤与当时的 key 窗口
    private static let verbose = ProcessInfo.processInfo.environment["CUBBY_E2E_VERBOSE"] == "1"

    /// 命令行请求的脚本名（`all` 或具体名称）；没有 --e2e 时为 nil
    static var requested: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "all"
    }

    /// 开始运行（异步）；结束时退出进程
    static func launch(_ selection: String) {
        startWatchdog()
        // 脚本中途应用被退出（例如 ⌘Q 漏到了菜单上）：以失败结束，不能让 AppKit 以退出码 0 收场
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            print("E2E: the app was asked to quit in the middle of the run (a leaked cmd-Q?)")
            print("E2E: 0 passed, 1 failed")
            fflush(stdout)
            exit(1)
        }
        Task { @MainActor in
            let code = await run(selection)
            exit(code)
        }
    }

    private static func run(_ selection: String) async -> Int32 {
        let all = E2EScenarios.all
        let names = selection.split(separator: ",").map(String.init)
        // 走查脚本（停在各个界面状态供截图）不在 all 里，只能点名运行
        let scenarios = selection == "all" ? all : (all + E2EScenarios.walkthroughs).filter { names.contains($0.name) }
        guard !scenarios.isEmpty else {
            E2EReport.line("E2E: unknown scenario \(selection). Available: \(all.map(\.name).joined(separator: ", "))")
            E2EReport.line("E2E: 0 passed, 1 failed")
            return 1
        }
        let root = URL(
            fileURLWithPath: "/tmp/cubby-e2e-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        // 与真实使用一致：Cubby 不是前台应用（覆盖层是不激活应用的面板）。
        // 从终端启动时进程可能被激活；若不先让出，覆盖层关闭后系统切换前台应用会抢走下一个覆盖层的 key
        NSApp.deactivate()
        _ = await pollMain(timeout: .seconds(2)) { !NSApp.isActive }
        // 关闭鼠标事件合并：每个合成的 mouseMoved / dragged 都单独派发，脚本里的每一步都有对应的会话变化
        NSEvent.isMouseCoalescingEnabled = false
        let driver = E2EEventDriver()
        driver.install()

        var failed: [String] = []
        for scenario in scenarios {
            if await !run(scenario, root: root, driver: driver) {
                failed.append(scenario.name)
            }
            try? await Task.sleep(for: pause)
        }
        driver.remove()
        let passed = scenarios.count - failed.count
        if driver.blockedRealEvents > 0 {
            E2EReport.line("note: ignored \(driver.blockedRealEvents) real input event(s) during the run")
        }
        if driver.refocusCount > 0 {
            E2EReport.line(
                "note: another app took the key focus; re-focused the overlay \(driver.refocusCount) time(s)")
        }
        if failed.isEmpty {
            try? FileManager.default.removeItem(at: root)
        } else {
            E2EReport.line("failed: \(failed.joined(separator: ", ")); data kept in \(root.path)")
        }
        E2EReport.line("E2E: \(passed) passed, \(failed.count) failed")
        return failed.isEmpty ? 0 : 1
    }

    /// 运行一条脚本：动作出错即中止；结束后总是清理（取消残留会话、关闭贴图）
    private static func run(_ scenario: E2EScenario, root: URL, driver: E2EEventDriver) async -> Bool {
        E2EReport.line("[\(scenario.name)] \(scenario.summary)")
        let world: E2EWorld
        do {
            world = try E2EWorld(name: scenario.name, root: root, options: scenario.options)
        } catch {
            E2EReport.line("    FAIL  environment: \(error)")
            return false
        }
        // 每条脚本从「没有按住任何键」开始
        try? await driver.setModifiers([])
        let context = E2EContext(world: world, driver: driver)
        var aborted: String?
        for step in scenario.steps {
            if verbose && step.kind == .action {
                let key = NSApp.keyWindow.map { String(describing: Swift.type(of: $0)) } ?? "none"
                E2EReport.line("      . \(step.title) [key window: \(key)]")
            }
            do {
                try await step.body(context)
            } catch {
                aborted = "\(step.title): \(error)"
                break
            }
        }
        if let aborted {
            context.record("step failed", false, detail: aborted)
        }
        try? await driver.setModifiers([])
        context.focusThief?.close()
        world.tearDown()
        _ = await context.poll(timeout: .seconds(3)) { !world.isActive }
        let ok = context.failures.isEmpty
        E2EReport.line(
            "    => \(ok ? "passed" : "FAILED") (\(context.passed) checks passed, \(context.failures.count) failed)")
        return ok
    }

    private static func pollMain(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private static func startWatchdog() {
        let limit = watchdog
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit) {
            print("E2E: watchdog fired after \(Int(limit)) s")
            print("E2E: 0 passed, 1 failed")
            fflush(stdout)
            exit(1)
        }
    }
}
#endif
