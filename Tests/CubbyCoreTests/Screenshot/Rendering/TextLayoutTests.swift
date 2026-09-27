import AppKit
import CoreGraphics
import CoreText
import Testing
@testable import CubbyCore

@Suite("TextLayout CoreText 排版")
struct TextLayoutTests {
    @Test("字体：系统字体 semibold，字号按参数")
    func font() {
        let font = TextLayout.font(size: 20)
        #expect(CTFontGetSize(font) == 20)
        let expected = NSFont.systemFont(ofSize: 20, weight: .semibold) as CTFont
        #expect(CTFontCopyPostScriptName(font) as String == CTFontCopyPostScriptName(expected) as String)
        let traits = CTFontCopyTraits(font) as NSDictionary
        let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        #expect(abs(weight - Double(NSFont.Weight.semibold.rawValue)) < 0.05)
    }

    @Test("空串尺寸为零")
    func emptyText() {
        #expect(TextLayout.size(of: "", fontSize: 20, maxWidth: 200) == .zero)
    }

    @Test("单行：宽度不超过 maxWidth，高度约一行")
    func singleLine() {
        let size = TextLayout.size(of: "Hello", fontSize: 20, maxWidth: 500)
        #expect(size.width > 20 && size.width < 500)
        #expect(size.height >= 20 && size.height < 40)
    }

    @Test("maxWidth 变小时换行，高度增加且宽度不超限")
    func wrapsWhenNarrow() {
        let text = "The quick brown fox jumps over the lazy dog"
        let wide = TextLayout.size(of: text, fontSize: 20, maxWidth: 2000)
        let narrow = TextLayout.size(of: text, fontSize: 20, maxWidth: 120)
        #expect(narrow.height > wide.height * 2)
        #expect(narrow.width <= 120)
    }

    @Test("显式换行增加行数；末尾换行也占一行")
    func newlines() {
        let one = TextLayout.size(of: "A", fontSize: 14, maxWidth: 300)
        let two = TextLayout.size(of: "A\nB", fontSize: 14, maxWidth: 300)
        let trailing = TextLayout.size(of: "A\n", fontSize: 14, maxWidth: 300)
        #expect(two.height > one.height * 1.8)
        #expect(trailing.height > one.height * 1.8)
    }

    @Test("中英混排与 emoji 不崩溃且有尺寸")
    func mixedScripts() {
        let size = TextLayout.size(of: "Hello \u{4F60}\u{597D} \u{1F44B}", fontSize: 20, maxWidth: 300)
        #expect(size.width > 0 && size.height > 0)
    }

    @Test("maxWidth 非正或无穷时仍能排版")
    func degenerateWidths() {
        #expect(TextLayout.size(of: "Hi", fontSize: 14, maxWidth: 0).height > 0)
        #expect(TextLayout.size(of: "Hi", fontSize: 14, maxWidth: .infinity).width > 0)
    }

    @Test("draw：在 y 向下的 context 中文字落在 origin 起的排版框内")
    func drawsInsideBox() {
        let canvas = TestCanvas(width: 200, height: 100)
        let context = canvas.context
        // 把位图 context 翻成左上原点、y 向下
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        let origin = CGPoint(x: 20, y: 30)
        let black = RGBAColor(red: 0, green: 0, blue: 0)
        TextLayout.draw("Hg", at: origin, fontSize: 28, maxWidth: 150, color: black, in: context)

        let size = TextLayout.size(of: "Hg", fontSize: 28, maxWidth: 150)
        let box = CGRect(origin: origin, size: size)
        var inside = 0
        var outside = 0
        for y in 0..<100 {
            for x in 0..<200 where !canvas.pixel(x: x, y: y).isWhite {
                if box.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)) { inside += 1 } else { outside += 1 }
            }
        }
        #expect(inside > 50)
        #expect(outside == 0)
        // 文字位于框的上部而不是被翻到下方：框顶部 1/3 有墨迹
        let topBand = (Int(origin.y)..<Int(origin.y + size.height / 3)).contains { y in
            canvas.countPixels(inRow: y) { !$0.isWhite } > 0
        }
        #expect(topBand)
    }

    @Test("draw：空串不绘制")
    func drawEmpty() {
        let canvas = TestCanvas(width: 20, height: 20)
        TextLayout.draw(
            "", at: .zero, fontSize: 14, maxWidth: 20, color: RGBAColor(red: 0, green: 0, blue: 0), in: canvas.context)
        #expect(canvas.countPixels { !$0.isWhite } == 0)
    }
}

@Suite("TextLayout 与 NSTextView 排版一致（R8）", .serializedPasteboardAccess, .timeLimit(.minutes(1)))
@MainActor
struct TextLayoutParityTests {
    /// 用与覆盖层编辑器相同的配置测量：NSTextView（TextKit 2）、lineFragmentPadding = 0、同字体、同宽度
    private func textViewSize(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: maxWidth, height: 1000))
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        textView.string = text
        guard let layoutManager = textView.textLayoutManager else {
            Issue.record("NSTextView is expected to use TextKit 2")
            return .zero
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return layoutManager.usageBoundsForTextContainer.size
    }

    @Test(
        "尺寸与 NSTextView（TextKit 2）相差 ≤ 1 pt",
        arguments: [
            ("Hello", 20.0, 400.0),
            ("Hello \u{4F60}\u{597D}", 14, 400),
            ("The quick brown fox jumps over the lazy dog", 20, 150),
            ("Line one\nLine two\nLine three", 28, 600),
            ("Trailing newline\n", 20, 600),
            ("abc\n\n", 20, 600),
            ("\n", 14, 600),
            ("Hi \u{1F44B} \u{0E2A}\u{0E27}\u{0E31}\u{0E2A}\u{0E14}\u{0E35}", 20, 600),
            ("a b c d e f g h i j k l m n o p", 14, 50),
            ("Hello \u{4F60}\u{597D}\nabc\n\u{4F60}\u{597D}", 20, 400),
            (
                "\u{4E2D}\u{6587}\u{6362}\u{884C}\u{6D4B}\u{8BD5}\u{4E2D}\u{6587}\u{6362}\u{884C}\u{6D4B}\u{8BD5}", 20,
                90
            ),
        ]
    )
    func matchesTextKit(text: String, fontSize: Double, maxWidth: Double) {
        let core = TextLayout.size(of: text, fontSize: fontSize, maxWidth: maxWidth)
        let kit = textViewSize(text, fontSize: fontSize, maxWidth: maxWidth)
        #expect(abs(core.width - kit.width.rounded(.up)) <= 1, "width core=\(core) kit=\(kit)")
        #expect(abs(core.height - kit.height.rounded(.up)) <= 1, "height core=\(core) kit=\(kit)")
    }

    @Test("行高与 TextKit 2 行框一致", arguments: [11.0, 14, 20, 28, 40])
    func lineHeightMatchesTextKit(fontSize: Double) {
        let one = textViewSize("Ag", fontSize: fontSize, maxWidth: 400)
        let two = textViewSize("Ag\nAg", fontSize: fontSize, maxWidth: 400)
        #expect(TextLayout.lineHeight(fontSize: fontSize) == one.height)
        #expect(two.height == one.height * 2)
    }
}
