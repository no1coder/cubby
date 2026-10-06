import Testing
@testable import CubbyCore

/// 结果拼接（docs/TEXT-PICK-DESIGN.md P8）：相邻选中的块（中间只有空白）按原文连成一段；
/// 段与段之间：原文间隔含换行 → 换行；两侧都是中日韩文字 → 直接相连；否则一个空格
@Suite("TextPickResult 结果拼接")
struct TextPickResultTests {
    /// 按词块文字选取（同一文字取第一个未选的）
    private func result(_ source: String, picking picked: [String]) -> String {
        let document = TextPickTokenizer.document(for: source)
        var indices: Set<Int> = []
        for text in picked {
            if let index = document.tokens.indices.first(where: {
                document.tokens[$0].text == text && !indices.contains($0)
            }) {
                indices.insert(index)
            }
        }
        return TextPickResult.text(of: document, selection: TextPickSelection(indices: indices))
    }

    @Test("没有选取时为空串")
    func emptySelection() {
        let document = TextPickTokenizer.document(for: "hello world")
        #expect(TextPickResult.text(of: document, selection: TextPickSelection()).isEmpty)
    }

    @Test("越界的序号被忽略")
    func ignoresOutOfRange() {
        let document = TextPickTokenizer.document(for: "hello world")
        #expect(TextPickResult.text(of: document, selection: TextPickSelection(indices: [1, 9])) == "world")
    }

    @Test("相邻选中的块保留原文的空格与换行")
    func adjacentKeepsOriginal() {
        #expect(result("hello   world", picking: ["hello", "world"]) == "hello   world")
        #expect(result("first line\nsecond", picking: ["line", "second"]) == "line\nsecond")
        #expect(result("a\n\nb", picking: ["a", "b"]) == "a\n\nb")
        #expect(result("邮箱 wang.xm@example.com。", picking: ["wang.xm@example.com", "。"]) == "wang.xm@example.com。")
    }

    @Test("段与段之间：拉丁文字加一个空格")
    func latinRunsJoinWithSpace() {
        #expect(result("one two three four", picking: ["one", "three", "four"]) == "one three four")
    }

    @Test("段与段之间：两侧都是中文时直接相连")
    func cjkRunsJoinDirectly() {
        #expect(result("会议改到周四下午", picking: ["会议", "下午"]) == "会议下午")
        #expect(result("地址：北京市", picking: ["地址", "北京市"]) == "地址北京市")
    }

    @Test("段与段之间：一侧不是中日韩文字时加空格")
    func mixedBoundaryJoinsWithSpace() {
        #expect(result("SOHO现代城A座", picking: ["SOHO", "城"]) == "SOHO 城")
        #expect(result("会议 at 3 下午", picking: ["会议", "3"]) == "会议 3")
    }

    @Test("段与段之间：原文间隔含换行时用一个换行")
    func gapWithNewlineJoinsWithNewline() {
        #expect(result("alpha beta\ngamma", picking: ["alpha", "gamma"]) == "alpha\ngamma")
        #expect(result("会议改到\n\n下午", picking: ["会议", "下午"]) == "会议\n下午")
    }

    @Test("全角标点与假名、韩文都算中日韩文字")
    func cjkClassification() {
        for character: Character in ["中", "の", "カ", "한", "，", "。", "：", "「", "\u{3000}", "Ａ", "𠀀"] {
            #expect(TextPickResult.isCJK(character), "\(character)")
        }
        for character: Character in ["a", "1", ",", ".", "—", "é", "🎉", "“"] {
            #expect(!TextPickResult.isCJK(character), "\(character)")
        }
    }

    @Test("字符数按用户看到的字符计")
    func characterCount() {
        let document = TextPickTokenizer.document(for: "会议 🎉 ok")
        let all = TextPickSelection().togglingAll(count: document.tokens.count)
        let text = TextPickResult.text(of: document, selection: all)
        #expect(text == "会议 🎉 ok")
        #expect(text.count == 7)
    }
}
