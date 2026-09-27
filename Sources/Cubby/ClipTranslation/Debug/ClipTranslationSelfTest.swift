#if DEBUG
import AppKit
import CubbyCore
import Foundation

/// 剪贴板翻译服务的自检（`Cubby --clip-translation-selftest`）：用临时目录里的历史、独立的偏好域、桩引擎与
/// 真实的 Vision 识别器（本机）驱动 ClipTranslationService 与 ClipAutoTranslator，逐项打印 PASS / FAIL，
/// 全部通过时以 0 退出。不联网、不读写剪贴板与真实数据目录，也不接触钥匙串
@MainActor
final class ClipTranslationSelfTest {
    static let argument = "--clip-translation-selftest"

    static var isRequested: Bool {
        CommandLine.arguments.contains(argument)
    }

    /// 独立的偏好域无法创建时直接失败退出：绝不退回到用户的 standard 偏好域
    static func launch() {
        Task { @MainActor in
            guard let test = ClipTranslationSelfTest() else {
                print("clip-translation selftest: FAILED (couldn't create a private preferences domain)")
                exit(1)
            }
            await test.run()
            test.cleanUp()
            print("clip-translation selftest: \(test.failures == 0 ? "PASSED" : "FAILED (\(test.failures))")")
            exit(test.failures == 0 ? 0 : 1)
        }
    }

    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "cubby-clip-selftest-\(UUID().uuidString)", directoryHint: .isDirectory)
    private let suiteName = "cubby-clip-selftest-\(UUID().uuidString)"
    let settings: AppSettings
    let store: ClipStore
    var failures = 0

    private init?() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        settings = AppSettings(defaults: defaults)
        store = ClipStore(
            storage: JSONHistoryStorage(fileURL: directory.appending(path: "history.json")),
            blobs: BlobStore(directory: directory.appending(path: "Images", directoryHint: .isDirectory)), limit: 100)
    }

    private func cleanUp() {
        store.flush()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL") \(name)")
        if !condition { failures += 1 }
    }

    func service(_ provider: ClipStubProvider) -> ClipTranslationService {
        ClipTranslationService(
            store: store, settings: settings, provider: provider, recognizer: VisionTranslationRecognizer(),
            preferredLanguages: { ["zh-Hans", "en"] })
    }

    private func run() async {
        await plainText()
        await richText()
        await brokenPlaceholders()
        await cancellation()
        await secretsAndFailures()
        await partialAndMisaligned()
        await securityGates()
        targetsAndSaving()
        await swap()
        await image()
        await autoTranslate()
    }

    // MARK: - 文本

    private func plainText() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        let service = service(provider)
        guard let item = store.record(.text("Hello there.\n\nhttps://example.com\n\nSee you."), source: nil),
            case .success(let plan) = service.plan(for: item, target: nil, pasteTarget: nil)
        else { return check(false, "text: record and plan") }
        check(plan.languages == TranslationLanguages(source: "en", target: "zh-Hans") && !plan.isCached, "text: plan")
        let first = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(first.started?.map(\.isTranslatable) == [true, false, true], "text: started segments")
        check(first.segments.keys.sorted() == [0, 2], "text: segment events")
        check(
            first.result?.plainText == "[T] Hello there.\n\nhttps://example.com\n\n[T] See you."
                && first.result?.fromCache == false, "text: finished result")
        check(log.requests == [["Hello there.", "See you."]], "text: engine got translatable segments only")
        let cachedPlan = try? service.plan(for: item, target: nil, pasteTarget: nil).get()
        check(cachedPlan?.isCached == true, "text: plan is cached after translating")
        let replay = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(replay.result?.fromCache == true && replay.segments.count == 2, "text: cache replay")
        check(log.requests.count == 1, "text: replay doesn't call the engine")
        provider.engine.displayName = "Other Engine"
        let other = try? service.plan(for: item, target: nil, pasteTarget: nil).get()
        check(other?.isCached == false, "text: another engine isn't a cache hit")
    }

    private func richText() async {
        let log = ClipStubLog()
        let service = service(ClipStubProvider(log: log))
        let html = "<p>Run <code>npm install</code> to set up the <b>project</b>.</p><pre>npm test</pre>"
        guard
            let item = store.record(
                .richText("Run npm install to set up the project.", formats: ["public.html": Data(html.utf8)]),
                source: nil),
            case .success(let plan) = service.plan(for: item, target: "ja", pasteTarget: nil)
        else { return check(false, "rich: record and plan") }
        let events = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(log.requests == [["Run {1} to set up the project."]], "rich: inline code replaced by a placeholder")
        let rich = events.result?.richText
        let code = rich?.runs.filter { $0.inlinePresentationIntent == .code }.map { String(rich![$0.range].characters) }
        check(code == ["npm install"], "rich: inline code restored with code style")
        check(events.result?.plainText.contains("npm test") == true, "rich: code block kept")
        let entry = store.item(id: item.id)?.translation(for: "ja")
        check(entry?.usesInlineMarkup == true, "rich: cache stores markup")
    }

    private func brokenPlaceholders() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        provider.engine.transform = { text, attempt in
            attempt == 1 ? "[T] " + text.replacingOccurrences(of: "{1}", with: "") : "[T] " + text
        }
        let service = service(provider)
        guard let item = store.record(.text("Run `make test` before pushing."), source: nil),
            case .success(let plan) = service.plan(for: item, target: nil, pasteTarget: nil)
        else { return check(false, "retry: record and plan") }
        let events = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(
            log.requests == [["Run {1} before pushing."], ["Run `make test` before pushing."]],
            "retry: broken placeholder retried without protection")
        check(events.result?.plainText == "[T] Run `make test` before pushing.", "retry: result")
    }

    private func cancellation() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        provider.engine.delay = .milliseconds(400)
        let service = service(provider)
        guard let item = store.record(.text("One sentence here.\n\nAnother one.\n\nA third one."), source: nil),
            case .success(let plan) = service.plan(for: item, target: nil, pasteTarget: nil)
        else { return check(false, "cancel: record and plan") }
        let consumer = Task { @MainActor in
            var count = 0
            for try await event in service.translate(item, plan: plan, confirmedSecret: false) {
                if case .segment = event { count += 1 }
            }
            return count
        }
        try? await Task.sleep(for: .milliseconds(600))
        consumer.cancel()
        _ = try? await consumer.value
        try? await Task.sleep(for: .milliseconds(600))
        check(log.cancellations == 1, "cancel: cancelling the consumer cancels the engine stream")
        check(store.item(id: item.id)?.hasTranslations == false, "cancel: partial result not cached")
    }

    private func secretsAndFailures() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        provider.engine.sendsTextOffDevice = true
        provider.host = "api.example.com"
        provider.input = .markup
        let service = service(provider)
        let secret = "My token is " + ["gh", "p_", String(repeating: "aB3dE5gH7j", count: 4)].joined()
        guard let item = store.record(.text(secret), source: nil),
            case .success(let plan) = service.plan(for: item, target: nil, pasteTarget: nil)
        else { return check(false, "secret: record and plan") }
        check(plan.needsSecretConfirmation && plan.host == "api.example.com", "secret: plan needs confirmation")
        let blocked = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(
            blocked.error as? ClipTranslationRefusal == .secretNotConfirmed && log.requests.isEmpty,
            "secret: nothing sent without confirmation")
        let confirmed = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: true))
        check(confirmed.result != nil && log.requests.count == 1, "secret: sent after confirmation")

        provider.engine.sendsTextOffDevice = false
        let changed = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: true))
        check(
            changed.error as? ClipTranslationRefusal == .planOutdated && log.requests.count == 1,
            "engine changed after planning: not sent")

        provider.engine.failAfter = 1
        provider.engine.sendsTextOffDevice = true
        guard let long = store.record(.text("First part.\n\nSecond part."), source: nil),
            case .success(let longPlan) = service.plan(for: long, target: nil, pasteTarget: nil)
        else { return check(false, "failure: record and plan") }
        let failed = await ClipCollectedEvents.collect(service.translate(long, plan: longPlan, confirmedSecret: true))
        check(failed.error as? TranslationFailure == .network, "failure: engine error ends the stream")
        check(store.item(id: long.id)?.hasTranslations == false, "failure: partial result not cached")
        provider.setupFailure = .notConfigured
        check(service.plan(for: long, target: nil, pasteTarget: nil) == .failure(.notConfigured), "failure: plan")
    }

    private func partialAndMisaligned() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        provider.engine.transform = { text, _ in text.hasPrefix("Second") ? " " : "[T] " + text }
        let service = service(provider)
        guard let item = store.record(.text("First paragraph.\n\nSecond paragraph."), source: nil),
            case .success(let plan) = service.plan(for: item, target: "ja", pasteTarget: nil)
        else { return check(false, "partial: record and plan") }
        let partial = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(partial.error as? TranslationFailure == .invalidResponse, "partial: a missing segment fails")
        check(store.item(id: item.id)?.hasTranslations == false, "partial: not cached")

        // 缓存的分段与当前文档对不上（段数不同）：计划承诺了缓存时退化为整段重放，不联网
        store.setTranslation(
            ClipTranslation(
                target: "ja", source: "en", engineName: "Stub Engine", isOnDevice: true, createdAt: Date(),
                segmentation: ClipTextSegmenter.version, segments: ["A", "B", "C"]),
            for: item.id)
        guard case .success(let cachedPlan) = service.plan(for: item, target: "ja", pasteTarget: nil) else {
            return check(false, "misaligned: plan")
        }
        let requests = log.requests.count
        let replay = await ClipCollectedEvents.collect(
            service.translate(item, plan: cachedPlan, confirmedSecret: false))
        check(
            cachedPlan.isCached && replay.started?.count == 1 && replay.result?.plainText == "A\nB\nC"
                && replay.result?.fromCache == true && log.requests.count == requests,
            "misaligned: whole-text replay without the network")

        let swapService = self.service(ClipStubProvider(log: log))
        let secret = "key " + ["gh", "p_", String(repeating: "aB3dE5gH7j", count: 4)].joined()
        let swapProvider = ClipStubProvider(log: log)
        swapProvider.engine.sendsTextOffDevice = true
        let refused = await ClipCollectedEvents.collect(
            self.service(swapProvider).translate(
                text: secret, languages: TranslationLanguages(source: "en", target: "ja")))
        check(refused.error as? ClipTranslationRefusal == .secretNotConfirmed, "swap: secret not sent to the cloud")
        let local = await ClipCollectedEvents.collect(
            swapService.translate(text: secret, languages: TranslationLanguages(source: "en", target: "ja")))
        check(local.result != nil, "swap: on-device engine may translate it")
    }
}
#endif
