import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TranslationTypesetter / TranslationFitter 排版与放不下的三步")
struct TranslationTypesettingTests {
    private let style = TranslationTypesetter.Style(fontSize: 13, isBold: false, language: "zh-Hans")
    private let hans = "\u{50A8}\u{5B58}\u{7A7A}\u{95F4}"

    private func request(
        _ text: String, multiLine: Bool = false, width: CGFloat, height: CGFloat = 16, extraWidth: CGFloat = 0,
        extraHeight: CGFloat = 0
    ) -> TranslationFitter.Request {
        TranslationFitter.Request(
            text: text, style: style, isMultiLine: multiLine, width: width, height: height, lineHeight: 16, pitch: 19,
            extraWidth: extraWidth, extraHeight: extraHeight)
    }

    @Test("宽度不含行尾空白；折行去掉首尾空白，硬换行处断开；空串没有行")
    func measureAndBreak() {
        #expect(
            TranslationTypesetter.width(of: "Save ", style: style)
                == TranslationTypesetter.width(of: "Save", style: style))
        let lines = TranslationTypesetter.breakLines("Optimize storage\nnow please", style: style, width: 1000)
        #expect(lines == ["Optimize storage", "now please"])
        #expect(TranslationTypesetter.breakLines("", style: style, width: 100).isEmpty)
        let narrow = TranslationTypesetter.breakLines(String(repeating: hans, count: 5), style: style, width: 60)
        #expect(narrow.count >= 4)
        #expect(narrow.allSatisfy { TranslationTypesetter.width(of: $0, style: style) <= 60.5 })
    }

    @Test("截断：放得下原样返回；放不下时以省略号结尾且不超宽")
    func truncation() {
        #expect(TranslationTypesetter.truncated("Save", style: style, width: 100) == "Save")
        let cut = TranslationTypesetter.truncated("Papierkorb entleeren", style: style, width: 60)
        #expect(cut.hasSuffix(TranslationTypesetter.ellipsis) && cut.count > 1)
        #expect(TranslationTypesetter.width(of: cut, style: style) <= 60)
    }

    @Test("字形边距与视觉中线：CJK 取字面中线，拉丁取大写高一半")
    func bearingsAndCenter() {
        #expect(TranslationTypesetter.bearings(of: nil, style: style) == (0, 0))
        #expect(TranslationTypesetter.bearings(of: " ", style: style) == (0, 0))
        let bearings = TranslationTypesetter.bearings(of: "O", style: style)
        #expect(bearings.left > 0 && bearings.left < 2 && bearings.right > 0 && bearings.right < 2)
        #expect(TranslationTypesetter.centerHeight(of: hans, style: style) > 4)
        #expect(abs(TranslationTypesetter.centerHeight(of: "Save", style: style) - 13 * 0.35) < 0.5)
    }

    @Test("在给定框内自动换行：三种对齐")
    func wrap() {
        let frame = CGRect(x: 10, y: 20, width: 80, height: 60)
        let leading = TranslationTypesetter.wrap("Optimize storage now", style: style, in: frame, alignment: .leading)
        let center = TranslationTypesetter.wrap("Optimize storage now", style: style, in: frame, alignment: .center)
        let trailing = TranslationTypesetter.wrap("Optimize storage now", style: style, in: frame, alignment: .trailing)
        #expect(leading.count == 2 && leading[0].origin.x == 10)
        #expect(leading[1].origin.y > leading[0].origin.y)
        #expect(center[0].origin.x > 10 && trailing[0].origin.x > center[0].origin.x)
    }

    @Test("放得下：原字号、原宽度")
    func fits() {
        let result = TranslationFitter.fit(request("Save", width: 100))
        #expect(result == TranslationFitter.Result(style: style, lines: ["Save"], pitch: 19))
    }

    @Test("① 扩展：只取需要的宽度，不缩字")
    func extend() {
        let needed = TranslationTypesetter.width(of: "Optimize storage", style: style)
        let result = TranslationFitter.fit(request("Optimize storage", width: 40, extraWidth: 200))
        #expect(result.style.fontSize == 13)
        #expect(result.lines == ["Optimize storage"])
        #expect(TranslationTypesetter.width(of: result.lines[0], style: style) == needed)
    }

    @Test("② 缩字：0.5 pt 步长，下限 75%；③ 省略号")
    func shrinkThenEllipsis() {
        let width = TranslationTypesetter.width(of: "Optimize storage", style: style)
        let shrunk = TranslationFitter.fit(request("Optimize storage", width: width * 0.9))
        #expect(
            shrunk.style.fontSize < 13 && shrunk.style.fontSize >= 9.75
                && !shrunk.lines[0].hasSuffix(TranslationTypesetter.ellipsis))
        let cut = TranslationFitter.fit(request("Optimize storage", width: width * 0.5))
        #expect(cut.style.fontSize == 10 && cut.lines[0].hasSuffix(TranslationTypesetter.ellipsis))
        #expect(TranslationFitter.sizes(from: 13) == [13, 12.5, 12, 11.5, 11, 10.5, 10])
    }

    @Test("单行块：下方有空白时一行缩到 75% 仍放不下才折行；多行块按行距折行，放不下时末行省略")
    func wrapping() {
        let long = String(repeating: "Optimize storage ", count: 4)
        let wrapped = TranslationFitter.fit(request(long, width: 200, extraHeight: 60))
        #expect(wrapped.lines.count > 1 && wrapped.style.fontSize == 13)
        #expect(!wrapped.lines.contains { $0.hasSuffix(TranslationTypesetter.ellipsis) })
        let paragraph = TranslationFitter.fit(request(long, multiLine: true, width: 150, height: 35))
        #expect(paragraph.lines.count == 2)
        #expect(paragraph.lines[1].hasSuffix(TranslationTypesetter.ellipsis))
        let roomy = TranslationFitter.fit(request(long, multiLine: true, width: 200, height: 35, extraHeight: 100))
        #expect(roomy.lines.count > 2 && roomy.pitch == 19)
        #expect(!roomy.lines.contains { $0.hasSuffix(TranslationTypesetter.ellipsis) })
    }
}
