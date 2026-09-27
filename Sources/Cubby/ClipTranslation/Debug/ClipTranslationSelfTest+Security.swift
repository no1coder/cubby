#if DEBUG
import CubbyCore
import Foundation

// 自检的安全场景：疑似密钥按实际发送的文字检查、计划过期（缓存被清除、换了云端主机）
extension ClipTranslationSelfTest {
    /// 运行时拼接的假令牌：源码中不出现完整的令牌字面量
    private static var fakeToken: String {
        ["gh", "p_", String(repeating: "aB3dE5gH7j", count: 4)].joined()
    }

    private func cloudProvider(_ log: ClipStubLog, host: String = "api.example.com") -> ClipStubProvider {
        let provider = ClipStubProvider(log: log)
        provider.engine.sendsTextOffDevice = true
        provider.host = host
        provider.input = .markup
        return provider
    }

    func securityGates() async {
        await secretOnlyInFormats()
        await secretInLinkAddress()
        await clearedCache()
        await hostChanged()
    }

    /// 纯文本里没有、HTML 里有的疑似密钥：翻译时按实际发送的文字拦下；构建过文档后 plan 也能判断
    private func secretOnlyInFormats() async {
        let log = ClipStubLog()
        let service = service(cloudProvider(log))
        let html = "<p>Deploy with <b>token \(Self.fakeToken)</b> today.</p>"
        guard
            let item = store.record(
                .richText("Deploy with the token today.", formats: ["public.html": Data(html.utf8)]), source: nil),
            case .success(let plan) = service.plan(for: item, target: "ja", pasteTarget: nil)
        else { return check(false, "gate: record and plan") }
        let blocked = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        check(
            blocked.error as? ClipTranslationRefusal == .secretNotConfirmed && log.requests.isEmpty,
            "gate: secret in the rich payload isn't sent without confirmation")
        let replanned = try? service.plan(for: item, target: "ja", pasteTarget: nil).get()
        check(replanned?.needsSecretConfirmation == true, "gate: plan scans the payload once the document is built")
        let confirmed = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: true))
        check(confirmed.result != nil && log.requests.count == 1, "gate: sent after confirmation")
    }

    /// 令牌只在链接地址里：链接地址不发送，发送的文字里也就没有它
    private func secretInLinkAddress() async {
        let log = ClipStubLog()
        let service = service(cloudProvider(log))
        let html = "<p>Read <a href=\"https://example.com/?key=\(Self.fakeToken)\">the guide</a> first.</p>"
        guard
            let item = store.record(
                .richText("Read the guide first.", formats: ["public.html": Data(html.utf8)]), source: nil),
            case .success(let plan) = service.plan(for: item, target: "ja", pasteTarget: nil)
        else { return check(false, "href: record and plan") }
        let events = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: false))
        let sent = log.requests.flatMap(\.self)
        let leaked = sent.contains { $0.contains(Self.fakeToken) }
        check(!leaked || events.error as? ClipTranslationRefusal == .secretNotConfirmed, "href: token never sent")
        check(!sent.joined().contains("example.com"), "href: link address not sent")
    }

    /// 计划承诺了缓存，翻译前缓存被清除：重新 plan，不跳过疑似密钥确认直接联网
    private func clearedCache() async {
        let log = ClipStubLog()
        let service = service(cloudProvider(log))
        guard let item = store.record(.text("Token " + Self.fakeToken + " expires soon."), source: nil),
            case .success(let first) = service.plan(for: item, target: "fr", pasteTarget: nil)
        else { return check(false, "cleared: record and plan") }
        _ = await ClipCollectedEvents.collect(service.translate(item, plan: first, confirmedSecret: true))
        guard case .success(let cached) = service.plan(for: item, target: "fr", pasteTarget: nil), cached.isCached
        else { return check(false, "cleared: cached plan") }
        store.clearTranslations()
        let requests = log.requests.count
        let events = await ClipCollectedEvents.collect(service.translate(item, plan: cached, confirmedSecret: false))
        check(
            events.error as? ClipTranslationRefusal == .planOutdated && log.requests.count == requests,
            "cleared: cached plan without a cache is outdated")
    }

    /// 计划之后换了云端主机：为原主机做的确认不带过去
    private func hostChanged() async {
        let log = ClipStubLog()
        let provider = cloudProvider(log, host: "api.one.example")
        let service = service(provider)
        guard let item = store.record(.text("Please forward this to the whole team."), source: nil),
            case .success(let plan) = service.plan(for: item, target: "de", pasteTarget: nil)
        else { return check(false, "host: record and plan") }
        provider.host = "api.two.example"
        let events = await ClipCollectedEvents.collect(service.translate(item, plan: plan, confirmedSecret: true))
        check(
            events.error as? ClipTranslationRefusal == .planOutdated && log.requests.isEmpty,
            "host: another cloud host makes the plan outdated")
    }
}
#endif
