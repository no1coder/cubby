import Foundation
import Testing
@testable import CubbyCore

/// 系统翻译的行内代码保护：占位符 {N} 代替代码发送，译文返回后还原；占位符被改坏时报告失败
@Suite("行内代码占位符保护")
struct ClipInlineCodeProtectionTests {
    private typealias Protection = ClipInlineCodeProtection

    private let plainPieces: [Protection.Piece] = [
        .text("Run "), .code("`npm install`"), .text(" then "), .code("`npm test`"), .text("."),
    ]

    private var plain: Protection {
        Protection(pieces: plainPieces, plainText: "Run `npm install` then `npm test`.", markup: false)
    }

    @Test("纯文本：代码换成 {1}、{2} 发送；还原为含反引号的原文，顺序可以改变")
    func plainRoundTrip() {
        #expect(plain.sent == "Run {1} then {2}.")
        #expect(plain.restore("先运行 {1}，再运行 {2}。") == "先运行 `npm install`，再运行 `npm test`。")
        #expect(plain.restore("{2} 之前先运行 {1}") == "`npm test` 之前先运行 `npm install`")
        #expect(!plain.isIdentity)
    }

    @Test("全角括号与数字、其他文字的数字、括号内的空白都接受")
    func tolerantTokens() {
        #expect(plain.restore("运行｛１｝，然后｛ 2 ｝。") == "运行`npm install`，然后`npm test`。")
        #expect(plain.restore("شغّل {١} ثم {٢}") == "شغّل `npm install` ثم `npm test`")
    }

    @Test("占位符缺失、重复、多出或编号越界时判定失败")
    func brokenTokens() {
        #expect(plain.restore("运行 {1}。") == nil)
        #expect(plain.restore("运行 {1}、{1} 和 {2}") == nil)
        #expect(plain.restore("运行 {1}、{2} 和 {3}") == nil)
        #expect(plain.restore("运行 {0} 和 {2}") == nil)
        #expect(plain.restore("运行 1 和 2") == nil)
    }

    @Test("不像占位符的括号按普通文字：没有数字、数字过长、没有闭括号、跨行")
    func nonTokens() {
        #expect(plain.restore("{1} {2} {} {a} {12345} {3") == "`npm install` `npm test` {} {a} {12345} {3")
        #expect(plain.restore("{1} {\n3} {2}") == "`npm install` {\n3} `npm test`")
    }

    @Test("原文里本就有形如占位符的文字、没有代码或不保护时：按原文发送，输出原样使用")
    func unprotected() {
        let collision = Protection(
            pieces: [.text("Use {1} for "), .code("`x`")], plainText: "Use {1} for `x`", markup: false)
        #expect(collision.sent == "Use {1} for `x`")
        #expect(collision.isIdentity)
        #expect(collision.restore("用 {1} 表示 `x`") == "用 {1} 表示 `x`")

        let noCode = Protection(pieces: [.text("Hello")], plainText: "Hello", markup: false)
        #expect(noCode.sent == "Hello")
        #expect(noCode.restore("{9}") == "{9}")

        let off = Protection(pieces: plainPieces, plainText: "raw", markup: false, protects: false)
        #expect(off.sent == "raw")
        #expect(off.isIdentity)
    }

    @Test("富文本：代码还原为 `cN` 占位符，其余文字按受限 Markdown 转义")
    func markupRestoration() {
        let rich = Protection(
            pieces: [.text("Set "), .code("c1"), .text(" to *true*")], plainText: "Set debug to *true*", markup: true)
        #expect(rich.sent == "Set {1} to *true*")
        #expect(rich.restore("将 {1} 设为 *true* [x]") == #"将 `c1` 设为 \*true\* \[x\]"#)
        #expect(!rich.isIdentity)

        let escapesOnly = Protection(pieces: [.text("a")], plainText: "a", markup: true)
        #expect(escapesOnly.restore("a\\b`c") == #"a\\b\`c"#)
        #expect(!escapesOnly.isIdentity)
    }

    @Test("纯文本分段：同一行内成对的反引号为代码；空的一对、不成对与跨行的按文字")
    func plainPiecesOfText() {
        #expect(Protection.pieces(of: "Run `npm i` now") == [.text("Run "), .code("`npm i`"), .text(" now")])
        #expect(Protection.pieces(of: "`a` and `b`") == [.code("`a`"), .text(" and "), .code("`b`")])
        #expect(Protection.pieces(of: "a `` b `c` d") == [.text("a `` b "), .code("`c`"), .text(" d")])
        #expect(Protection.pieces(of: "one ` two") == [.text("one ` two")])
        #expect(Protection.pieces(of: "x `a\nb` y") == [.text("x `a\nb` y")])
        #expect(Protection.pieces(of: "") == [])
    }

    @Test("富文本分段：代码行内文字为代码，相邻的普通文字合并（粗体、链接不影响）")
    func richPieces() {
        let runs = [
            ClipRichRun("Open "), ClipRichRun("the file", isBold: true), ClipRichRun(" "),
            ClipRichRun("c1", isCode: true), ClipRichRun("c2", isBold: true, isCode: true), ClipRichRun(" now"),
        ]
        #expect(
            Protection.pieces(of: runs) == [
                .text("Open the file "), .code("c1"), .code("c2"), .text(" now"),
            ])
    }
}
