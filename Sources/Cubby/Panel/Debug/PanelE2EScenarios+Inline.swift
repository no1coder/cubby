#if DEBUG
import AppKit
import CubbyCore

/// ⌥↩ 翻译后粘贴：行内进度、esc 取消、失败与超时绝不退回原文、疑似密钥（§4）
extension PanelE2EScenarios {
    static var altReturn: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.segmentDelay = .milliseconds(300)
        return PanelE2EScenario(
            name: "alt-return",
            summary: "⌥↩ shows inline progress on the card, then pastes the translation and names the engine",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.press(.returnKey, .option)
            let job = context.translation?.inline.job
            context.check("⌥↩ starts an inline job", job?.isRunning == true)
            context.check("the panel stays open while translating", context.world.panel.debugIsShown)
            try await context.settle()
            context.check(
                "the card shows the inline progress row",
                context.hasAnchor("list.inline.\(PanelE2EFixtures.id("mail"))"))
            await context.eventually("the translation is pasted") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("mail", "zh-Hans")
            }
            context.check("the panel hides", !context.world.panel.debugIsShown)
            context.check("the job is done", context.translation?.inline.job == nil)
            await context.expectHUD(containing: PanelE2EStubTranslator.systemEngineName)
        }
    }

    static var altReturnCancel: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.segmentDelay = .milliseconds(800)
        return PanelE2EScenario(
            name: "alt-return-cancel",
            summary: "esc during ⌥↩ cancels it with a footer toast and pastes nothing",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.press(.returnKey, .option)
            try await context.settle(.milliseconds(300))
            try await context.press(.escape)
            context.check("esc cancels the job", context.translation?.inline.job == nil)
            context.checkEqual(
                "the footer says so", TranslationCopy.cancelledTitle, context.viewModel.toast?.message)
            context.check("the panel stays open", context.world.panel.debugIsShown)
            await context.eventually("the stream was cancelled") { (context.stub?.terminatedEarly ?? 0) >= 1 }
            try await Task.sleep(for: .seconds(1.5))
            context.check("nothing was pasted", context.world.pasteboardText == nil)
        }
    }

    static var altReturnFailure: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.streamFailure = .network
        options.engine = .cloud
        options.inlineCap = .seconds(1)
        return PanelE2EScenario(
            name: "alt-return-failure",
            summary: "a failed or timed-out ⌥↩ shows the reason inline, never pastes the original, Retry works",
            options: options
        ) { context in
            try await context.open(selecting: "notes")
            try await context.press(.returnKey, .option)
            await context.eventually("the failure shows inline") {
                context.translation?.inline.job?.phase == .failed(.failure(.network))
            }
            context.check("nothing was pasted (no fallback to the original)", context.world.pasteboardText == nil)
            context.check("the panel stays open", context.world.panel.debugIsShown)
            context.stub?.streamFailure = nil
            context.stub?.startDelay = .seconds(3)
            try await context.click("list.inlineAction")
            context.check("Retry restarts the job", context.translation?.inline.job?.isRunning == true)
            await context.eventually("the 1 s cap times it out", timeout: .seconds(3)) {
                context.translation?.inline.job?.phase == .failed(.timedOut)
            }
            context.check("a timeout pastes nothing", context.world.pasteboardText == nil)
            context.stub?.startDelay = .milliseconds(50)
            try await context.click("list.inlineAction")
            await context.eventually("the retry pastes the translation") {
                context.world.pasteboardText?.hasPrefix("Before Thursday") == true
            }
            await context.expectHUD(containing: "DeepSeek")
            context.check(
                "the HUD names the provider, not the model",
                E2EInspect.visibleHUD()?.text.contains("deepseek-chat") == false)
        }
    }

    static var secretGate: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.engine = .cloud
        return PanelE2EScenario(
            name: "secret-gate",
            summary: "a suspected secret is never sent to the cloud until “Translate Anyway”",
            options: options
        ) { context in
            try await context.open(selecting: "terminal")
            try await context.command("t")
            context.checkEqual(
                "the card asks first", TranslationCardPhase.needsSecretConfirmation, context.card?.phase)
            context.check("nothing was sent", context.stub?.sentCalls.isEmpty == true)
            context.check(
                "the privacy line says not sent",
                context.card.map { TranslationCopy.privacy(for: $0).text.contains("secret") } == true)
            try await context.settle()
            try await context.click("card.action.0")
            context.check(
                "“Translate Anyway” sends with confirmation", context.stub?.sentCalls.last?.confirmedSecret == true)
            try await context.waitForCard(.done)
            try await confirmationIsPerSend(context)
            try await context.press(.escape)
            context.stub?.clearCache()
            try await context.press(.returnKey, .option)
            context.checkEqual(
                "⌥↩ asks inline as well", InlineTranslation.Phase.failed(.needsSecretConfirmation("DeepSeek")),
                context.translation?.inline.job?.phase)
            context.check("… and pastes nothing", context.world.pasteboardText == nil)
            try await context.settle()
            try await context.click("list.inlineAction")
            await context.eventually("confirming inline pastes the translation") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("terminal", "zh-Hans")
            }
        }
    }

    /// 「仍然翻译」只对同一次发送有效：换目标语言后要重新确认，确认前什么都不发
    private static func confirmationIsPerSend(_ context: PanelE2EContext) async throws {
        guard let card = context.card, let controller = context.translation?.card else { return }
        let sent = context.stub?.sentCalls.count ?? 0
        let menu = TranslationMenus.languageMenu(for: card, controller: controller)
        let traditional = TranslationCopy.nativeLanguageName("zh-Hant")
        menu.performActionForItem(at: menu.items.firstIndex { $0.title == traditional } ?? 0)
        context.checkEqual(
            "another target language asks again", TranslationCardPhase.needsSecretConfirmation, context.card?.phase)
        context.checkEqual("… and sends nothing", sent, context.stub?.sentCalls.count)
        // 回到自动目标语言，后面的 ⌥↩ 仍译成简体中文
        context.stub?.setTarget(nil, rememberFor: nil)
    }

    static var notConfigured: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.planFailure = .notConfigured
        return PanelE2EScenario(
            name: "not-configured",
            summary: "no service: the card offers “Go to Settings”, which hides the panel and asks the service",
            options: options
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            context.checkEqual(
                "the card explains", TranslationCardPhase.failed(.notConfigured), context.card?.phase)
            try await context.settle()
            try await context.click("card.action.0")
            await context.eventually("the service is asked to resolve it") {
                context.stub?.resolved == [.notConfigured]
            }
            context.check("the panel hides first", !context.world.panel.debugIsShown)
            try await context.open(selecting: "mail")
            try await context.press(.returnKey, .option)
            context.checkEqual(
                "⌥↩ shows the same reason inline", InlineTranslation.Phase.failed(.failure(.notConfigured)),
                context.translation?.inline.job?.phase)
            context.check("… and pastes nothing", context.world.pasteboardText == nil)
        }
    }
}
#endif
