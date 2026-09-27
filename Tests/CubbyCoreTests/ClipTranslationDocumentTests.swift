import Foundation
import Testing
@testable import CubbyCore

/// ClipTranslationDocument：C3 按段送引擎、按段缓存，C2 按段显示「对照」、粘贴纯文本 / 富文本
@Suite("ClipTranslationDocument 翻译文档")
struct ClipTranslationDocumentTests {
    private static let articleHTML = """
        <meta charset='utf-8'><h1>Why local-first apps feel instant</h1>
        <p>Every interaction skips the <b>network round trip</b>. <a href="https://example.com/local-first">Read the guide</a>.</p>
        <ul><li>Reads hit local storage first, usually <code>SQLite</code> in WAL mode</li></ul>
        <pre>PRAGMA journal_mode=WAL;</pre>
        """

    private var article: ClipTranslationDocument {
        ClipTranslationDocument.make(
            text: "Why local-first apps feel instant", formats: ["public.html": Data(Self.articleHTML.utf8)])
    }

    // MARK: - 纯文本

    @Test("纯文本：段与分段器一致；未翻译的段用原文，按原文的分隔符拼回")
    func plainDocument() {
        let document = ClipTranslationDocument.plain("- Buy milk\nhttps://a.b\n\nCall mom")
        #expect(!document.isRich)
        #expect(document.segments.map(\.plainText) == ["Buy milk", "https://a.b", "Call mom"])
        #expect(document.segments.map(\.markup) == document.segments.map(\.plainText))
        #expect(document.translatableSegments.map(\.index) == [0, 2])
        #expect(
            document.plainText(translations: ["\u{4E70}\u{725B}\u{5976}", nil, nil], markup: false)
                == "- \u{4E70}\u{725B}\u{5976}\nhttps://a.b\n\nCall mom")
        #expect(document.richText(translations: [], markup: false) == nil)
        #expect(document.original(at: 1) == AttributedString("https://a.b"))
        #expect(document.original(at: 9) == AttributedString())
        #expect(document.translation("x", at: 0, markup: true) == AttributedString("x"))
    }

    @Test("没有格式、格式无法解析或没有结构时按纯文本分段")
    func fallsBackToPlain() {
        #expect(!ClipTranslationDocument.make(text: "Hello", formats: [:]).isRich)
        #expect(
            !ClipTranslationDocument.make(text: "Hello", formats: ["public.html": Data("<p>Hello</p>".utf8)]).isRich)
        let codeOnly = ["public.html": Data("<pre>let x = 1</pre>".utf8)]
        #expect(!ClipTranslationDocument.make(text: "let x = 1", formats: codeOnly).isRich)
        #expect(ClipTranslationDocument.make(text: "Hello", formats: Fixtures.richFormats(for: "Hello")).isRich)
    }

    // MARK: - 富文本

    @Test("富文本：按段落分段；系统翻译发纯文本，大模型发受限 Markdown（行内代码与链接地址为占位符）；代码块不翻译")
    func richSegments() {
        let document = article
        #expect(document.isRich)
        #expect(
            document.segments.map(\.plainText) == [
                "Why local-first apps feel instant", "Every interaction skips the network round trip. Read the guide.",
                "Reads hit local storage first, usually SQLite in WAL mode", "PRAGMA journal_mode=WAL;",
            ])
        #expect(
            document.segments[1].markup == "Every interaction skips the **network round trip**. [Read the guide](L1).")
        #expect(document.sentTexts(markup: true) == document.translatableSegments.map(\.markup))
        #expect(document.sentTexts(markup: false) == document.translatableSegments.map(\.plainText))
        #expect(document.sentTexts(markup: true).allSatisfy { !$0.contains("example.com") })
        #expect(document.segments[2].markup == "Reads hit local storage first, usually `c1` in WAL mode")
        #expect(document.segments.map(\.isTranslatable) == [true, true, true, false])
        #expect(ClipRichTextRenderer.paragraphStyle(of: document.original(at: 0)) == .heading(level: 1))
        #expect(ClipRichTextRenderer.paragraphStyle(of: document.original(at: 2)) == .listItem(ordinal: nil, level: 1))
        #expect(document.original(at: 9) == AttributedString())
    }

    @Test("大模型流程：返回的标记还原占位符、剔除编造的链接，缓存规范形式；重建出带结构的富文本与纯文本")
    func llmFlow() throws {
        let document = article
        let outputs = [
            " 为什么本地优先的应用毫无延迟\n",
            "每次操作都省去了**网络往返**。[阅读指南](L1)，或[点这里](https://evil.example)、[这里](L9)。",
            "读写优先落到本地存储，通常是 WAL 模式下的 `c1`", nil,
        ]
        let stored = outputs.enumerated().map { index, output in
            output.map { document.storableTranslation($0, at: index, markup: true) }
        }
        #expect(stored[0] == "为什么本地优先的应用毫无延迟")
        #expect(stored[1] == "每次操作都省去了**网络往返**。[阅读指南](https://example.com/local-first)，或点这里、这里。")
        #expect(stored[2] == "读写优先落到本地存储，通常是 WAL 模式下的 `SQLite`")

        let entry = document.cacheEntry(
            target: "zh-Hans", source: "en", engineName: "DeepSeek", isOnDevice: false, createdAt: Fixtures.baseDate,
            translations: stored, markup: true)
        #expect(entry.usesInlineMarkup == true)
        #expect(entry.segmentation == ClipTextSegmenter.version)
        #expect(document.isAligned(with: entry))
        #expect(entry.plainText.contains("SQLite"))

        let segments = entry.segments
        #expect(
            document.plainText(translations: segments, markup: true) == """
                为什么本地优先的应用毫无延迟

                每次操作都省去了网络往返。阅读指南，或点这里、这里。

                \u{2022} 读写优先落到本地存储，通常是 WAL 模式下的 SQLite

                PRAGMA journal_mode=WAL;
                """)
        let rich = try #require(document.richText(translations: segments, markup: true))
        let bold = rich.runs.first { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(bold.map { String(rich[$0.range].characters) } == "网络往返")
        #expect(rich.runs.contains { $0.link == URL(string: "https://example.com/local-first") })
        #expect(
            rich.runs.contains { $0.inlinePresentationIntent == .code && String(rich[$0.range].characters) == "SQLite" }
        )
        let segment = document.translation(try #require(segments[2]), at: 2, markup: true)
        #expect(ClipRichTextRenderer.paragraphStyle(of: segment) == .listItem(ordinal: nil, level: 1))
        #expect(ClipRichTextRenderer.paragraphStyle(of: rich) == .heading(level: 1))
        #expect(!rich.runs.contains { $0.link?.host == "evil.example" })
    }

    @Test("链接地址从不发送：href 里带令牌的链接，两种引擎收到的文字都不含地址的任何部分；译文还原原文链接")
    func linkURLsAreNeverSent() throws {
        let token = FakeSecrets.jwt()
        let href = "https://portal.acme-corp.invalid/sso/callback?session=" + token
        let html = #"<p>Please <a href=""# + href + #"">Sign in</a> to <b>continue</b>.</p>"#
        let document = ClipTranslationDocument.make(
            text: "Please Sign in to continue.", formats: ["public.html": Data(html.utf8)])
        #expect(document.isRich)
        let payload = (document.sentTexts(markup: true) + document.sentTexts(markup: false)).joined(separator: "\n")
        #expect(payload.contains("[Sign in](L1)"))
        let windows = Set((0...(href.count - 5)).map { String(Array(href)[$0..<($0 + 5)]) })
        #expect(windows.allSatisfy { !payload.contains($0) })
        #expect(!SecretDetector.containsSecret(payload))

        let stored = document.storableTranslation("请[登录](L1)以**继续**。", at: 0, markup: true)
        let link = try #require(URL(string: href))
        let shown = document.translation(stored, at: 0, markup: true)
        #expect(shown.runs.compactMap(\.link) == [link])
        let rejected = document.storableTranslation("请[登录](" + href + ")以继续。", at: 0, markup: true)
        #expect(document.translation(rejected, at: 0, markup: true).runs.allSatisfy { $0.link == nil })
    }

    @Test("旧缓存（规范形式里写着真实地址）仍可重建：只接受与原文相同的地址")
    func legacyCachedLinks() throws {
        let document = article
        let legacy = "阅读[指南](https://example.com/local-first)或[别处](https://evil.example)。"
        let shown = document.translation(legacy, at: 1, markup: true)
        #expect(shown.runs.compactMap(\.link) == [try #require(URL(string: "https://example.com/local-first"))])
        let rich = try #require(document.richText(translations: ["t", legacy, nil, nil], markup: true))
        #expect(!rich.runs.contains { $0.link?.host == "evil.example" })
    }

    @Test("系统翻译流程：只发纯文本、只保留段落样式；段内标记符号按字面")
    func systemFlow() throws {
        let document = article
        let stored = ["为什么本地优先", "每次操作都省去了网络往返。**不是标记**", nil, nil].enumerated().map { index, output in
            output.map { document.storableTranslation($0, at: index, markup: false) }
        }
        let entry = document.cacheEntry(
            target: "zh-Hans", source: "en", engineName: "System", isOnDevice: true, createdAt: Fixtures.baseDate,
            translations: stored + ["ignored extra"], markup: false)
        #expect(entry.usesInlineMarkup == nil)
        #expect(entry.segments.count == 4)
        let rich = try #require(document.richText(translations: entry.segments, markup: false))
        // 译过的段只有段落样式：原文里的粗体与链接不再出现；未翻译的段保留原样（行内代码）
        let translated = rich.runs.filter { String(rich[$0.range].characters).contains("\u{7F51}\u{7EDC}") }
        #expect(translated.count == 1)
        #expect(translated.allSatisfy { $0.inlinePresentationIntent == nil && $0.link == nil })
        #expect(String(rich.characters).contains("**不是标记**"))
        #expect(rich.runs.contains { $0.inlinePresentationIntent == .code })
        #expect(ClipRichTextRenderer.paragraphStyle(of: rich) == .heading(level: 1))
        #expect(
            ClipRichTextRenderer.paragraphStyle(of: document.translation("x", at: 0, markup: false))
                == .heading(level: 1))
    }

    @Test("缓存对齐：版本号或段数不同、图片译文都不对齐；空译文与不翻译的段用原文")
    func alignment() {
        let document = ClipTranslationDocument.plain("One\n\nTwo")
        #expect(document.isAligned(with: TranslationFixtures.text(segments: ["1", "2"])))
        #expect(!document.isAligned(with: TranslationFixtures.text(segments: ["1"])))
        let oldVersion = ClipTranslation(
            target: "ja", source: nil, engineName: "S", isOnDevice: true, createdAt: Fixtures.baseDate,
            segmentation: 0, segments: ["1", "2"])
        #expect(!document.isAligned(with: oldVersion))
        #expect(!document.isAligned(with: TranslationFixtures.image(blob: "t.png", segments: ["1", "2"])))
        #expect(document.plainText(translations: ["", "2"], markup: false) == "One\n\n2")
        let rich = article
        #expect(
            rich.plainText(translations: ["", nil, nil, "X"], markup: true).hasPrefix(
                "Why local-first apps feel instant"))
        #expect(rich.plainText(translations: ["", nil, nil, "X"], markup: true).hasSuffix("PRAGMA journal_mode=WAL;"))
    }
}
