#if DEBUG
import AppKit
import CubbyCore
import Foundation

// 自检的其余场景：目标语言与存为新条目、⇄ 对调、图片、复制时自动翻译
extension ClipTranslationSelfTest {
    func targetsAndSaving() {
        let service = service(ClipStubProvider(log: ClipStubLog()))
        let app = "com.example.chat"
        service.setTarget("ja", rememberFor: app)
        check(service.rememberedTarget(for: app) == "ja", "target: remembered for the paste target")
        guard let item = store.record(.text("Good morning, everyone."), source: nil) else {
            return check(false, "target: record")
        }
        check(
            (try? service.plan(for: item, target: nil, pasteTarget: app).get())?.languages.target == "ja",
            "target: plan")
        check(
            (try? service.plan(for: item, target: "fr", pasteTarget: app).get())?.languages.target == "fr",
            "target: explicit")
        service.setTarget(nil, rememberFor: app)
        service.setTarget("de", rememberFor: nil)
        check(service.rememberedTarget(for: app) == nil, "target: forgotten")
        check(
            (try? service.plan(for: item, target: nil, pasteTarget: app).get())?.languages.target == "de",
            "target: shared")

        let result = ClipTranslationResult(
            plainText: "Guten Morgen", richText: nil, imageURL: nil, engineName: "Stub", isOnDevice: true,
            fromCache: false)
        settings.isPaused = true
        check(!service.saveAsNewItem(result), "save: refused while paused")
        settings.isPaused = false
        check(service.saveAsNewItem(result), "save: saved")
        check(!service.saveAsNewItem(result.with(text: "")), "save: empty text refused")
        check(service.eligibility(of: item) == .eligible, "eligibility: text")
        let link = store.record(.text("https://example.com"), source: nil)
        check(link.map(service.eligibility(of:)) == .unsupported(.link), "eligibility: link")
    }

    func swap() async {
        let log = ClipStubLog()
        let service = service(ClipStubProvider(log: log))
        // 只比较译文：前一项「存为新条目」的后台记录可能在此期间入历史
        let before = store.history.items.compactMap(\.translations)
        let events = await ClipCollectedEvents.collect(
            service.translate(
                text: "Line one.\nLine two.", languages: TranslationLanguages(source: "zh-Hans", target: "en")))
        check(events.result?.plainText.hasPrefix("[T] ") == true && events.result?.fromCache == false, "swap: result")
        check(store.history.items.compactMap(\.translations) == before, "swap: nothing cached")
    }

    // MARK: - 图片

    func image() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        let service = service(provider)
        guard let png = Self.syntheticImage(),
            let item = store.record(.image(png: png, width: 1200, height: 400), source: nil),
            case .success(let plan) = service.plan(for: item, target: "zh-Hans", pasteTarget: nil)
        else { return check(false, "image: record and plan") }
        let events = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: true))
        let sent = log.requests.flatMap(\.self)
        check(sent.contains { $0.localizedCaseInsensitiveContains("save your changes") }, "image: recognized text sent")
        check(!sent.contains { $0.contains("ghp_") }, "image: secret-like block never sent")
        check(!events.imageBlocks.isEmpty, "image: blocks streamed")
        guard let url = events.result?.imageURL, let data = try? Data(contentsOf: url),
            let decoded = HistoryImageFrame.decode(data)
        else { return check(false, "image: translated PNG") }
        check(decoded.image.width == 1200 && decoded.dpi == 144, "image: translated PNG keeps size and DPI")
        check(store.item(id: item.id)?.translation(for: "zh-Hans")?.imageName != nil, "image: cached as blob")
        let replay = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(replay.result?.fromCache == true && replay.result?.imageURL == url, "image: cache replay")
        check(replay.result.map(service.saveAsNewItem) == true, "image: save as new item")
    }

    /// 1200×400 像素、144 DPI 的白底黑字图：一行普通英文、一行疑似密钥
    private static func syntheticImage() -> Data? {
        guard
            let context = CGContext(
                data: nil, width: 1200, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
        ]
        NSString(string: "Save your changes").draw(at: CGPoint(x: 60, y: 250), withAttributes: attributes)
        let token = ["gh", "p_", String(repeating: "aB3dE5gH7j", count: 3), "aB3dE5"].joined()
        NSString(string: token).draw(at: CGPoint(x: 60, y: 80), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().flatMap { ClipTranslatedImage.pngData($0, dpi: 144) }
    }

    // MARK: - 复制时自动翻译

    func autoTranslate() async {
        let log = ClipStubLog()
        let provider = ClipStubProvider(log: log)
        let translator = ClipAutoTranslator(
            store: store, settings: settings, provider: provider, preferredLanguages: { ["zh-Hans"] })
        let text = "The meeting has been moved to Thursday afternoon at three."
        guard let off = store.record(.text(text), source: nil) else { return check(false, "auto: record") }
        translator.enqueue(off)
        try? await Task.sleep(for: .seconds(1))
        check(log.requests.isEmpty, "auto: off by default")

        settings.setTranslatesClipsOnCopy(true)
        check(settings.showsTranslationOnCards, "auto: turning it on shows translations on cards")
        provider.installed = false
        translator.enqueue(off)
        try? await Task.sleep(for: .seconds(1))
        check(log.requests.isEmpty, "auto: skipped when the language isn't downloaded")

        provider.installed = true
        translator.track(store.recordInBackground(.text(text + " Bring the slides."), source: nil))
        try? await Task.sleep(for: .seconds(1.5))
        let item = store.history.items.first
        let entry = item?.translation(for: "zh-Hans")
        check(entry?.engineName == "Stub On-Device" && entry?.isOnDevice == true, "auto: translated on device")

        provider.onDevice.delay = .seconds(3)
        guard let slow = store.record(.text("Please remember to water the plants tomorrow."), source: nil) else {
            return
        }
        translator.enqueue(slow)
        try? await Task.sleep(for: .seconds(1))
        settings.isPaused = true
        try? await Task.sleep(for: .seconds(1))
        check(log.cancellations == 1, "auto: pausing cancels the running translation")
        check(store.item(id: slow.id)?.hasTranslations == false, "auto: cancelled translation not cached")
        settings.isPaused = false
        settings.setTranslatesClipsOnCopy(false)
    }
}

extension ClipTranslationResult {
    fileprivate func with(text: String) -> ClipTranslationResult {
        ClipTranslationResult(
            plainText: text, richText: richText, imageURL: imageURL, engineName: engineName, isOnDevice: isOnDevice,
            fromCache: fromCache)
    }
}
#endif
