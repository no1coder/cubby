#if DEBUG
import AppKit
import CubbyCore

/// 与翻译服务的约定：拒绝发送（计划过期、疑似密钥未确认）、部分完成即失败、缓存重放（分段变了的文本、图片）
extension PanelE2EScenarios {
    static var refusals: PanelE2EScenario {
        PanelE2EScenario(
            name: "refusals",
            summary: "a stale plan is re-planned transparently; an unconfirmed secret shows the gate; nothing is sent"
        ) { context in
            try await context.open(selecting: "mail")
            context.stub?.refuseNext = .planOutdated
            try await context.command("t")
            try await context.waitForCard(.done)
            context.check("a stale plan is retried with the new engine", context.card?.plan?.sendsTextOffDevice == true)
            context.checkEqual("… after one refusal", [.planOutdated], context.stub?.refusals)
            try await context.press(.escape)
            context.stub?.refuseNext = .secretNotConfirmed
            try context.select("notes")
            try await context.command("t")
            try await context.waitForCard(.needsSecretConfirmation)
            context.check("an unconfirmed secret shows the gate", true)
            context.checkEqual("… and nothing was sent for it", 1, context.stub?.sentCalls.count)
            try await context.press(.escape)
            context.stub?.refuseNext = .planOutdated
            try await context.press(.returnKey, .option)
            await context.eventually("⌥↩ re-plans and pastes") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("notes", "en")
            }
            try await context.open(selecting: "article")
            context.stub?.refuseNext = .secretNotConfirmed
            try await context.press(.returnKey, .option)
            await context.eventually("⌥↩ shows the secret gate inline") {
                if case .failed(.needsSecretConfirmation) = context.translation?.inline.job?.phase { return true }
                return false
            }
        }
    }

    static var swapRefused: PanelE2EScenario {
        PanelE2EScenario(
            name: "swap-refused",
            summary: "when the service refuses ⇄ for a secret, the card says so and stays on the translation"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.waitForCard(.done)
            context.stub?.refusesReverse = true
            try await context.click("card.swap")
            try await context.waitForCard(.done)
            context.check("the card stays forward", context.card?.isReversed == false)
            context.checkEqual(
                "… with an explanation", TranslationCopy.swapRefusedForSecret,
                context.translation?.card.flash?.message)
            context.check("nothing was sent", context.stub?.reverseCalls.isEmpty == true)
        }
    }

    static var partialFailure: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.streamFailure = .invalidResponse
        return PanelE2EScenario(
            name: "partial-failure",
            summary: "a stream that stops half way fails: nothing is pasteable, nothing is pasted",
            options: options
        ) { context in
            try await context.open(selecting: "article")
            try await context.command("t")
            try await context.waitForCard(.failed(.invalidResponse))
            context.check("the partial translation is not pasteable", context.card?.result == nil)
            try await context.press(.returnKey)
            try await context.command("c")
            context.check("↩ / ⌘C write nothing", context.world.pasteboardText == nil)
            try await context.press(.escape)
            try await context.press(.returnKey, .option)
            await context.eventually("⌥↩ shows the failure inline") {
                context.translation?.inline.job?.phase == .failed(.failure(.invalidResponse))
            }
            try await Task.sleep(for: .milliseconds(500))
            context.check("… and pastes nothing", context.world.pasteboardText == nil)
        }
    }

    static var cacheWholeSegment: PanelE2EScenario {
        PanelE2EScenario(
            name: "cache-whole-segment",
            summary: "a cache from an older segmentation replays as one segment; Compare shows one pair"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.waitForCard(.done)
            try await context.press(.escape)
            context.stub?.replaysCacheAsOneSegment = true
            try await context.command("t")
            try await context.waitForCard(.done)
            context.checkEqual("the replay has one segment", 1, context.card?.content.segments.count)
            try await context.press(.rightArrow)
            try await context.settle()
            context.check(
                "Compare shows one pair", context.hasAnchor("card.pair.0") && !context.hasAnchor("card.pair.1"))
            try await context.press(.returnKey)
            await context.eventually("↩ pastes the whole translation") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("mail", "zh-Hans")
            }
        }
    }

    static var imageCached: PanelE2EScenario {
        PanelE2EScenario(
            name: "image-cached",
            summary: "a cached image replays without blocks and shows the translated PNG at once"
        ) { context in
            try await context.open(selecting: "image")
            try await context.command("t")
            try await context.waitForCard(.done, timeout: .seconds(8))
            try await context.press(.escape)
            try await context.command("t")
            try await context.waitForCard(.done, timeout: .seconds(2))
            context.check("… without block layouts", context.card?.content.imageBlocks.isEmpty == true)
            context.check("… from the cached PNG", context.card?.content.result?.imageURL != nil)
            context.check("… marked cached", context.card?.content.result?.fromCache == true)
        }
    }

    static var cardRoutesTranslateAndPaste: PanelE2EScenario {
        PanelE2EScenario(
            name: "card-routes-alt-return",
            summary: "“Translate and Paste” on another item while the card is open sends exactly one request"
        ) { context in
            try await context.open(selecting: "mail")
            try await context.command("t")
            try await context.waitForCard(.done)
            context.stub?.engine = .cloud
            let sent = context.stub?.sentCalls.count ?? 0
            context.viewModel.translateAndPaste(try context.item("notes"))
            // 同步检查：完成后面板会收起、卡片随之关闭
            context.checkEqual("the card follows the item", PanelE2EFixtures.id("notes"), context.card?.itemID)
            context.check("no inline job is started", context.translation?.inline.job == nil)
            await context.eventually("the translation is pasted") {
                context.world.pasteboardText == PanelE2EFixtures.plainTranslation("notes", "en")
            }
            try await Task.sleep(for: .milliseconds(800))
            context.checkEqual("the service got exactly one request", sent + 1, context.stub?.sentCalls.count)
        }
    }

    static var copyCachedAfterEngineChange: PanelE2EScenario {
        PanelE2EScenario(
            name: "copy-cached-other-engine",
            summary: "right-click “Copy Translation” copies the cache even after switching engines, sending nothing"
        ) { context in
            try await context.open(selecting: "line")
            context.stub?.engine = .cloud
            context.viewModel.copyCachedTranslation(try context.item("line"))
            context.checkEqual(
                "the cached translation is copied", PanelE2EFixtures.plainTranslation("line", "zh-Hans"),
                context.world.pasteboardText)
            context.check("nothing was sent", context.stub?.translateCalls.isEmpty == true)
            context.check("the panel stays open", context.world.panel.debugIsShown)
        }
    }

    static var holdOptionNoteAfterRelease: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.startDelay = .milliseconds(700)
        options.streamFailure = .network
        return PanelE2EScenario(
            name: "hold-option-note",
            summary: "a preview that fails after ⌥ is released becomes a footer toast; the next ⌥ works",
            options: options
        ) { context in
            try await context.open(selecting: "article")
            try await context.holdOption(true)
            await context.eventually("the preview starts") { context.translation?.peek.peek?.isStreaming == true }
            try await context.press(.returnKey)
            try await context.holdOption(false)
            await context.eventually("the failure restores the card") { context.translation?.peek.peek == nil }
            context.check("… and shows a footer toast", context.viewModel.toast != nil)
            context.check("nothing was pasted", context.world.pasteboardText == nil)
            context.stub?.streamFailure = nil
            try await context.holdOption(true)
            await context.eventually("the next ⌥ previews again") { context.translation?.peek.peek != nil }
            try await context.holdOption(false)
        }
    }
}
#endif
