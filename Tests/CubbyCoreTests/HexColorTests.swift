import Testing
@testable import CubbyCore

@Suite("HexColor 解析")
struct HexColorTests {
    @Test("3 位简写按 4 位分量展开")
    func parsesThreeDigits() {
        #expect(HexColor.parse("#F80") == RGBAColor(red: 1, green: 8.0 / 15, blue: 0, alpha: 1))
    }

    @Test("4 位简写带透明度")
    func parsesFourDigits() {
        #expect(HexColor.parse("#F80C") == RGBAColor(red: 1, green: 8.0 / 15, blue: 0, alpha: 12.0 / 15))
    }

    @Test("6 位完整格式")
    func parsesSixDigits() {
        #expect(HexColor.parse("#FF8800") == RGBAColor(red: 1, green: 136.0 / 255, blue: 0, alpha: 1))
    }

    @Test("8 位完整格式带透明度")
    func parsesEightDigits() {
        #expect(HexColor.parse("#FF880080") == RGBAColor(red: 1, green: 136.0 / 255, blue: 0, alpha: 128.0 / 255))
    }

    @Test("大小写不敏感")
    func isCaseInsensitive() {
        #expect(HexColor.parse("#ff8800") == HexColor.parse("#FF8800"))
        #expect(HexColor.parse("#aBc") == HexColor.parse("#AABBCC"))
    }

    @Test("黑白边界值")
    func parsesExtremes() {
        #expect(HexColor.parse("#000") == RGBAColor(red: 0, green: 0, blue: 0))
        #expect(HexColor.parse("#FFFFFFFF") == RGBAColor(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(HexColor.parse("#00000000") == RGBAColor(red: 0, green: 0, blue: 0, alpha: 0))
    }

    @Test("首尾空白与换行会被忽略")
    func trimsWhitespace() {
        #expect(HexColor.parse("  #FFF\n") == RGBAColor(red: 1, green: 1, blue: 1))
    }

    @Test("缺少 # 前缀返回 nil", arguments: ["FFF", "FF8800", "0xFF8800", ""])
    func rejectsMissingHash(_ input: String) {
        #expect(HexColor.parse(input) == nil)
    }

    @Test("长度不合法返回 nil", arguments: ["#", "#F", "#FF", "#FFFFF", "#FFFFFFF", "#FFFFFFFFF"])
    func rejectsInvalidLength(_ input: String) {
        #expect(HexColor.parse(input) == nil)
    }

    @Test(
        "包含非法字符返回 nil",
        arguments: ["#GGG", "#12345G", "##FFF", "#FF 88 00", "#-FF", "#+FFF", "#ＦＦＦ", "#FF\u{301}F"]
    )
    func rejectsInvalidCharacters(_ input: String) {
        #expect(HexColor.parse(input) == nil)
    }
}

@Suite("ContentClassifier 类型判断")
struct ContentClassifierTests {
    @Test("HEX 颜色识别为 color", arguments: ["#FF8800", "#abc", "  #FF880080 \n"])
    func classifiesColor(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .color)
    }

    @Test(
        "http / https 链接识别为 link",
        arguments: [
            "https://example.com",
            "http://example.com/path?q=1#frag",
            "HTTPS://Example.COM",
            "  https://example.com/a\n",
            "https://user@example.com:8080/x",
        ]
    )
    func classifiesLink(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .link)
    }

    @Test(
        "带空白的文本不是链接",
        arguments: ["https://example.com/a b", "访问 https://example.com", "https://example.com\nhttps://b.com"]
    )
    func textWithWhitespaceIsNotLink(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .text)
    }

    @Test("缺少 host 不是链接", arguments: ["https://", "http:///path", "https:example.com"])
    func missingHostIsNotLink(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .text)
    }

    @Test(
        "其他 scheme 不是链接",
        arguments: ["ftp://example.com", "file:///tmp/a.txt", "mailto:a@example.com", "javascript:alert(1)"]
    )
    func otherSchemesAreText(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .text)
    }

    @Test("普通文本与空文本", arguments: ["hello world", "example.com", "", "   \n", "你好，世界"])
    func plainText(_ input: String) {
        #expect(ContentClassifier.kind(forText: input) == .text)
    }

    @Test("isLink 不做裁剪，前后有空白即判定为否")
    func isLinkDoesNotTrim() {
        #expect(ContentClassifier.isLink("https://example.com"))
        #expect(!ContentClassifier.isLink(" https://example.com"))
        #expect(!ContentClassifier.isLink(""))
    }
}

@Suite("ClipKind 元数据")
struct ClipKindTests {
    @Test("每种类型都有非空的显示名与图标")
    func everyKindHasMetadata() {
        for kind in ClipKind.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.symbolName.isEmpty)
        }
        #expect(Set(ClipKind.allCases.map(\.displayName)).count == ClipKind.allCases.count)
    }
}
