import Foundation
import Testing
@testable import CubbyCore

/// 带期望语言的代码样本，便于在参数化测试中辨认
struct CodeLanguageSample: Sendable, CustomTestStringConvertible {
    let label: String
    let text: String
    let expected: CodeLanguage

    init(_ label: String, _ expected: CodeLanguage, _ text: String) {
        self.label = label
        self.expected = expected
        self.text = text
    }

    var testDescription: String { label }
}

@Suite("CodeLanguage 语言识别")
struct CodeLanguageTests {
    @Test("徽标名称是固定的专有名词")
    func displayNames() {
        let names = CodeLanguage.allCases.map(\.displayName)
        #expect(
            names == ["Swift", "JavaScript", "Python", "JSON", "Shell", "HTML", "CSS", "SQL", "Go", "Rust"])
    }

    @Test("真实代码片段识别为对应语言", arguments: CodeLanguageSamples.all)
    func detectsLanguage(_ sample: CodeLanguageSample) {
        #expect(CodeLanguage.detect(sample.text) == sample.expected)
    }

    @Test(
        "散文、链接、单词、空文本、颜色值不识别为任何语言",
        arguments: [
            TextSample("空字符串", ""),
            TextSample("只有空白", "   \n\t  \n"),
            TextSample("单个单词", "hello"),
            TextSample("数字", "12345"),
            TextSample("HEX 颜色", "#FF5733"),
            TextSample("短 HEX 颜色", "#fff"),
            TextSample("链接", "https://github.com/no1coder/cubby/releases?tag=v0.2.1#notes"),
            TextSample("邮箱", "jackie@example.com"),
            TextSample("英文散文", "Let me know if this works for you.\nThanks, and have a great weekend!"),
            TextSample("含 select/from/import 的散文", "Please select the files from the list and import them."),
            TextSample("含 make/git 的散文", "Make sure you commit your changes.\nUse git before you push."),
            TextSample("以冒号结尾的散文", "if you want, we can meet at 3pm:\nfor example at the cafe:"),
            TextSample("问句散文", "Where are you from?\nI'm from Vienna, where it rains."),
            TextSample("中文散文", "今天下午三点开会，请准时参加。\n记得带上电脑和充电器。"),
            TextSample("中英混排", "明天 review 一下 PR，然后 merge 到 main。"),
            TextSample("Markdown 列表", "- buy milk\n- call mom\n- write tests"),
            TextSample("单条命令", "git status"),
            TextSample("不是 JSON 的方括号文本", "[x] done\n[ ] todo"),
        ])
    func proseIsNotCode(_ sample: TextSample) {
        #expect(CodeLanguage.detect(sample.text) == nil)
    }

    @Test("合法 JSON 优先识别为 JSON，JS 对象字面量不是 JSON")
    func jsonVersusObjectLiteral() {
        #expect(CodeLanguage.detect(#"{"name": "Ada", "age": 36}"#) == .json)
        #expect(CodeLanguage.detect("[1, 2, 3]") == .json)
        #expect(CodeLanguage.detect("{ name: 'Ada', age: 36 }") != .json)
        #expect(CodeLanguage.detect(#"const user = {"name": "Ada"};"#) == .javascript)
    }

    @Test("超大 JSON 用结构检查识别，不完整解析")
    func hugeJSON() {
        let element = #"{"id": 1, "name": "item", "tags": ["a", "b"]}"#
        let text = "[" + Array(repeating: element, count: 50_000).joined(separator: ",\n") + "]"
        #expect(text.utf8.count > 2_000_000)
        #expect(CodeLanguage.detect(text) == .json)
    }

    @Test("超大文本首尾不像 JSON 时不当作 JSON")
    func hugeBracketedText() {
        let body = String(repeating: "lorem ipsum dolor sit amet ", count: 4_000)
        #expect(CodeLanguage.detect("{" + body + "}") == nil)
        #expect(CodeLanguage.detect("[ " + body + "]") == nil)
        #expect(CodeLanguage.detect(#"{"a": 1, "# + body) == nil)
        // 开括号后的样本全是空白，无从判断
        #expect(CodeLanguage.detect("{" + String(repeating: " ", count: 70_000) + "}") == nil)
    }

    @Test("2 MB 输入也能很快返回")
    func hugeInputIsFast() {
        let code = String(repeating: "let value = compute(x)  // note\n", count: 70_000)
        let prose = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 50_000)
        let line = String(repeating: "a", count: 2_000_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            #expect(CodeLanguage.detect(code) == .swift)
            #expect(CodeLanguage.detect(prose) == nil)
            #expect(CodeLanguage.detect(line) == nil)
        }
        #expect(elapsed < .seconds(1))
    }

    @Test("Swift 与 Go 都说得通的片段不下结论")
    func ambiguousReturnsNil() {
        // func 同时是 Swift 与 Go 的特征，其余部分不偏向任何一方
        #expect(CodeLanguage.detect("func run() {\n    start()\n}") == nil)
    }
}
