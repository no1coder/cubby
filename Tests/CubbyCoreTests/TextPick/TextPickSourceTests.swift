import Foundation
import Testing
@testable import CubbyCore

/// 可拆的条目（docs/TEXT-PICK-DESIGN.md P4）：文本（含富文本、代码）与已识别出文字的图片；
/// 链接、颜色、文件与没有文字的图片不支持
@Suite("TextPickSource 可拆的条目")
struct TextPickSourceTests {
    @Test("文本、代码、富文本都按纯文本拆")
    func textItems() {
        #expect(TextPickSource(item: Fixtures.text("Hello world")) == .text("Hello world"))
        let code = "let x = 1\nprint(x)"
        #expect(TextPickSource(item: Fixtures.text(code)) == .text(code))
        let rich = Fixtures.text("Bold title", formatsName: "rich.formats")
        #expect(TextPickSource(item: rich) == .text("Bold title"))
        #expect(TextPickSource(item: Fixtures.text("Hello world")).text == "Hello world")
    }

    @Test("链接与颜色不支持")
    func linksAndColors() {
        let link = Fixtures.text("https://github.com/no1coder/cubby")
        #expect(link.kind == .link)
        #expect(TextPickSource(item: link) == .unsupported)
        let color = Fixtures.text("#5F2EEA")
        #expect(color.kind == .color)
        #expect(TextPickSource(item: color) == .unsupported)
        #expect(TextPickSource(item: color).text == nil)
    }

    @Test("只有空白的文本不支持")
    func blankText() {
        #expect(TextPickSource(item: Fixtures.text(" \n\t")) == .unsupported)
        #expect(TextPickSource(item: Fixtures.text("\u{200B}\u{200D}")) == .unsupported)
    }

    @Test("图片：有识别文字时拆识别文字，否则不支持")
    func images() {
        let image = Fixtures.image(name: "a.png")
        #expect(TextPickSource(item: image) == .unsupported)
        #expect(TextPickSource(item: image.withRecognizedText("")) == .unsupported)
        #expect(TextPickSource(item: image.withRecognizedText("  \n")) == .unsupported)
        #expect(TextPickSource(item: image.withRecognizedText("Software Update")) == .text("Software Update"))
    }

    @Test("文件不支持")
    func files() {
        #expect(TextPickSource(item: Fixtures.files(["/tmp/a.txt"])) == .unsupported)
    }
}
