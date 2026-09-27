import Foundation
import Testing
@testable import CubbyCore

/// 带标签的文本样本，便于在参数化测试中辨认
struct TextSample: Sendable, CustomTestStringConvertible {
    let label: String
    let text: String

    init(_ label: String, _ text: String) {
        self.label = label
        self.text = text
    }

    var testDescription: String { label }
}

@Suite("TextHeuristics 代码识别")
struct TextHeuristicsTests {
    @Test(
        "多行代码识别为代码",
        arguments: [
            TextSample(
                "Swift",
                """
                struct Point {
                    let x: Int
                    let y: Int
                }
                """),
            TextSample(
                "Swift 函数",
                """
                func greet(_ name: String) -> String {
                    return "Hello, \\(name)"
                }
                """),
            TextSample(
                "Python",
                """
                def greet(name):
                    message = f"Hello {name}"
                    return message
                """),
            TextSample(
                "Python import",
                """
                import os
                import sys
                print(os.getcwd())
                """),
            TextSample(
                "JavaScript",
                """
                const add = (a, b) => a + b;
                console.log(add(1, 2));
                """),
            TextSample(
                "HTML",
                """
                <div class="card">
                  <p>Hello</p>
                </div>
                """),
            TextSample(
                "C",
                """
                #include <stdio.h>
                int main(void) {
                  printf("hi");
                }
                """),
            TextSample(
                "SQL",
                """
                SELECT id, name
                FROM users
                WHERE age > 18;
                """),
            TextSample("Tab 缩进", "if ok:\n\tpass\n\tpass"),
            TextSample(
                "Python 循环（缩进行带赋值或调用）",
                """
                for item in items:
                    total += item
                    print(total)
                """),
            TextSample(
                "缩进的配置赋值",
                """
                [server]
                    host = "localhost"
                    port = 8080
                """),
            TextSample(
                "缩进的 Shell 块（不超过 3 个词的 ASCII 短语句）",
                """
                if [ -f "$FILE" ]; then
                    echo "found"
                    exit 0
                fi
                """),
            TextSample("CRLF 换行", "let a = 1\r\nlet b = 2"),
        ])
    func recognizesCode(_ sample: TextSample) {
        #expect(TextHeuristics.looksLikeCode(sample.text))
    }

    @Test(
        "散文不识别为代码",
        arguments: [
            TextSample(
                "中文散文",
                """
                今天天气很好，我们去公园散步。
                湖面上有几只白鹅在游泳，孩子们在岸边奔跑。
                傍晚时分，夕阳把天空染成了橘红色。
                """),
            TextSample(
                "中文带全角括号",
                """
                会议安排在下周三下午（具体时间待定）
                请大家提前准备好材料。
                """),
            TextSample(
                "英文散文",
                """
                The quick brown fox jumps over the lazy dog.
                It was a sunny day, and everyone was happy.
                We walked to the park together after lunch.
                """),
            TextSample(
                "英文邮件",
                """
                Hi team,
                Thanks for the update on the release.
                I will review the notes this afternoon.
                Best regards,
                Alex
                """),
            TextSample(
                "中英混排列表",
                """
                待办事项：
                1. 买牛奶
                2. Call the plumber
                3. 回复邮件
                """),
            TextSample("口语中的 let", "Hi,\nplease let me know if you need anything"),
            TextSample("缩进的 Markdown 列表", "Notes:\n    - first item\n    - second item\n    1. numbered"),
            // 反例（审计 P2-2）：只有缩进、没有任何代码符号的散文此前被判为代码
            TextSample("前导空白与制表符缩进的中文段落", "\n\n\t   前面有很多空白和换行的文本\n\n\n第二段落\n\t制表符缩进"),
            TextSample(
                "缩进的英文引文",
                """
                As the saying goes
                    the only way to do great work
                    is to love what you do
                """),
            TextSample(
                "首行缩进的中文段落",
                """
                    春天来了，院子里的桃花开了。
                    孩子们在树下追逐打闹，笑声传得很远。
                """),
        ])
    func rejectsProse(_ sample: TextSample) {
        #expect(!TextHeuristics.looksLikeCode(sample.text))
    }

    @Test(
        "单行内容（即使是代码）不识别为代码",
        arguments: [
            "let x = 1;",
            "const f = () => {};",
            "print(\"hello\")",
            "SELECT * FROM t;",
            "let x = 1;\n\n   \n",
            "\n\nfunc a() {}\n\n",
        ])
    func singleLineIsNotCode(_ text: String) {
        #expect(!TextHeuristics.looksLikeCode(text))
    }

    @Test("空串与纯空白不识别为代码", arguments: ["", " ", "\n\n", "   \n\t\n  "])
    func blankIsNotCode(_ text: String) {
        #expect(!TextHeuristics.looksLikeCode(text))
    }

    @Test("代码行占比恰好一半时识别为代码，低于一半时不识别")
    func ratioBoundary() {
        #expect(TextHeuristics.looksLikeCode("plain words here\nfoo();"))
        #expect(!TextHeuristics.looksLikeCode("plain words\nmore words\nfoo();"))
    }

    @Test("只检查开头 2000 字符：代码出现在长散文之后不识别")
    func onlySamplesHead() {
        let prose = String(repeating: "这是一段普通的中文说明文字，没有任何代码特征\n", count: 100)
        let code = String(repeating: "let value = compute();\n", count: 200)
        #expect(!TextHeuristics.looksLikeCode(prose + code))
        #expect(TextHeuristics.looksLikeCode(code + prose))
    }

    @Test("MB 级文本也能快速完成判断")
    func hugeTextCompletes() {
        let huge = String(repeating: "func f() {}\n", count: 200_000)
        #expect(TextHeuristics.looksLikeCode(huge))
    }
}
