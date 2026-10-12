import Foundation
import Testing
@testable import CubbyCore

/// 便于断言的着色片段：类型 + 对应的原文
struct CodeSpan: Equatable, CustomStringConvertible {
    let kind: CodeToken.Kind
    let text: String

    init(_ kind: CodeToken.Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    var description: String { "\(kind):\(text)" }
}

@Suite("CodeSyntax 轻量着色")
struct CodeSyntaxTests {
    private func spans(_ text: String, _ language: CodeLanguage?) -> [CodeSpan] {
        CodeSyntax.tokens(in: text, language: language).map { CodeSpan($0.kind, String(text[$0.range])) }
    }

    @Test("空文本没有任何片段")
    func emptyText() {
        #expect(CodeSyntax.tokens(in: "", language: .swift).isEmpty)
        #expect(CodeSyntax.tokens(in: "", language: nil).isEmpty)
    }

    @Test("Swift：类型与字符串（含引号）")
    func swiftTypeAndString() {
        #expect(
            spans(#"Text("Ship it!").font(.headline)"#, .swift) == [
                .init(.type, "Text"), .init(.string, #""Ship it!""#),
            ])
    }

    @Test("Swift：关键字按整词匹配")
    func swiftKeywords() {
        #expect(
            spans("guard let x = y else { return nil }", .swift) == [
                .init(.keyword, "guard"), .init(.keyword, "let"), .init(.keyword, "else"), .init(.keyword, "return"),
                .init(.keyword, "nil"),
            ])
        #expect(spans("iffy letter returned", .swift).isEmpty)
        #expect(
            spans("@State var count: Int", .swift) == [
                .init(.type, "State"), .init(.keyword, "var"), .init(.type, "Int"),
            ])
    }

    @Test("数字中的字母不算类型")
    func numbers() {
        #expect(spans("let x = 0xFF + 1E5", .swift) == [.init(.keyword, "let")])
    }

    @Test("转义引号不会提前结束字符串")
    func escapedQuotes() {
        #expect(
            spans(#"let s = "say \"hi\" now" + t"#, .swift) == [
                .init(.keyword, "let"), .init(.string, #""say \"hi\" now""#),
            ])
        #expect(spans(#"x = "a\\" if"#, .python) == [.init(.string, #""a\\""#), .init(.keyword, "if")])
    }

    @Test("未闭合的字符串在行尾结束")
    func unterminatedString() {
        #expect(
            spans("let s = \"open\nlet t = 1", .swift) == [
                .init(.keyword, "let"), .init(.string, "\"open"), .init(.keyword, "let"),
            ])
        #expect(spans("let s = \"open\\", .swift) == [.init(.keyword, "let"), .init(.string, "\"open\\")])
    }

    @Test("注释里的关键字与类型不着色")
    func commentsAreSkipped() {
        #expect(spans("// return nil if Foo\nreturn x", .swift) == [.init(.keyword, "return")])
        #expect(spans("/* if Foo */ if", .javascript) == [.init(.keyword, "if")])
        #expect(spans("/* if Foo", .go).isEmpty)
        #expect(spans("# def Foo\ndef bar(): pass", .python) == [.init(.keyword, "def"), .init(.keyword, "pass")])
        #expect(spans(#"echo "a" # if then"#, .shell) == [.init(.keyword, "echo"), .init(.string, #""a""#)])
        #expect(spans("SELECT 1 -- FROM t", .sql) == [.init(.keyword, "SELECT")])
        #expect(
            spans(#"const u = "http://x" // Foo"#, .javascript) == [
                .init(.keyword, "const"), .init(.string, #""http://x""#),
            ])
    }

    @Test("Shell 中词内的 # 不是注释")
    func shellHashInsideWord() {
        #expect(spans("echo a#b; if", .shell) == [.init(.keyword, "echo"), .init(.keyword, "if")])
    }

    @Test("Swift 与 Rust 的 # 不是注释")
    func hashIsNotCommentInSwiftOrRust() {
        #expect(spans("#if DEBUG", .swift) == [.init(.keyword, "if"), .init(.type, "DEBUG")])
        #expect(spans("#[derive(Debug)]", .rust) == [.init(.type, "Debug")])
    }

    @Test("JSON：键与值是字符串，true/false/null 是关键字")
    func json() {
        #expect(
            spans(#"{"name": "Ada", "ok": true, "x": null, "off": false, "n": 1}"#, .json) == [
                .init(.string, #""name""#), .init(.string, #""Ada""#), .init(.string, #""ok""#),
                .init(.keyword, "true"), .init(.string, #""x""#), .init(.keyword, "null"),
                .init(.string, #""off""#), .init(.keyword, "false"), .init(.string, #""n""#),
            ])
        #expect(spans(#"{"Key": True}"#, .json) == [.init(.string, #""Key""#)])
    }

    @Test("SQL 关键字不区分大小写，且没有类型")
    func sqlCaseInsensitive() {
        #expect(
            spans("select Name from Users WHERE id = 'x'", .sql) == [
                .init(.keyword, "select"), .init(.keyword, "from"), .init(.keyword, "WHERE"), .init(.string, "'x'"),
            ])
    }

    @Test("Python：类名是类型，True/None 是关键字")
    func python() {
        #expect(
            spans("class Loader(Base):\n    x = True or None", .python) == [
                .init(.keyword, "class"), .init(.type, "Loader"), .init(.type, "Base"), .init(.keyword, "True"),
                .init(.keyword, "or"), .init(.keyword, "None"),
            ])
        #expect(spans("name = 'Ada'", .python) == [.init(.string, "'Ada'")])
    }

    @Test("反引号字符串只用于 JS 与 Go")
    func backticks() {
        #expect(spans("msg := `raw` + x", .go) == [.init(.string, "`raw`")])
        #expect(spans("const s = `hi ${a}`", .javascript) == [.init(.keyword, "const"), .init(.string, "`hi ${a}`")])
        #expect(spans("let `default` = 1", .swift) == [.init(.keyword, "let"), .init(.keyword, "default")])
    }

    @Test("单引号紧跟在词后是撇号或生命周期，不是字符串")
    func apostrophes() {
        #expect(spans("don't stop", nil).isEmpty)
        #expect(spans("fn f<'a>(x: &'a str)", .rust) == [.init(.keyword, "fn")])
        #expect(spans("echo 'hi'", .shell) == [.init(.keyword, "echo"), .init(.string, "'hi'")])
    }

    @Test("Rust：关键字与类型")
    func rust() {
        #expect(
            spans("let mut v: Vec<u8> = Vec::new();", .rust) == [
                .init(.keyword, "let"), .init(.keyword, "mut"), .init(.type, "Vec"), .init(.type, "Vec"),
            ])
    }

    @Test("Shell、CSS 没有类型")
    func noTypesInShellOrCSS() {
        #expect(
            spans(#"export PATH="$HOME/bin""#, .shell) == [.init(.keyword, "export"), .init(.string, #""$HOME/bin""#)])
        #expect(
            spans(".card { color: red !important; content: \"A\"; }", .css) == [
                .init(.keyword, "important"), .init(.string, "\"A\""),
            ])
        #expect(spans("Foo { font-family: Menlo; }", .css).isEmpty)
    }

    @Test("HTML：标签名是关键字，只有双引号是字符串")
    func html() {
        #expect(
            spans(#"<div class="card">Don't Stop</div>"#, .html) == [
                .init(.keyword, "div"), .init(.string, #""card""#), .init(.keyword, "div"),
            ])
    }

    @Test("未知语言使用通用关键字集，并识别类型")
    func genericLanguage() {
        #expect(
            spans("if x { return Foo(nil) }", nil) == [
                .init(.keyword, "if"), .init(.keyword, "return"), .init(.type, "Foo"), .init(.keyword, "nil"),
            ])
        #expect(spans("# comment if\nint main", nil) == [])
    }

    @Test("CJK 与 emoji 不影响片段范围")
    func unicode() {
        #expect(
            spans("let \u{540D}\u{5B57} = \"\u{4F60}\u{597D}\"; let e = \"\u{1F44D}\"; Foo", .swift) == [
                .init(.keyword, "let"), .init(.string, "\"\u{4F60}\u{597D}\""), .init(.keyword, "let"),
                .init(.string, "\"\u{1F44D}\""), .init(.type, "Foo"),
            ])
    }

    @Test("片段有序、不重叠、非空且落在字符边界上", arguments: CodeSyntaxTests.snippets)
    func tokensAreWellFormed(_ snippet: String) {
        for language in CodeLanguage.allCases.map(Optional.some) + [nil] {
            let tokens = CodeSyntax.tokens(in: snippet, language: language)
            let boundaries = Set(snippet.indices).union([snippet.endIndex])
            #expect(zip(tokens, tokens.dropFirst()).allSatisfy { $0.range.upperBound <= $1.range.lowerBound })
            for token in tokens {
                #expect(!token.range.isEmpty)
                #expect(boundaries.contains(token.range.lowerBound) && boundaries.contains(token.range.upperBound))
            }
        }
    }

    static let snippets: [String] =
        CodeLanguageSamples.all.map(\.text) + [
            "\"", "'", "`", "/", "/*", "#", "-", "--", "\\", "a\"b'c`d", "\"\\\"",
            "\u{1F468}\u{200D}\u{1F469} \"\u{0301}\"",
        ]

    @Test("2 MB 输入只扫描开头，很快返回")
    func hugeInputIsBounded() {
        let text = String(repeating: "let value = \"x\" // Foo\n", count: 90_000)
        let clock = ContinuousClock()
        var tokens: [CodeToken] = []
        let elapsed = clock.measure { tokens = CodeSyntax.tokens(in: text, language: .swift) }
        #expect(elapsed < .seconds(1))
        #expect(!tokens.isEmpty)
        let limit = text.index(text.startIndex, offsetBy: CodeSyntax.scanLimit)
        #expect(tokens.allSatisfy { $0.range.upperBound <= limit })
    }
}
