import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("AnnotationRenderer 荧光笔 / 马赛克 / 文档顺序")
struct AnnotationCompositingTests {
    private let yellow = AnnotationStyle(color: .yellow, weight: .regular)
    private let red = AnnotationStyle(color: .red, weight: .regular)

    @Test("荧光笔以 multiply、0.5 alpha 合成：底色变暗但不是纯色")
    func highlighterMultiply() {
        let canvas = TestCanvas(width: 100, height: 100, fill: Pixel(200, 200, 200))
        let annotation = Annotation(shape: .highlighter([CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)]), style: yellow)
        let environment = RenderHarness.environment(width: 100, height: 100)
        AnnotationRenderer.draw(annotation, numberLabel: nil, in: canvas.context, environment: environment)

        // dst × (1 − 0.5) + (src × dst) × 0.5；黄 = (1, 0.8, 0)
        #expect(canvas.pixel(x: 50, y: 50).isClose(to: Pixel(200, 180, 100), tolerance: 3))
        #expect(canvas.pixel(x: 50, y: 20) == Pixel(200, 200, 200))
    }

    @Test("荧光笔在黑色文字上保持黑色（multiply 不遮字）")
    func highlighterKeepsDarkText() {
        let canvas = TestCanvas(width: 100, height: 100, fill: .black)
        let annotation = Annotation(shape: .highlighter([CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)]), style: yellow)
        let environment = RenderHarness.environment(width: 100, height: 100)
        AnnotationRenderer.draw(annotation, numberLabel: nil, in: canvas.context, environment: environment)
        #expect(canvas.pixel(x: 50, y: 50).isClose(to: .black, tolerance: 1))
    }

    @Test("荧光笔自交叉处不加深")
    func highlighterSelfIntersection() {
        let canvas = TestCanvas(width: 100, height: 100)
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80), CGPoint(x: 80, y: 20), CGPoint(x: 20, y: 80)]
        let annotation = Annotation(shape: .highlighter(points), style: yellow)
        let environment = RenderHarness.environment(width: 100, height: 100)
        AnnotationRenderer.draw(annotation, numberLabel: nil, in: canvas.context, environment: environment)

        let crossing = canvas.pixel(x: 50, y: 50)
        let single = canvas.pixel(x: 30, y: 30)
        #expect(!crossing.isWhite)
        #expect(crossing.isClose(to: single, tolerance: 2))
    }

    @Test("单点荧光笔画成圆点")
    func singlePointHighlighter() {
        let canvas = TestCanvas(width: 100, height: 100)
        let annotation = Annotation(shape: .highlighter([CGPoint(x: 50, y: 50)]), style: yellow)
        AnnotationRenderer.draw(
            annotation,
            numberLabel: nil,
            in: canvas.context,
            environment: RenderHarness.environment(width: 100, height: 100)
        )
        #expect(!canvas.pixel(x: 50, y: 50).isWhite)
        #expect(canvas.pixel(x: 50, y: 70).isWhite)
    }

    @Test("马赛克：笔迹内像素 = 像素化副本对应像素，笔迹外 = 原图")
    func mosaicUsesPixelatedFrame() throws {
        let frame = TestImage.coordinates(width: 100, height: 100)
        let pixelated = try #require(Pixelator.pixelated(frame, blockSize: 8))
        let original = TestCanvas(image: frame)
        let expected = TestCanvas(image: pixelated)

        let canvas = TestCanvas(image: frame)
        let annotation = Annotation(shape: .mosaic([CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50)]), style: red)
        let environment = RenderHarness.environment(width: 100, height: 100, pixelated: pixelated)
        AnnotationRenderer.draw(annotation, numberLabel: nil, in: canvas.context, environment: environment)

        #expect(canvas.pixel(x: 50, y: 50) == expected.pixel(x: 50, y: 50))
        #expect(canvas.pixel(x: 50, y: 50) != original.pixel(x: 50, y: 50))
        #expect(canvas.pixel(x: 30, y: 42) == expected.pixel(x: 30, y: 42))
        #expect(canvas.pixel(x: 50, y: 10) == original.pixel(x: 50, y: 10))
        #expect(canvas.pixel(x: 50, y: 90) == original.pixel(x: 50, y: 90))
    }

    @Test("马赛克在选区相对偏移（负坐标屏）下仍与帧像素对齐")
    func mosaicWithSelectionOffset() throws {
        let screenOrigin = CGPoint(x: 1440, y: -180)
        let frame = TestImage.coordinates(width: 100, height: 100)
        let pixelated = try #require(Pixelator.pixelated(frame, blockSize: 8))
        let expected = TestCanvas(image: pixelated)

        // 目标 = 帧中 (20, 20) 起的 60×60 区域
        let canvas = TestCanvas(width: 60, height: 60)
        let environment = RenderHarness.environment(
            width: 60,
            height: 60,
            origin: CGPoint(x: screenOrigin.x + 20, y: screenOrigin.y + 20),
            pixelated: pixelated,
            frameOrigin: screenOrigin
        )
        let points = [CGPoint(x: 1470, y: -130), CGPoint(x: 1510, y: -130)]
        AnnotationRenderer.draw(
            Annotation(shape: .mosaic(points), style: red),
            numberLabel: nil,
            in: canvas.context,
            environment: environment
        )
        #expect(canvas.pixel(x: 30, y: 30) == expected.pixel(x: 50, y: 50))
        #expect(canvas.pixel(x: 13, y: 25) == expected.pixel(x: 33, y: 45))
        #expect(canvas.pixel(x: 30, y: 5).isWhite)
    }

    @Test("马赛克在 2x 下按帧像素对齐")
    func mosaicAtRetina() throws {
        let frame = TestImage.coordinates(width: 200, height: 200)
        let pixelated = try #require(Pixelator.pixelated(frame, blockSize: 16))
        let expected = TestCanvas(image: pixelated)
        let canvas = TestCanvas(width: 200, height: 200)
        let environment = RenderHarness.environment(width: 200, height: 200, scale: 2, pixelated: pixelated)
        AnnotationRenderer.draw(
            Annotation(shape: .mosaic([CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50)]), style: red),
            numberLabel: nil,
            in: canvas.context,
            environment: environment
        )
        #expect(canvas.pixel(x: 100, y: 100) == expected.pixel(x: 100, y: 100))
        #expect(canvas.pixel(x: 60, y: 80) == expected.pixel(x: 60, y: 80))
        #expect(canvas.pixel(x: 100, y: 40).isWhite)
    }

    @Test("像素化副本未就绪时马赛克画半透明灰块占位")
    func mosaicPlaceholder() {
        let frame = TestImage.coordinates(width: 100, height: 100)
        let canvas = TestCanvas(image: frame)
        let environment = RenderHarness.environment(width: 100, height: 100, pixelated: nil)
        AnnotationRenderer.draw(
            Annotation(shape: .mosaic([CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50)]), style: red),
            numberLabel: nil,
            in: canvas.context,
            environment: environment
        )
        // (50, 50, 128) 与 50% 灰合成
        #expect(canvas.pixel(x: 50, y: 50).isClose(to: Pixel(89, 89, 128), tolerance: 2))
        #expect(canvas.pixel(x: 50, y: 10) == Pixel(50, 10, 128))
    }

    @Test("单点马赛克按笔刷宽的圆形区域像素化")
    func singlePointMosaic() throws {
        let frame = TestImage.coordinates(width: 100, height: 100)
        let pixelated = try #require(Pixelator.pixelated(frame, blockSize: 8))
        let expected = TestCanvas(image: pixelated)
        let canvas = TestCanvas(image: frame)
        AnnotationRenderer.draw(
            Annotation(shape: .mosaic([CGPoint(x: 50, y: 50)]), style: red),
            numberLabel: nil,
            in: canvas.context,
            environment: RenderHarness.environment(width: 100, height: 100, pixelated: pixelated)
        )
        #expect(canvas.pixel(x: 50, y: 50) == expected.pixel(x: 50, y: 50))
        #expect(canvas.pixel(x: 50, y: 80) == Pixel(50, 80, 128))
    }

    @Test("文档按顺序绘制：后画的马赛克盖住先画的矩形，后画的矩形盖在马赛克上")
    func documentOrder() throws {
        let frame = TestImage.solid(width: 100, height: 100, .white)
        let pixelated = try #require(Pixelator.pixelated(frame, blockSize: 8))
        let rect = Annotation(shape: .rectangle(CGRect(x: 40, y: 40, width: 20, height: 20)), style: red)
        let mosaic = Annotation(shape: .mosaic([CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)]), style: red)
        let environment = RenderHarness.environment(width: 100, height: 100, pixelated: pixelated)

        let mosaicOnTop = TestCanvas(width: 100, height: 100)
        let first = AnnotationDocument.empty.adding(rect).adding(mosaic)
        AnnotationRenderer.draw(first, in: mosaicOnTop.context, environment: environment)
        #expect(mosaicOnTop.pixel(x: 40, y: 50).isWhite)
        #expect(RenderHarness.isRed(mosaicOnTop.pixel(x: 50, y: 40)) == false)
        #expect(RenderHarness.isRed(mosaicOnTop.pixel(x: 50, y: 30)) == false)

        let rectOnTop = TestCanvas(width: 100, height: 100)
        let second = AnnotationDocument.empty.adding(mosaic).adding(rect)
        AnnotationRenderer.draw(second, in: rectOnTop.context, environment: environment)
        #expect(RenderHarness.isRed(rectOnTop.pixel(x: 40, y: 50)))
    }

    @Test("文档中的荧光笔整层垫在其他标注下面（与覆盖层的图层顺序一致）")
    func highlighterUnderOtherAnnotations() {
        let environment = RenderHarness.environment(width: 100, height: 100)
        let rect = Annotation(shape: .rectangle(CGRect(x: 20, y: 20, width: 60, height: 60)), style: red)
        let marker = Annotation(shape: .highlighter([CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)]), style: yellow)

        // 荧光笔后画（文档里在上）：矩形的红色描边仍是纯红，不被 multiply 染暗
        let later = TestCanvas(width: 100, height: 100)
        AnnotationRenderer.draw(
            AnnotationDocument.empty.adding(rect).adding(marker), in: later.context, environment: environment)
        #expect(later.pixel(x: 20, y: 50).isClose(to: RenderHarness.red, tolerance: 2))
        // 荧光笔本身仍在（描边以外的地方被染黄）
        #expect(!later.pixel(x: 50, y: 50).isWhite)

        // 与「荧光笔先画」逐像素相同：顺序只影响同类之间
        let earlier = TestCanvas(width: 100, height: 100)
        AnnotationRenderer.draw(
            AnnotationDocument.empty.adding(marker).adding(rect), in: earlier.context, environment: environment)
        let same = (0..<100).allSatisfy { y in
            (0..<100).allSatisfy { x in later.pixel(x: x, y: y) == earlier.pixel(x: x, y: y) }
        }
        #expect(same)
    }

    @Test("文档绘制的序号编号与逐个绘制一致")
    func documentNumbers() {
        let one = Annotation(shape: .number(center: CGPoint(x: 25, y: 50)), style: red)
        let shape = Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 10, height: 10)), style: red)
        let two = Annotation(shape: .number(center: CGPoint(x: 75, y: 50)), style: red)
        let document = AnnotationDocument.empty.adding(one).adding(shape).adding(two)
        let environment = RenderHarness.environment(width: 100, height: 100)

        let whole = TestCanvas(width: 100, height: 100)
        AnnotationRenderer.draw(document, in: whole.context, environment: environment)

        let manual = TestCanvas(width: 100, height: 100)
        AnnotationRenderer.draw(one, numberLabel: 1, in: manual.context, environment: environment)
        AnnotationRenderer.draw(shape, numberLabel: nil, in: manual.context, environment: environment)
        AnnotationRenderer.draw(two, numberLabel: 2, in: manual.context, environment: environment)

        let wrongLabel = TestCanvas(width: 100, height: 100)
        AnnotationRenderer.draw(two, numberLabel: 1, in: wrongLabel.context, environment: environment)

        var identical = true
        var differsFromWrongLabel = false
        for y in 0..<100 {
            for x in 0..<100 {
                identical = identical && whole.pixel(x: x, y: y) == manual.pixel(x: x, y: y)
                if x > 55, whole.pixel(x: x, y: y) != wrongLabel.pixel(x: x, y: y) { differsFromWrongLabel = true }
            }
        }
        #expect(identical)
        #expect(differsFromWrongLabel)
    }

    @Test("选中框：外扩 4 pt 的虚线，只描框不画标注本身")
    func selectionOutline() {
        let canvas = TestCanvas(width: 100, height: 100)
        let annotation = Annotation(shape: .rectangle(CGRect(x: 30, y: 30, width: 40, height: 40)), style: red)
        let environment = RenderHarness.environment(width: 100, height: 100)
        AnnotationRenderer.drawSelectionOutline(for: annotation, in: canvas.context, environment: environment)

        // bounds = (28.5, 28.5, 43, 43)，外扩 4 → 顶边 y = 24.5，覆盖像素行 24
        let colored = (25..<75).filter { !canvas.pixel(x: $0, y: 24).isWhite }.count
        #expect(colored > 20)
        #expect(colored < 50)
        #expect(canvas.pixel(x: 50, y: 30).isWhite)
        #expect(canvas.pixel(x: 50, y: 50).isWhite)
    }

    @Test("空点列的选中框不绘制")
    func selectionOutlineForEmptyShape() {
        let canvas = TestCanvas(width: 50, height: 50)
        let annotation = Annotation(shape: .pen([]), style: red)
        AnnotationRenderer.drawSelectionOutline(
            for: annotation,
            in: canvas.context,
            environment: RenderHarness.environment(width: 50, height: 50)
        )
        #expect(canvas.countPixels { !$0.isWhite } == 0)
    }
}
