import Foundation
import Testing
@testable import CubbyCore

/// 剪贴板文本 ↔ 引擎：段落映射成块、译文按 id 对回段；系统翻译的行内代码占位符保护与失败后的重译
@Suite("剪贴板翻译批次")
struct ClipTranslationBatchTests {
    private static let html = """
        <meta charset='utf-8'><p>Run <code>npm install</code> to set up the <b>project</b>.</p>
        <pre>npm test</pre>
        <p>See <a href="https://example.com/docs">the docs</a>.</p>
        """

    private let rich = ClipTranslationDocument.make(
        text: "Run npm install to set up the project.", formats: ["public.html": Data(Self.html.utf8)])

    @Test("大模型：可翻译段各一块（id = 段序号），发送受限 Markdown；译文还原行内代码")
    func llmBatch() throws {
        let batch = ClipTranslationBatch(document: rich, input: .markup)
        #expect(rich.isRich)
        #expect(batch.blocks.map(\.id) == [0, 2])
        #expect(batch.blocks.map(\.text) == rich.translatableSegments.map(\.markup))
        #expect(batch.blocks.allSatisfy { $0.lines.isEmpty && $0.alignment == .leading })
        #expect(batch.blocks[0].text.contains("`c1`"))
        #expect(batch.storesMarkup)

        let arrival = batch.arrival(BlockTranslation(blockID: 0, text: " 运行 `c1` 来设置**项目**。 "))
        guard case .translated(0, let stored)? = arrival else {
            Issue.record("unexpected arrival \(String(describing: arrival))")
            return
        }
        #expect(stored == "运行 `npm install` 来设置**项目**。")
        let shown = rich.translation(stored, at: 0, markup: true)
        #expect(shown.runs.contains { $0.inlinePresentationIntent == .code })
    }

    @Test("系统翻译：行内代码换成 {1} 发送，还原后保持代码样式；缓存为受限 Markdown")
    func systemBatchRestoresCode() throws {
        let batch = ClipTranslationBatch(document: rich, input: .plainText)
        #expect(batch.blocks.map(\.id) == [0, 2])
        #expect(batch.blocks[0].text == "Run {1} to set up the project.")
        #expect(batch.blocks[1].text == "See the docs.")
        #expect(batch.storesMarkup)

        let first = batch.arrival(BlockTranslation(blockID: 0, text: "运行 {1} 来设置项目*。"))
        #expect(first == .translated(index: 0, text: #"运行 `npm install` 来设置项目\*。"#))
        let second = batch.arrival(BlockTranslation(blockID: 2, text: "参见文档。"))
        #expect(second == .translated(index: 2, text: "参见文档。"))

        let translations = batch.translations([0: #"运行 `npm install` 来设置项目\*。"#, 2: "参见文档。"])
        #expect(translations == [#"运行 `npm install` 来设置项目\*。"#, nil, "参见文档。"])
        let entry = rich.cacheEntry(
            target: "zh-Hans", source: "en", engineName: "System", isOnDevice: true, createdAt: Fixtures.baseDate,
            translations: translations, markup: batch.storesMarkup)
        #expect(entry.usesInlineMarkup == true)
        #expect(entry.plainText == "运行 npm install 来设置项目*。\n参见文档。")
        let text = rich.plainText(translations: translations, markup: batch.storesMarkup)
        #expect(text.contains("运行 npm install 来设置项目*。"))
        #expect(text.contains("npm test"))
        let shown = rich.translation(try #require(translations[0]), at: 0, markup: true)
        let code = shown.runs.filter { $0.inlinePresentationIntent == .code }
        #expect(code.map { String(shown[$0.range].characters) } == ["npm install"])
    }

    @Test("占位符被改坏：报告重译；重译不带保护（代码原文随文字发送），译文按文字转义")
    func retryWithoutProtection() {
        let batch = ClipTranslationBatch(document: rich, input: .plainText)
        #expect(batch.arrival(BlockTranslation(blockID: 0, text: "运行 npm 安装")) == .needsRetry(index: 0))

        let retry = batch.retrying([0, 1, 7])
        #expect(retry.blocks.map(\.id) == [0])
        #expect(retry.blocks[0].text == "Run npm install to set up the project.")
        #expect(
            retry.arrival(BlockTranslation(blockID: 0, text: "运行 npm install 来设置 [项目]"))
                == .translated(index: 0, text: #"运行 npm install 来设置 \[项目\]"#))
        #expect(retry.arrival(BlockTranslation(blockID: 2, text: "x")) == nil)
    }

    @Test("纯文本条目：反引号括起的代码受保护、原样还原；缓存不是 Markdown")
    func plainDocument() {
        let document = ClipTranslationDocument.plain("Run `make test` before pushing.\n\nThanks!")
        let batch = ClipTranslationBatch(document: document, input: .plainText)
        #expect(!batch.storesMarkup)
        #expect(batch.blocks.map(\.text) == ["Run {1} before pushing.", "Thanks!"])
        #expect(
            batch.arrival(BlockTranslation(blockID: 0, text: "推送前运行 {1}。"))
                == .translated(index: 0, text: "推送前运行 `make test`。"))
        #expect(batch.arrival(BlockTranslation(blockID: 1, text: "谢谢 *")) == .translated(index: 1, text: "谢谢 *"))

        let llm = ClipTranslationBatch(document: document, input: .markup)
        #expect(llm.blocks.map(\.text) == ["Run `make test` before pushing.", "Thanks!"])
        #expect(llm.storesMarkup)
        #expect(llm.arrival(BlockTranslation(blockID: 1, text: " 谢谢！ ")) == .translated(index: 1, text: "谢谢！"))
    }

    @Test("不属于本批的块、还原后为空的译文都忽略；没有可翻译段时没有块")
    func ignoredArrivals() {
        let batch = ClipTranslationBatch(document: rich, input: .markup)
        #expect(batch.arrival(BlockTranslation(blockID: 1, text: "npm 测试")) == nil)
        #expect(batch.arrival(BlockTranslation(blockID: 9, text: "x")) == nil)
        #expect(batch.arrival(BlockTranslation(blockID: 2, text: "   ")) == nil)

        let codeOnly = ClipTranslationBatch(document: ClipTranslationDocument.plain("https://a.b"), input: .plainText)
        #expect(codeOnly.blocks.isEmpty)
        #expect(codeOnly.translations([:]) == [nil])
    }
}
