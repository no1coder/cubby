import Foundation
import Testing
@testable import CubbyCore

/// 受限 Markdown（**粗体**、[文字](链接)、`代码`）：写出、占位符、解析回行内样式、容错
@Suite("ClipInlineMarkup 受限 Markdown")
struct ClipInlineMarkupTests {
    private let docs = URL(string: "https://example.com/guide")!
    private let wiki = URL(string: "https://en.wikipedia.org/wiki/Foo_(bar)")!

    private func normalized(_ runs: [ClipRichRun]) -> [ClipRichRun] {
        ClipRichParagraph(style: .body, runs: runs).runs
    }

    // MARK: - 写出

    @Test("粗体、链接、代码；发送时行内代码与链接地址换成占位符，缓存时写原文")
    func serialize() {
        let runs = [
            ClipRichRun("Run "), ClipRichRun("npm install", isCode: true), ClipRichRun(" then "),
            ClipRichRun("read", isBold: true), ClipRichRun(" the "), ClipRichRun("guide", link: docs),
            ClipRichRun(" and "), ClipRichRun("a`b", isCode: true), ClipRichRun(" or "),
            ClipRichRun("wiki", isBold: true, link: wiki), ClipRichRun(" / "), ClipRichRun("again", link: docs),
        ]
        #expect(
            ClipInlineMarkup.serialize(runs, placeholders: true)
                == "Run `c1` then **read** the [guide](L1) and `c2` or [**wiki**](L2) / [again](L3)")
        #expect(ClipInlineMarkup.linkSlots(in: runs) == [docs, wiki, docs])
        #expect(
            ClipInlineMarkup.serialize(runs, placeholders: false)
                == #"Run `npm install` then **read** the [guide](https://example.com/guide) and `a\`b` or "#
                + "[**wiki**](https://en.wikipedia.org/wiki/Foo_%28bar%29) / [again](https://example.com/guide)")
        #expect(ClipInlineMarkup.codeSpans(in: runs) == ["npm install", "a`b"])
    }

    @Test("文字里的标记字符转义；粗体首尾空白挪到标记外；链接内的粗体；链接地址里的括号编码")
    func serializeEscapingAndNesting() {
        #expect(
            ClipInlineMarkup.serialize([ClipRichRun(#"a*b [c] `d` \e"#)], placeholders: false)
                == #"a\*b \[c\] \`d\` \\e"#)
        #expect(ClipInlineMarkup.serialize([ClipRichRun(" bold ", isBold: true)], placeholders: false) == " **bold** ")
        #expect(ClipInlineMarkup.serialize([ClipRichRun("   ", isBold: true)], placeholders: false) == "   ")
        let nested = [ClipRichRun("see ", isBold: true), ClipRichRun("docs", isBold: true, link: docs)]
        #expect(
            ClipInlineMarkup.serialize(nested, placeholders: false) == "**see** [**docs**](https://example.com/guide)")
        #expect(
            ClipInlineMarkup.serialize([ClipRichRun("Foo", link: wiki)], placeholders: false)
                == "[Foo](https://en.wikipedia.org/wiki/Foo_%28bar%29)")
    }

    // MARK: - 解析

    @Test("规范形式往返：写出再解析得到相同的行内文字")
    func roundTrip() {
        let runs = [
            ClipRichRun("Plain "), ClipRichRun("bold", isBold: true), ClipRichRun(" "),
            ClipRichRun("link", link: docs), ClipRichRun(" "), ClipRichRun("bold link", isBold: true, link: wiki),
            ClipRichRun(" "), ClipRichRun(#"code ` \ ]"#, isCode: true), ClipRichRun(#" * [x] \ end"#),
        ]
        let markup = ClipInlineMarkup.serialize(runs, placeholders: false)
        #expect(normalized(ClipInlineMarkup.parse(markup, allowedLinks: [docs, wiki])) == normalized(runs))
    }

    @Test("随机行内文字（固定种子）：规范形式往返不变")
    func randomizedRoundTrip() {
        var random = SeededGenerator(seed: 42)
        let alphabet = Array(#"ab *[]`\()中文 "#)
        for _ in 0..<300 {
            let runs = (0..<Int.random(in: 1...6, using: &random)).map { _ -> ClipRichRun in
                let length = Int.random(in: 1...8, using: &random)
                let raw = String((0..<length).map { _ in alphabet.randomElement(using: &random) ?? "a" })
                let isBold = Bool.random(using: &random)
                let text = isBold ? "b" + raw.filter { !$0.isWhitespace } + "b" : raw
                return ClipRichRun(
                    text, isBold: isBold, link: Int.random(in: 0..<4, using: &random) == 0 ? docs : nil,
                    isCode: Int.random(in: 0..<4, using: &random) == 0)
            }
            let markup = ClipInlineMarkup.serialize(runs, placeholders: false)
            #expect(normalized(ClipInlineMarkup.parse(markup, allowedLinks: [docs])) == normalized(runs), "\(markup)")
        }
    }

    @Test("大模型译文：占位符按编号还原（可调换顺序），编号越界或不是占位符时按字面")
    func restoresPlaceholders() {
        let spans = ["npm install", "SQLite"]
        let runs = ClipInlineMarkup.parse("先用 `c2`，再运行 `c1`；`c9` 与 `x`", codeSpans: spans)
        #expect(
            runs == [
                ClipRichRun("先用 "), ClipRichRun("SQLite", isCode: true), ClipRichRun("，再运行 "),
                ClipRichRun("npm install", isCode: true), ClipRichRun("；"), ClipRichRun("c9", isCode: true),
                ClipRichRun(" 与 "), ClipRichRun("x", isCode: true),
            ])
    }

    @Test("发送形式往返：占位符按本段的代码与链接还原（可调换顺序），得到相同的行内文字")
    func placeholderRoundTrip() {
        let runs = [
            ClipRichRun("See "), ClipRichRun("docs", link: docs), ClipRichRun(" and "),
            ClipRichRun("wiki", isBold: true, link: wiki), ClipRichRun(", run "), ClipRichRun("make", isCode: true),
        ]
        let sent = ClipInlineMarkup.serialize(runs, placeholders: true)
        let parsed = ClipInlineMarkup.parse(
            sent, codeSpans: ClipInlineMarkup.codeSpans(in: runs), linkSlots: ClipInlineMarkup.linkSlots(in: runs))
        #expect(normalized(parsed) == normalized(runs))
        let reordered = ClipInlineMarkup.parse(
            "先看[**维基**](L2)，再看[文档](L1)", linkSlots: ClipInlineMarkup.linkSlots(in: runs))
        #expect(
            reordered == [
                ClipRichRun("先看"), ClipRichRun("维基", isBold: true, link: wiki), ClipRichRun("，再看"),
                ClipRichRun("文档", link: docs),
            ])
    }

    @Test("大模型译文里的链接：编号未知、重复出现、直接写出的地址（即使是原文地址）都只保留文字")
    func maliciousLinkPlaceholders() {
        let slots = [docs]
        #expect(ClipInlineMarkup.parse("[x](L9)", linkSlots: slots) == [ClipRichRun("x")])
        #expect(ClipInlineMarkup.parse("[x](L0) [y](l1) [z](L1a)", linkSlots: slots).allSatisfy { $0.link == nil })
        #expect(ClipInlineMarkup.parse("[x](https://evil.example)", linkSlots: slots) == [ClipRichRun("x")])
        #expect(ClipInlineMarkup.parse("[x](https://example.com/guide)", linkSlots: slots) == [ClipRichRun("x")])
        #expect(ClipInlineMarkup.parse("[x](L1) [y](L1)", linkSlots: slots).allSatisfy { $0.link == nil })
        #expect(ClipInlineMarkup.parse("[x](L1) [y](L2)", linkSlots: [docs, wiki]).compactMap(\.link) == [docs, wiki])
        #expect(ClipInlineMarkup.parse("[x](L1)", linkSlots: []) == [ClipRichRun("x")])
        #expect(ClipInlineMarkup.parse("no link here", linkSlots: slots) == [ClipRichRun("no link here")])
    }

    @Test("只接受原文里的链接：模型编造或改写的地址只保留文字；未编码括号的地址也能认出")
    func onlyAllowedLinks() {
        #expect(ClipInlineMarkup.parse("[指南](https://evil.example)", allowedLinks: [docs]) == [ClipRichRun("指南")])
        #expect(
            ClipInlineMarkup.parse("[指南](https://example.com/guide)", allowedLinks: [docs]) == [
                ClipRichRun("指南", link: docs)
            ])
        #expect(
            ClipInlineMarkup.parse("[Foo](https://en.wikipedia.org/wiki/Foo_(bar))", allowedLinks: [wiki])
                == [ClipRichRun("Foo", link: wiki)])
        #expect(ClipInlineMarkup.parse("[x](https://example.com/guide)") == [ClipRichRun("x")])
    }

    @Test("容错：不成对或嵌套的 ** 丢弃，其余不合语法的标记按字面保留")
    func malformedMarkup() {
        #expect(ClipInlineMarkup.parse("**未闭合的粗体") == [ClipRichRun("未闭合的粗体")])
        // 按出现顺序两两配对
        #expect(
            ClipInlineMarkup.parse("**外 **内** 外**")
                == [ClipRichRun("外 ", isBold: true), ClipRichRun("内"), ClipRichRun(" 外", isBold: true)])
        #expect(ClipInlineMarkup.parse("[没有地址] 和 [空](  ) 和 [x](") == [ClipRichRun("[没有地址] 和 [空](  ) 和 [x](")])
        // 外层 [ 没有闭合按字面；内层是合法链接但地址不在原文里：只保留文字
        #expect(normalized(ClipInlineMarkup.parse("[a [b](c)")) == [ClipRichRun("[a b")])
        #expect(ClipInlineMarkup.parse("`未闭合代码") == [ClipRichRun("`未闭合代码")])
        #expect(ClipInlineMarkup.parse("单个 * 星号与 \\q 反斜杠") == [ClipRichRun("单个 * 星号与 \\q 反斜杠")])
        #expect(ClipInlineMarkup.parse("[]()") == [ClipRichRun("[]()")])
        #expect(ClipInlineMarkup.parse("[x](https://a.b") == [ClipRichRun("[x](https://a.b")])
        #expect(ClipInlineMarkup.parse("") == [])
    }

    @Test("病态输入保持线性：成千上万个未闭合的链接、粗体、代码标记按字面返回，不卡住")
    func pathologicalInputStaysLinear() {
        let clock = ContinuousClock()
        for pattern in ["[a](", "[a](((", "**[a](", "[`a`](", "(", "[a]", "`", "\\", "[**"] {
            let input = String(repeating: pattern, count: 20_000)
            let elapsed = clock.measure { _ = ClipInlineMarkup.parse(input) }
            #expect(elapsed < .seconds(5), "\(pattern)")
        }
        #expect(
            ClipInlineMarkup.plainText(String(repeating: "[a](", count: 20_000))
                == String(repeating: "[a](", count: 20_000))
        #expect(ClipInlineMarkup.parse("[a](x(y)z)") == [ClipRichRun("a")])
        #expect(ClipInlineMarkup.parse("[a](x(y) z)") == [ClipRichRun("[a](x(y) z)")])
    }

    @Test("粗体里的链接地址含 ** 时不会被当作粗体结束")
    func boldSkipsLinksAndCode() {
        let odd = URL(string: "https://a.b/**x")!
        let runs = ClipInlineMarkup.parse("**[t](https://a.b/**x) `**` z**", allowedLinks: [odd])
        #expect(
            runs == [
                ClipRichRun("t", isBold: true, link: odd), ClipRichRun(" ", isBold: true),
                ClipRichRun("**", isBold: true, isCode: true), ClipRichRun(" z", isBold: true),
            ])
    }

    @Test("plainText 去掉全部标记，保留文字与代码原文")
    func plainText() {
        #expect(ClipInlineMarkup.plainText(#"**粗体** [链接](https://a.b) `code` \*"#) == "粗体 链接 code *")
    }
}
