import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TranslationPainter 绘制（像素断言）")
struct TranslationPainterTests {
    private let red = PixelColor(red: 1, green: 0, blue: 0)

    private func environment(origin: CGPoint = .zero, scale: CGFloat, size: CGSize) -> RenderEnvironment {
        RenderEnvironment(origin: origin, scale: scale, targetPixelSize: size, pixelatedFrame: nil, frameOrigin: .zero)
    }

    private func block(
        erase: [CGRect], backdrop: TranslationBackdrop, text: String = "", lines: [TranslatedLine] = [],
        textFrame: CGRect = .zero, plate: TranslationPlateImage? = nil
    ) -> TranslatedBlock {
        TranslatedBlock(
            blockID: 0, eraseFrame: erase.reduce(textFrame) { $0.union($1) }, backdrop: backdrop, text: text,
            textFrame: textFrame, style: .init(fontSize: 13, isBold: false, language: "zh-Hans"),
            textColor: .black, alignment: .leading, eraseRects: erase, plateImage: plate, lines: lines)
    }

    /// 非透明像素的外框（像素，左上原点）
    private func inkBounds(_ canvas: TestCanvas) -> CGRect {
        var bounds = CGRect.null
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas.pixel(x: x, y: y).alpha > 0 {
                bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return bounds
    }

    @Test("纯色：填色恰好盖住对齐像素后的抹除矩形，不多不少，不抗锯齿")
    func solidFillIsExact() {
        for scale in [CGFloat(1), 2] {
            let canvas = TestCanvas(width: Int(100 * scale), height: Int(60 * scale), fill: nil)
            let rect = CGRect(x: 10.3, y: 20.2, width: 30.1, height: 10.4)
            TranslationPainter.draw(
                [block(erase: [rect], backdrop: .solid(red))], in: canvas.context,
                environment: environment(scale: scale, size: CGSize(width: canvas.width, height: canvas.height)))
            let expected = TranslationPainter.snapped(
                CGRect(
                    x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
            #expect(inkBounds(canvas) == expected)
            #expect(canvas.countPixels { $0.alpha > 0 && $0 != Pixel(255, 0, 0) } == 0)
        }
    }

    @Test("文字像素只落在 textFrame 内；1x 与 2x 的结果几何一致")
    func textStaysInsideTextFrame() {
        let text = "\u{50A8}\u{5B58}\u{7A7A}\u{95F4} Storage"
        let style = TranslationTypesetter.Style(fontSize: 13, isBold: false, language: "zh-Hans")
        let lines = [TranslatedLine(text: text, origin: CGPoint(x: 12, y: 30))]
        let textFrame = TranslationPlacer.textBounds(lines, style: style)
        var bounds: [CGFloat: CGRect] = [:]
        for scale in [CGFloat(1), 2] {
            let canvas = TestCanvas(width: Int(200 * scale), height: Int(60 * scale), fill: nil)
            TranslationPainter.draw(
                [block(erase: [], backdrop: .solid(red), text: text, lines: lines, textFrame: textFrame)],
                in: canvas.context,
                environment: environment(scale: scale, size: CGSize(width: canvas.width, height: canvas.height)))
            let ink = inkBounds(canvas)
            let frame = CGRect(
                x: textFrame.minX * scale, y: textFrame.minY * scale, width: textFrame.width * scale,
                height: textFrame.height * scale
            ).insetBy(dx: -1, dy: -1)
            #expect(!ink.isNull && frame.contains(ink), "scale \(scale): \(ink) not in \(frame)")
            bounds[scale] = ink
        }
        let one = bounds[1] ?? .null
        let two = bounds[2] ?? .null
        #expect(abs(two.minX - 2 * one.minX) <= 2 && abs(two.maxX - 2 * one.maxX) <= 2)
        #expect(abs(two.minY - 2 * one.minY) <= 2 && abs(two.maxY - 2 * one.maxY) <= 2)
    }

    @Test("覆盖层（整屏）与导出（选区裁剪，原点偏移）逐像素一致")
    func overlayMatchesExport() {
        let screen = CaptureScreen(id: 1, frame: CGRect(x: -300, y: 50, width: 200, height: 100), scale: 2)
        let text = "\u{4F18}\u{5316} Optimize"
        let style = TranslationTypesetter.Style(fontSize: 13, isBold: true, language: "zh-Hans")
        let lines = [TranslatedLine(text: text, origin: CGPoint(x: -270.5, y: 100))]
        let textFrame = TranslationPlacer.textBounds(lines, style: style)
        let placed = TranslatedBlock(
            blockID: 0, eraseFrame: textFrame, backdrop: .solid(PixelColor(red: 0, green: 0.48, blue: 1)), text: text,
            textFrame: textFrame, style: style, textColor: .white, alignment: .leading,
            eraseRects: [textFrame.insetBy(dx: -2, dy: -2)], plateImage: nil, lines: lines)
        let full = TestCanvas(width: 400, height: 200)
        TranslationPainter.draw(
            [placed], in: full.context,
            environment: environment(origin: screen.frame.origin, scale: 2, size: CGSize(width: 400, height: 200)))
        // 导出：选区从屏幕局部像素 (20, 40) 起，大小 300×120
        let crop = TestCanvas(width: 300, height: 120)
        let origin = CGPoint(x: screen.frame.minX + 10, y: screen.frame.minY + 20)
        TranslationPainter.draw(
            [placed], in: crop.context,
            environment: environment(origin: origin, scale: 2, size: CGSize(width: 300, height: 120)))
        var differences = 0
        for y in 0..<120 {
            for x in 0..<300 where full.pixel(x: x + 20, y: y + 40) != crop.pixel(x: x, y: y) {
                differences += 1
            }
        }
        #expect(differences == 0)
    }

    @Test("衬底：圆角外保持原样，内部先画模糊背景再叠 0.74 的主色")
    func plate() {
        let canvas = TestCanvas(width: 120, height: 80, fill: nil)
        let rect = CGRect(x: 10, y: 10, width: 40, height: 20)
        let backdrop = TestImage.solid(width: 80, height: 40, Pixel(0, 0, 255))
        TranslationPainter.draw(
            [block(erase: [rect], backdrop: .plate(red), plate: TranslationPlateImage(image: backdrop))],
            in: canvas.context, environment: environment(scale: 2, size: CGSize(width: 120, height: 80)))
        #expect(canvas.pixel(x: 20, y: 20) == .clear, "rounded corner stays untouched")
        let center = canvas.pixel(x: 60, y: 40)
        #expect(abs(Int(center.red) - 189) <= 2 && abs(Int(center.blue) - 66) <= 2 && center.alpha == 255)
        let bare = TestCanvas(width: 120, height: 80, fill: nil)
        TranslationPainter.draw(
            [block(erase: [rect], backdrop: .plate(red))], in: bare.context,
            environment: environment(scale: 2, size: CGSize(width: 120, height: 80)))
        #expect(abs(Int(bare.pixel(x: 60, y: 40).alpha) - 189) <= 1)
    }

    @Test("衬底图按对象判等")
    func plateImageEquality() {
        let image = TestImage.solid(width: 2, height: 2, .white)
        #expect(TranslationPlateImage(image: image) == TranslationPlateImage(image: image))
        #expect(
            TranslationPlateImage(image: image)
                != TranslationPlateImage(image: TestImage.solid(width: 2, height: 2, .white)))
    }

    @Test("绘制前后 context 状态不变；公开 init 在 textFrame 内自动换行")
    func restoresStateAndPublicInit() {
        let canvas = TestCanvas(width: 200, height: 100, fill: nil)
        let before = canvas.context.ctm
        let stub = TranslatedBlock(
            blockID: 7, eraseFrame: CGRect(x: 5, y: 5, width: 60, height: 40), backdrop: .solid(.white),
            text: "Optimize storage now", textFrame: CGRect(x: 5, y: 5, width: 60, height: 40), fontSize: 13,
            isBold: false, textColor: .black, alignment: .center)
        #expect(stub.lines.count >= 2)
        #expect(stub.eraseRects == [stub.eraseFrame])
        #expect(stub.lines.allSatisfy { $0.origin.x >= 5 })
        TranslationPainter.draw(
            [stub], in: canvas.context, environment: environment(scale: 2, size: CGSize(width: 200, height: 100)))
        #expect(canvas.context.ctm == before)
        #expect(canvas.countPixels { $0.alpha > 0 && $0.red < 128 } > 0)
    }
}
