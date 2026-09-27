#if DEBUG
import AppKit
import CubbyCore

/// 走查脚本：依次停在截图翻译的各个界面状态，打印 `SHOT <名称> <窗口号>` 后停留，
/// 供外部用 `screencapture -o -l <窗口号>` 截取 Cubby 自己的覆盖层窗口（画面是合成夹具，不含用户内容）。
/// 不在 E2EScenarios.all 里，需点名运行：`Cubby --e2e walkthrough-translate`
extension E2EScenarios {
    static var walkthroughs: [E2EScenario] {
        guard #available(macOS 26, *) else { return [] }
        return [translateWalkthrough]
    }

    static var translateWalkthrough: E2EScenario {
        E2EScenario(
            name: "walkthrough-translate",
            summary: "stops at each translation UI state for screenshots",
            options: translationOptions {
                $0.script.firstDelay = .milliseconds(400)
                $0.script.blockDelay = .milliseconds(900)
            },
            steps: [
                .start(at: desktop),
                // 比测试脚本的选区高一些：卷帘的标签、拖柄与气泡都有地方放
                .drag([.fromBottom(12, 420), .fromBottom(700, 158)]),
                .translateKey,
                .expectTranslationStatus("two blocks arrived", timeout: .seconds(8)) { status in
                    if case .translating(let done, _) = status { return done >= 2 }
                    return false
                },
                .shot("translating"),
                .expectTranslationReady,
                .move(.at(1500, 700)),
                .shot("ready"),
                .move(firstBlock),
                .wait(700),
                .shot("bubble"),
                .move(.at(1500, 700)),
                .clickTranslationBar(.compare),
                .shot("wipe"),
                .clickTranslationBar(.compare),
                .spaceDown,
                .shot("peek"),
                .spaceUp,
                .letter("r"),
                .shot("style-bar"),
                .key(.escape),
                .key(.escape),
                .remember("failure") { $0.world.translationProvider?.script.setupFailure = .notConfigured },
                .start(at: desktop),
                .drag([textStart, textEnd]),
                .translateKey,
                .expectTranslationStatus("failed") { $0 == .failed(.notConfigured) },
                .shot("failure"),
                .key(.escape),
                .key(.escape),
            ]
        )
    }
}

extension E2EStep {
    /// 打印覆盖层（选区所在屏）的窗口号，停留 1.5 s 供外部截图
    static func shot(_ name: String) -> E2EStep {
        action("shot \(name)") { context in
            try? await Task.sleep(for: .milliseconds(400))
            guard let window = context.world.overlay?.debugWindows.first(where: \.isVisible) else {
                throw E2EScriptError.unavailable("overlay window")
            }
            E2EReport.line("SHOT \(name) \(window.windowNumber)")
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }
}
#endif
