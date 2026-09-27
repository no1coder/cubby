#if DEBUG
import AppKit
import CubbyCore

/// 走查截图：`Cubby --panel-e2e shots`（CUBBY_SHOTS_DIR 指定输出目录）。
/// 逐个摆出翻译相关的界面状态，用 `screencapture -l <窗口号>` 只截本进程自己的窗口（主面板、详情区、HUD），不截整屏
@MainActor
enum PanelE2EShots {
    static var all: [PanelE2EScenario] {
        [shots]
    }

    private static var shots: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.startDelay = .milliseconds(200)
        options.segmentDelay = .milliseconds(500)
        return PanelE2EScenario(
            name: "shots", summary: "walkthrough screenshots of every translation state", options: options
        ) { context in
            if ProcessInfo.processInfo.environment["CUBBY_SHOTS_APPEARANCE"] == "light" {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            context.stub?.engine = .localizedSystem
            try await listStates(context)
            try await cardStates(context)
            try await imageStates(context)
            try await issueStates(context)
        }
    }

    private static func listStates(_ context: PanelE2EContext) async throws {
        try await context.open(selecting: "mail")
        try await context.settle(.milliseconds(400))
        try await shot(context, "list")
        context.viewModel.showsTranslationOnCards = true
        try context.select("line")
        try await context.settle(.milliseconds(400))
        try await shot(context, "list-translation-line")
        context.viewModel.showsTranslationOnCards = false
        try context.select("mail")
        try await context.holdOption(true)
        try await context.settle(.milliseconds(900))
        try await shot(context, "list-hold-option-streaming")
        try await context.settle(.milliseconds(900))
        try await shot(context, "list-hold-option-done")
        try await context.holdOption(false)
        context.viewModel.toggleHelp()
        try await context.settle(.milliseconds(300))
        try await shot(context, "help")
        context.viewModel.toggleHelp()
        context.stub?.segmentDelay = .seconds(2)
        try context.select("article")
        try await context.press(.returnKey, .option)
        try await context.settle(.milliseconds(700))
        try await shot(context, "list-alt-return-progress")
        try await context.press(.escape)
        try await context.settle(.milliseconds(300))
        try await shot(context, "list-alt-return-cancelled")
        context.stub?.segmentDelay = .milliseconds(500)
    }

    private static func cardStates(_ context: PanelE2EContext) async throws {
        context.stub?.clearCache()
        try context.select("mail")
        try await context.command("t")
        try await context.settle(.milliseconds(120))
        try await shot(context, "card-waiting")
        try await context.wait("streaming") { context.card?.phase == .streaming }
        try await context.settle(.milliseconds(250))
        try await shot(context, "card-streaming")
        try await context.waitForCard(.done)
        try await context.settle(.milliseconds(400))
        try await shot(context, "card-done")
        try await context.press(.rightArrow)
        try await context.settle(.milliseconds(300))
        context.hover(at: try? context.point(of: "card.pair.1"))
        try await context.settle(.milliseconds(300))
        try await shot(context, "card-side-by-side")
        try await context.press(.rightArrow)
        try await context.settle(.milliseconds(300))
        try await shot(context, "card-original")
        try await context.press(.leftArrow)
        try await context.press(.leftArrow)
        try await context.holdOption(true)
        try await context.settle(.milliseconds(300))
        try await shot(context, "card-hold-option")
        try await context.holdOption(false)
        try await context.command("c")
        try await context.settle(.milliseconds(200))
        try await shot(context, "card-copied")
        try await follow(context, "article")
        try await context.waitForCard(.done, timeout: .seconds(8))
        try await context.settle(.milliseconds(500))
        try await shot(context, "card-rich")
        try await follow(context, "line")
        try await context.settle(.milliseconds(400))
        try await shot(context, "card-cached")
        try await context.click("card.swap")
        try await context.waitForCard(.done)
        try await context.settle(.milliseconds(400))
        try await shot(context, "card-swapped")
        try await follow(context, "code")
        try await context.settle(.milliseconds(400))
        try await shot(context, "card-unsupported")
    }

    private static func imageStates(_ context: PanelE2EContext) async throws {
        context.stub?.segmentDelay = .milliseconds(400)
        try await follow(context, "image")
        try await context.settle(.milliseconds(900))
        try await shot(context, "image-streaming")
        try await context.waitForCard(.done, timeout: .seconds(8))
        try await context.settle(.milliseconds(400))
        try await shot(context, "image-done")
        try await context.press(.rightArrow)
        try await context.settle(.milliseconds(400))
        try await shot(context, "image-wipe")
        let stage = try context.frame(of: "card.stage", in: context.detailWindow)
        let point = PanelE2EFixtures.stagePoint(of: 1, in: stage)
        context.hover(at: point)
        try await context.settle(.milliseconds(700))
        try await shot(context, "image-hover-bubble")
        context.hover(at: nil)
        try await context.holdOption(true)
        try await context.settle(.milliseconds(300))
        try await shot(context, "image-hold-option")
        try await context.holdOption(false)
        try await context.press(.escape)
        try await context.settle(.milliseconds(300))
    }

    private static func issueStates(_ context: PanelE2EContext) async throws {
        context.stub?.engine = .cloud
        try context.select("terminal")
        try await context.command("t")
        try await context.settle(.milliseconds(400))
        try await shot(context, "card-secret")
        try await context.press(.escape)
        try await context.press(.returnKey, .option)
        try await context.settle(.milliseconds(400))
        try await shot(context, "list-inline-secret")
        try await context.press(.escape)
        try context.select("mail")
        try await context.command("t")
        try await context.press(.downArrow)
        try await context.settle(.milliseconds(200))
        try await shot(context, "card-cloud-holding")
        try await context.settle(.milliseconds(1500))
        try await shot(context, "card-cloud-streaming")
        context.stub?.planFailure = .notConfigured
        try await context.press(.downArrow)
        try await context.settle(.milliseconds(400))
        try await shot(context, "card-not-configured")
        context.stub?.planFailure = nil
        context.stub?.streamFailure = .network
        try await context.press(.escape)
        try context.select("mail")
        context.stub?.clearCache()
        try await context.command("t")
        try await context.settle(.milliseconds(1500))
        try await shot(context, "card-network-error")
        context.stub?.streamFailure = nil
    }

    /// 选中另一条并等翻译卡跟过去
    private static func follow(_ context: PanelE2EContext, _ key: String) async throws {
        try context.select(key)
        try await context.wait("the card follows \(key)") { context.card?.itemID == PanelE2EFixtures.id(key) }
    }

    // MARK: - 截图

    /// 截下本进程所有可见窗口（主面板、详情区、HUD）
    private static func shot(_ context: PanelE2EContext, _ name: String) async throws {
        try await context.settle()
        guard let directory = ProcessInfo.processInfo.environment["CUBBY_SHOTS_DIR"] else { return }
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let windows = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 }
            .sorted { $0.windowNumber < $1.windowNumber }
        for (index, window) in windows.enumerated() {
            let path = "\(directory)/tr-\(language)-\(appearance)-\(name)-\(index).png"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
            try process.run()
            process.waitUntilExit()
        }
        E2EReport.line("    SHOT  \(name) (\(windows.count) window(s))")
    }
}
#endif
