import Foundation
import Testing
@testable import CubbyCore

/// 疑似密钥的发送前检查：扫描该引擎实际会收到的文字，而不是条目的纯文本
@Suite("疑似密钥的发送前检查")
struct ClipSecretGateTests {
    private let token = FakeSecrets.github()

    private func rich(_ html: String, text: String) -> ClipTranslationDocument {
        ClipTranslationDocument.make(text: text, formats: ["public.html": Data(html.utf8)])
    }

    @Test("本机引擎从不需要确认")
    func onDevice() {
        let document = ClipTranslationDocument.plain("key " + token)
        #expect(!ClipSecretGate.needsConfirmation(document, input: .plainText, sendsTextOffDevice: false))
        #expect(!ClipSecretGate.needsConfirmation(document, input: .markup, sendsTextOffDevice: false))
    }

    @Test("纯文本里没有、富文本格式里有的疑似密钥：两种引擎都需要确认")
    func secretOnlyInFormats() {
        let document = rich("<p>Deploy with <b>token \(token)</b> today.</p>", text: "Deploy with the token today.")
        #expect(!SecretDetector.containsSecret("Deploy with the token today."))
        #expect(ClipSecretGate.needsConfirmation(document, input: .markup, sendsTextOffDevice: true))
        #expect(ClipSecretGate.needsConfirmation(document, input: .plainText, sendsTextOffDevice: true))
    }

    @Test("令牌只在链接地址里：发送的文字不含它，否则必须要求确认")
    func tokenInHref() {
        let document = rich(
            "<p>Read <a href=\"https://example.com/?key=\(token)\">the guide</a> first.</p>",
            text: "Read the guide first.")
        #expect(document.isRich)
        for input in [ClipTranslationBatch.Input.markup, .plainText] {
            let sent = document.sentTexts(markup: input == .markup)
            let leaks = sent.contains { $0.contains(token) }
            #expect(!leaks || ClipSecretGate.needsConfirmation(document, input: input, sendsTextOffDevice: true))
            #expect(!sent.contains { $0.contains("example.com") })
        }
    }

    @Test("不发送的段（代码块）里的疑似密钥不要求确认；普通段落里的要求")
    func onlySentSegments() {
        let document = rich("<p>Set the variable below.</p><pre>export KEY=\(token)</pre>", text: "x")
        #expect(!ClipSecretGate.needsConfirmation(document, input: .markup, sendsTextOffDevice: true))
        let plain = ClipTranslationDocument.plain("Hello team,\n\nthe key is " + token)
        #expect(ClipSecretGate.needsConfirmation(plain, input: .plainText, sendsTextOffDevice: true))
        #expect(!ClipSecretGate.needsConfirmation(.plain("Hello team"), input: .markup, sendsTextOffDevice: true))
    }
}
