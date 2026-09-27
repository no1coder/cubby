import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TranslationCandidates 哪些块需要翻译")
struct TranslationCandidatesTests {
    private func block(_ text: String, id: Int = 0, frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 20))
        -> TextBlock
    {
        TextBlock(id: id, lines: [RecognizedLine(text: text, frame: frame)], alignment: .leading, text: text)
    }

    private func kept(_ text: String, target: String = "zh-Hans", hidden: [CGRect] = []) -> Bool {
        !TranslationCandidates.translatable([block(text)], target: target, hidden: hidden).isEmpty
    }

    @Test("普通界面文字需要翻译，保持原顺序")
    func keepsOrdinaryText() {
        let blocks = [block("Storage", id: 0), block("Optimize Storage", id: 1)]
        #expect(TranslationCandidates.translatable(blocks, target: "zh-Hans", hidden: []) == blocks)
    }

    @Test("与遮挡区域相交 ≥ 20% 块面积时跳过；更小的相交保留")
    func hiddenArea() {
        #expect(!kept("API key", hidden: [CGRect(x: 0, y: 0, width: 20, height: 20)]))
        #expect(kept("API key", hidden: [CGRect(x: 0, y: 0, width: 19, height: 20)]))
        #expect(
            !kept(
                "API key",
                hidden: [CGRect(x: 0, y: 0, width: 10, height: 20), CGRect(x: 50, y: 0, width: 10, height: 20)]))
        #expect(kept("API key", hidden: [CGRect(x: 500, y: 500, width: 100, height: 100)]))
    }

    @Test("疑似密钥跳过")
    func secrets() {
        #expect(!kept("API key: sk-live-8f3a9c21e7d4b5a6c7d8e9f0"))
        #expect(!kept("ghp_abcdefghijklmnopqrstuvwxyz0123456789"))
    }

    @Test("不含字母（数字、符号、价格、时间）跳过")
    func noLetters() {
        for text in ["1,284", "21:30", "$19.99", "--", "100%", "2026-09-27", "\u{00A5}128"] {
            #expect(!kept(text), "\(text)")
        }
    }

    @Test("数字带短单位（≤ 3 个拉丁字母）跳过")
    func numberWithUnit() {
        for text in ["12.4 GB", "48.1 GB", "3 MB", "5 min", "v2.3.1", "120 px"] {
            #expect(!kept(text), "\(text)")
        }
        #expect(kept("Yesterday at 21:30"))
        #expect(kept("3 items"))
        #expect(kept("\u{4E09}\u{5929}"), "CJK letters are not units")
    }

    @Test("URL、邮箱、路径、包名整块匹配时跳过")
    func urlsAndPaths() {
        for text in [
            "https://github.com/no1coder/cubby", "www.apple.com", "github.com/no1coder", "com.example.app",
            "hello@example.com", "~/Library/Caches/com.example.app", "/usr/local/bin", "./build.sh", "C:\\Users\\me",
        ] {
            #expect(!kept(text), "\(text)")
        }
        #expect(kept("Visit www.apple.com for details"))
        #expect(kept("Use e.g. a shorter name"))
    }

    @Test("命令行跳过：提示符开头，或常见命令开头且全小写、无句末标点")
    func commandLines() {
        for text in [
            "$ make install", "% ls -la", "brew install cubby", "git commit -m", "npm run build", "swift test",
        ] {
            #expect(!kept(text), "\(text)")
        }
        #expect(kept("git is a version control system."))
        #expect(kept("Make sure the app is running"))
    }

    @Test("代码跳过：多个代码符号，或含下划线 / 括号 / 点号调用的单个标识符")
    func code() {
        for text in [
            "let x = foo();", "if (a && b) { run() }", "snake_case_name", "viewDidLoad()", "NSApp.terminate(nil)",
            "items.map { $0.id }",
        ] {
            #expect(!kept(text), "\(text)")
        }
        #expect(kept("iCloud Drive"))
        #expect(kept("Storage (optional)"))
        #expect(kept("Save; then quit"))
    }

    @Test("已是目标语言（置信度 ≥ 0.8）跳过；zh-Hans / zh-Hant 按字形区分")
    func alreadyTarget() {
        let hans =
            "\u{4F18}\u{5316}\u{50A8}\u{5B58}\u{7A7A}\u{95F4}\u{53EF}\u{81EA}\u{52A8}\u{79FB}\u{9664}\u{4E0D}\u{518D}\u{9700}\u{8981}\u{7684}\u{9879}\u{76EE}"
        #expect(!kept(hans, target: "zh-Hans"))
        #expect(kept(hans, target: "en"))
        let english = "Optimize storage to free up space automatically"
        #expect(!kept(english, target: "en"))
        #expect(!kept(english, target: "en-US"))
        #expect(kept(english, target: "zh-Hans"))
    }

    @Test("繁体目标：简体文本仍需翻译；zh 无文字标签时按简体处理")
    func chineseScripts() {
        let hans =
            "\u{4F18}\u{5316}\u{50A8}\u{5B58}\u{7A7A}\u{95F4}\u{53EF}\u{81EA}\u{52A8}\u{79FB}\u{9664}\u{4E0D}\u{518D}\u{9700}\u{8981}\u{7684}\u{9879}\u{76EE}"
        let hant =
            "\u{6700}\u{4F73}\u{5316}\u{5132}\u{5B58}\u{7A7A}\u{9593}\u{53EF}\u{81EA}\u{52D5}\u{79FB}\u{9664}\u{4E0D}\u{518D}\u{9700}\u{8981}\u{7684}\u{9805}\u{76EE}"
        #expect(kept(hans, target: "zh-Hant"))
        #expect(!kept(hant, target: "zh-Hant"))
        #expect(!kept(hant, target: "zh-TW"))
        #expect(!kept(hans, target: "zh"))
    }

    @Test("少于 4 个字母的块不做语言判断")
    func shortBlocksGoToEngine() {
        #expect(kept("OK", target: "en"))
        #expect(kept("\u{8BBE}\u{7F6E}", target: "zh-Hans"))
    }
}
