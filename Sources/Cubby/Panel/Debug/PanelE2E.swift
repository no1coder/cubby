#if DEBUG
import AppKit
import CubbyCore

/// 面板端到端测试入口：`Cubby --panel-e2e <名称|all>`（仅调试构建，make e2e-panel）。
///
/// 每条脚本在独立的 PanelE2EWorld 中运行（演示条目、命名剪贴板、/tmp/cubby-panel-e2e-<pid> 下的数据），
/// 用合成的键盘 / 鼠标事件驱动真实的面板与详情区窗口，逐步打印结果，最后输出 `E2E: N passed, M failed`
/// 并以退出码 0（全部通过）或 1 结束
@MainActor
enum PanelE2E {
    private static let argument = "--panel-e2e"
    /// 整个运行的上限：任何卡死都以失败退出
    private static let watchdog: TimeInterval = 600
    /// 两条脚本之间的间隔：让上一条的 HUD 与窗口动画结束
    private static let pause: Duration = .milliseconds(300)

    /// 命令行请求的脚本名（`all`、具体名称或逗号分隔的列表）；没有 --panel-e2e 时为 nil
    static var requested: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "all"
    }

    /// 开始运行（异步）；结束时退出进程
    static func launch(_ selection: String) {
        startWatchdog()
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
        let all = PanelE2EScenarios.all
        let names = selection.split(separator: ",").map(String.init)
        // 走查截图（shots）不在 all 里，只在点名时运行
        let scenarios =
            selection == "all" ? all : (all + PanelE2EShots.all).filter { names.contains($0.name) }
        guard !scenarios.isEmpty else {
            E2EReport.line("E2E: unknown scenario \(selection). Available: \(all.map(\.name).joined(separator: ", "))")
            E2EReport.line("E2E: 0 passed, 1 failed")
            return 1
        }
        let root = URL(
            fileURLWithPath: "/tmp/cubby-panel-e2e-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        // 与真实使用一致：Cubby 不是前台应用（面板不激活应用）
        NSApp.deactivate()
        PanelE2EAnchors.isEnabled = true
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
        if failed.isEmpty {
            try? FileManager.default.removeItem(at: root)
        } else {
            E2EReport.line("failed: \(failed.joined(separator: ", ")); data kept in \(root.path)")
        }
        E2EReport.line("E2E: \(passed) passed, \(failed.count) failed")
        return failed.isEmpty ? 0 : 1
    }

    /// 运行一条脚本：动作出错即中止；结束后总是清理
    private static func run(_ scenario: PanelE2EScenario, root: URL, driver: E2EEventDriver) async -> Bool {
        E2EReport.line("[\(scenario.name)] \(scenario.summary)")
        let world: PanelE2EWorld
        do {
            world = try PanelE2EWorld(name: scenario.name, root: root, options: scenario.options)
        } catch {
            E2EReport.line("    FAIL  environment: \(error)")
            return false
        }
        try? await driver.setModifiers([])
        let context = PanelE2EContext(world: world, driver: driver)
        do {
            try await scenario.run(context)
        } catch {
            context.check("script aborted", false, detail: "\(error)")
        }
        try? await driver.setModifiers([])
        world.tearDown()
        let ok = context.failures.isEmpty
        E2EReport.line(
            "    => \(ok ? "passed" : "FAILED") (\(context.passed) checks passed, \(context.failures.count) failed)")
        return ok
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
