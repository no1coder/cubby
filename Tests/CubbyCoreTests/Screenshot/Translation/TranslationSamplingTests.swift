import AppKit
import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("翻译版面的像素采样与小工具")
struct TranslationSamplingTests {
    private let white = RGB(red: 255, green: 255, blue: 255)
    private let black = RGB(red: 0, green: 0, blue: 0)

    private func scene(_ texts: [TranslationTestScene.Text], scale: CGFloat = 2, extra: ((CGContext) -> Void)? = nil)
        -> TranslationTestScene
    {
        TranslationTestScene(
            size: CGSize(width: 300, height: 100), scale: scale, background: .solid(.srgb(0xFFFFFF)), texts: texts,
            extra: extra)
    }

    // MARK: - PixelPatch

    @Test("只读取区域内的像素；全局点 ↔ 帧像素换算；区域在帧外时为 nil")
    func patchGeometry() throws {
        let screen = CaptureScreen(id: 1, frame: CGRect(x: 100, y: 50, width: 50, height: 40), scale: 2)
        let frame = FrozenFrame(screen: screen, image: TestImage.coordinates(width: 100, height: 80))
        let patch = try #require(PixelPatch(frame: frame, region: CGRect(x: 110, y: 60, width: 10, height: 5)))
        #expect(patch.bounds == PixelBox(minX: 20, minY: 20, maxX: 40, maxY: 30))
        #expect(patch.color(x: 25, y: 27) == RGB(red: 25, green: 27, blue: 128))
        #expect(
            patch.box(CGRect(x: 111.2, y: 61, width: 2, height: 100))
                == PixelBox(minX: 22, minY: 22, maxX: 27, maxY: 30))
        #expect(patch.box(CGRect(x: 0, y: 0, width: 5, height: 5)) == nil)
        #expect(
            patch.globalRect(PixelBox(minX: 20, minY: 20, maxX: 24, maxY: 22))
                == CGRect(x: 110, y: 60, width: 2, height: 1))
        #expect(PixelPatch(frame: frame, region: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }

    @Test("逐像素访问：相交的框重叠处只访问一次，不相交的框各自完整访问")
    func forEachPixelDedup() throws {
        let frame = FrozenFrame(
            screen: CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 40, height: 40), scale: 1),
            image: TestImage.solid(width: 40, height: 40, .white))
        let patch = try #require(PixelPatch(frame: frame, region: CGRect(x: 0, y: 0, width: 40, height: 40)))
        var visits: [Int: Int] = [:]
        patch.forEachPixel(in: [
            PixelBox(minX: 0, minY: 0, maxX: 10, maxY: 10), PixelBox(minX: 5, minY: 5, maxX: 15, maxY: 15),
            PixelBox(minX: 20, minY: 20, maxX: 30, maxY: 25),
        ]) { x, y, _ in visits[y * 40 + x, default: 0] += 1 }
        #expect(visits.count == 100 + 75 + 50)
        #expect(visits.values.allSatisfy { $0 == 1 })
    }

    @Test("环带：纯色判定与中位数；渐变判为复杂；框内中位色")
    func ringSampling() throws {
        let solid = FrozenFrame(
            screen: CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 50), scale: 1),
            image: TestImage.solid(width: 50, height: 50, Pixel(10, 20, 30)))
        let patch = try #require(PixelPatch(frame: solid, region: CGRect(x: 0, y: 0, width: 50, height: 50)))
        let box = PixelBox(minX: 10, minY: 10, maxX: 30, maxY: 20)
        #expect(
            patch.background(around: box, ringWidth: 3)
                == BackgroundSample(color: RGB(red: 10, green: 20, blue: 30), isSolid: true))
        #expect(patch.background(inside: box, bandWidth: 2)?.isSolid == true)
        #expect(patch.medianColor(in: [box]) == RGB(red: 10, green: 20, blue: 30))
        let gradient = FrozenFrame(
            screen: CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 256, height: 20), scale: 1),
            image: TestImage.coordinates(width: 256, height: 20))
        let ramp = try #require(PixelPatch(frame: gradient, region: CGRect(x: 0, y: 0, width: 256, height: 20)))
        #expect(
            ramp.background(around: PixelBox(minX: 50, minY: 5, maxX: 200, maxY: 15), ringWidth: 3)?.isSolid == false)
        #expect(ramp.inkColor(in: [], background: white) == nil)
    }

    @Test("同色空白：止于贯通的边、止于别的内容、扫到尽头")
    func freeRuns() throws {
        let text = TranslationTestScene.Text(string: "Hi", origin: CGPoint(x: 150, y: 50))
        let scene = scene([text]) { context in
            context.setFillColor(CGColor.srgb(0x000000))
            context.fill(CGRect(x: 100, y: 0, width: 1, height: 100))
        }
        let patch = try #require(PixelPatch(frame: scene.frame, region: CGRect(x: 0, y: 0, width: 300, height: 100)))
        let rows = 80..<100
        let toEdge = patch.freeColumns(from: 260, step: -1, limit: 0, rows: rows, background: white)
        #expect(toEdge == PixelPatch.FreeRun(length: 59, endsAtEdge: true))
        let toText = patch.freeColumns(from: 260, step: 1, limit: 600, rows: 60..<130, background: white)
        #expect(!toText.endsAtEdge && toText.length > 30 && toText.length < 60)
        let open = patch.freeColumns(from: 400, step: 1, limit: 600, rows: rows, background: white)
        #expect(open == PixelPatch.FreeRun(length: 200, endsAtEdge: true))
        let down = patch.freeRows(from: 150, limit: 200, columns: 400..<500, background: white)
        #expect(down == PixelPatch.FreeRun(length: 50, endsAtEdge: true))
    }

    // MARK: - 墨迹

    @Test("覆盖度：连线上的抗锯齿像素按投影计，离线太远的颜色与复杂背景的弱起伏记 0")
    func coverageModel() {
        let solid = InkModel(background: white, ink: black, isSolid: true)
        #expect(solid.coverage(RGB(red: 128, green: 128, blue: 128)) > 0.49)
        #expect(solid.coverage(RGB(red: 255, green: 0, blue: 0)) == 0)
        #expect(solid.coverage(white) == 0 && solid.coverage(black) == 1)
        let complex = InkModel(background: white, ink: black, isSolid: false)
        #expect(complex.coverage(RGB(red: 230, green: 230, blue: 230)) == 0)
        #expect(InkModel(background: white, ink: white, isSolid: true).coverage(black) == 0)
        #expect(solid == InkModel(background: white, ink: black, isSolid: true))
    }

    @Test("按墨迹收紧行框：文字在带边框的输入框里时，边框与框外颜色不算进墨迹")
    func tightInsideField() throws {
        let text = TranslationTestScene.Text(string: "October", origin: CGPoint(x: 60, y: 55))
        let scene = scene([text]) { context in
            context.setFillColor(CGColor.srgb(0xECECEC))
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
            context.setFillColor(CGColor.srgb(0xFFFFFF))
            context.fill(CGRect(x: 50, y: 38, width: 200, height: 24))
            context.setStrokeColor(CGColor.srgb(0xC7C7CC))
            context.stroke(CGRect(x: 50.5, y: 38.5, width: 199, height: 23))
        }
        let vision = RecognizedLine(text: "October", frame: CGRect(x: 45, y: 33, width: 70, height: 34))
        let geometry = BlockGeometry(TextBlock(id: 0, lines: [vision], alignment: .leading, text: "October"))
        let appearance = BlockAppearance.sample(
            geometry, frame: scene.frame, reach: .init(horizontal: 20, below: 0), limit: nil)
        #expect(appearance.isSolid)
        #expect(appearance.background == .white)
        #expect(appearance.geometry.frame.minX > 59 && appearance.geometry.frame.maxX < 115)
        #expect(appearance.geometry.frame.minY > 43 && appearance.geometry.frame.maxY < 60)
        #expect(abs(appearance.source.fontSize - 13) <= 1)
    }

    @Test("字号估计：只有 x 高字母时按 x 高；假名为主时按假名比例")
    func fontSizeRatios() {
        let ink = LineInk(minX: 0, maxX: 10, top: 0, bottom: 10, bodyTop: 0, bodyBottom: 10, baseline: 7)
        #expect(abs(InkMetrics.fontSize(ink, text: "some", ideographic: false) - 7 / 0.53) < 0.01)
        #expect(abs(InkMetrics.fontSize(ink, text: "Some", ideographic: false) - 7 / 0.72) < 0.01)
        #expect(
            abs(InkMetrics.fontSize(ink, text: "\u{304A}\u{3059}\u{3059}\u{3081}", ideographic: true) - 10 / 0.8) < 0.01
        )
        #expect(abs(InkMetrics.fontSize(ink, text: "\u{50A8}\u{5B58}", ideographic: true) - 10 / 0.86) < 0.01)
    }

    // MARK: - 颜色、语言、模糊、几何

    @Test("WCAG 对比度；按明暗方向补足对比度")
    func contrast() {
        #expect(abs(PixelColor.white.contrastRatio(with: .black) - 21) < 0.01)
        let gray = PixelColor(red: 0.85, green: 0.85, blue: 0.85)
        let fixed = gray.ensuringContrast(3, against: .white)
        #expect(fixed.contrastRatio(with: .white) >= 3 && fixed.red > 0.3)
        let lightOnDark = PixelColor(red: 0.3, green: 0.3, blue: 0.3).ensuringContrast(
            3, against: PixelColor(red: 0.2, green: 0.2, blue: 0.2))
        #expect(lightOnDark.red > 0.3)
        #expect(PixelColor.white.ensuringContrast(3, against: PixelColor(red: 0.6, green: 0.6, blue: 0.6)) == .white)
        #expect(PixelColor.black.ensuringContrast(3, against: .white) == .black)
    }

    @Test("排版语言：假名 → ja，韩文 → ko，汉字按简繁，拉丁文字 nil")
    func languageGuess() {
        #expect(TranslationLanguageGuess.language(of: "\u{30B9}\u{30C8}\u{30EC}\u{30FC}\u{30B8}") == "ja")
        #expect(TranslationLanguageGuess.language(of: "\u{C800}\u{C7A5} \u{acf5}\u{AC04}") == "ko")
        #expect(TranslationLanguageGuess.language(of: "\u{4F18}\u{5316}\u{50A8}\u{5B58}\u{7A7A}\u{95F4}") == "zh-Hans")
        #expect(
            TranslationLanguageGuess.language(of: "\u{6700}\u{4F73}\u{5316}\u{5132}\u{5B58}\u{7A7A}\u{9593}")
                == "zh-Hant")
        #expect(TranslationLanguageGuess.language(of: "Storage") == nil)
    }

    @Test("衬底模糊：盒宽为奇数；输出与衬底同像素大小；去墨迹后白底黑字几乎变回白底")
    func plateBlur() throws {
        #expect(PlateBlur.boxKernel(sigma: 20) == 41)
        #expect(PlateBlur.boxKernel(sigma: 0) == 1)
        let text = TranslationTestScene.Text(string: "Storage", origin: CGPoint(x: 100, y: 55), size: 20)
        let scene = scene([text])
        let line = TranslationTestScene.lineFrame(text)
        let plate = line.insetBy(dx: -6, dy: -6).integral
        let model = InkModel(background: white, ink: black, isSolid: true)
        let image = try #require(
            PlateBlur.image(
                frame: scene.frame, plate: plate, radius: 10,
                deinking: .init(model: model, lines: [line.insetBy(dx: -2, dy: -2)])))
        #expect(image.width == Int(plate.width * 2) && image.height == Int(plate.height * 2))
        let canvas = TestCanvas(image: image)
        #expect(canvas.pixel(x: image.width / 2, y: image.height / 2).red > 240)
        let flat = try #require(
            PlateBlur.image(frame: scene.frame, plate: plate, radius: 0, deinking: .init(model: model, lines: [])))
        #expect(flat.width == image.width)
    }

    @Test("行框推算的兜底值：视觉中线、行距、收紧后的几何")
    func geometryFallbacks() {
        let lines = [
            RecognizedLine(text: "First", frame: CGRect(x: 10, y: 10, width: 100, height: 14)),
            RecognizedLine(text: "Second", frame: CGRect(x: 10, y: 30, width: 80, height: 14)),
        ]
        let geometry = BlockGeometry(TextBlock(id: 0, lines: lines, alignment: .leading, text: "First Second"))
        #expect(geometry.pitch == 20 && geometry.isMultiLine && geometry.pad == 2)
        #expect(geometry.fontSize == 13.5)
        #expect(abs(geometry.visualCenter(ofLine: 0) - (10 + 0.42 * 13.5)) < 0.01)
        let tight = geometry.tightened(to: [CGRect(x: 12, y: 12, width: 50, height: 10), nil])
        #expect(tight.lineFrames == [CGRect(x: 12, y: 12, width: 50, height: 10), lines[1].frame])
        #expect(tight.frame == CGRect(x: 10, y: 12, width: 80, height: 32))
        let cjk = BlockGeometry(
            TextBlock(
                id: 0,
                lines: [RecognizedLine(text: "\u{8BBE}\u{7F6E}", frame: CGRect(x: 0, y: 0, width: 30, height: 16))],
                alignment: .leading, text: "\u{8BBE}\u{7F6E}"))
        #expect(cjk.isIdeographic && cjk.fontSize == 13)
        #expect(abs(cjk.visualCenter(ofLine: 0) - 0.48 * 13) < 0.01)
    }
}
