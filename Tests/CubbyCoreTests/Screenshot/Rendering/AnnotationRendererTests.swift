import CoreGraphics
import Testing
@testable import CubbyCore

/// 渲染测试的公共工具：白底画布 + 以画布左上为 origin 的环境
enum RenderHarness {
    static let red = Pixel(AnnotationColor.red.rgba)

    static func environment(
        width: Int,
        height: Int,
        origin: CGPoint = .zero,
        scale: CGFloat = 1,
        pixelated: CGImage? = nil,
        frameOrigin: CGPoint = .zero
    ) -> RenderEnvironment {
        RenderEnvironment(
            origin: origin,
            scale: scale,
            targetPixelSize: CGSize(width: width, height: height),
            pixelatedFrame: pixelated,
            frameOrigin: frameOrigin
        )
    }

    /// 在白底画布上画一个标注，返回画布
    static func render(
        _ annotation: Annotation,
        width: Int = 100,
        height: Int = 100,
        origin: CGPoint = .zero,
        scale: CGFloat = 1,
        numberLabel: Int? = nil
    ) -> TestCanvas {
        let canvas = TestCanvas(width: width, height: height)
        let environment = environment(width: width, height: height, origin: origin, scale: scale)
        AnnotationRenderer.draw(annotation, numberLabel: numberLabel, in: canvas.context, environment: environment)
        return canvas
    }

    static func isRed(_ pixel: Pixel) -> Bool {
        pixel.isClose(to: red, tolerance: 3)
    }
}

@Suite("AnnotationRenderer 形状像素校验")
struct AnnotationRendererShapeTests {
    private let red = AnnotationStyle(color: .red, weight: .regular)

    @Test("矩形：四边中点为描边色，内部与外部仍为白")
    func rectangle() {
        let annotation = Annotation(shape: .rectangle(CGRect(x: 20, y: 20, width: 60, height: 40)), style: red)
        let canvas = RenderHarness.render(annotation)
        #expect(RenderHarness.isRed(canvas.pixel(x: 50, y: 20)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 50, y: 59)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 20, y: 40)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 79, y: 40)))
        #expect(canvas.pixel(x: 50, y: 40).isWhite)
        #expect(canvas.pixel(x: 50, y: 10).isWhite)
        #expect(canvas.pixel(x: 90, y: 40).isWhite)
    }

    @Test("矩形在 2x 下按像素放大：同一全局点落在两倍像素处")
    func rectangleAtRetina() {
        let annotation = Annotation(shape: .rectangle(CGRect(x: 20, y: 20, width: 60, height: 40)), style: red)
        let canvas = RenderHarness.render(annotation, width: 200, height: 200, scale: 2)
        #expect(RenderHarness.isRed(canvas.pixel(x: 100, y: 40)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 40, y: 80)))
        #expect(canvas.pixel(x: 100, y: 80).isWhite)
        #expect(canvas.pixel(x: 100, y: 30).isWhite)
    }

    @Test("椭圆：中心白、轮廓有色")
    func ellipse() {
        let annotation = Annotation(shape: .ellipse(CGRect(x: 20, y: 20, width: 60, height: 40)), style: red)
        let canvas = RenderHarness.render(annotation)
        #expect(canvas.pixel(x: 50, y: 40).isWhite)
        #expect(RenderHarness.isRed(canvas.pixel(x: 50, y: 20)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 79, y: 40)))
        // 外接矩形的角落不在椭圆上
        #expect(canvas.pixel(x: 22, y: 22).isWhite)
    }

    @Test("箭头：头部与箭杆有色，箭杆两侧与尾后为白")
    func arrow() {
        let annotation = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50)), style: red)
        let canvas = RenderHarness.render(annotation)
        #expect(RenderHarness.isRed(canvas.pixel(x: 84, y: 50)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 80, y: 52)))
        #expect(!canvas.pixel(x: 50, y: 49).isWhite)
        #expect(canvas.pixel(x: 50, y: 45).isWhite)
        #expect(canvas.pixel(x: 5, y: 50).isWhite)
        #expect(canvas.pixel(x: 95, y: 50).isWhite)
    }

    @Test("画笔：起点（圆头）与路径中段有色，远处为白")
    func pen() {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 10), CGPoint(x: 90, y: 10)]
        let canvas = RenderHarness.render(Annotation(shape: .pen(points), style: red))
        #expect(RenderHarness.isRed(canvas.pixel(x: 10, y: 10)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 30, y: 10)))
        #expect(canvas.pixel(x: 30, y: 20).isWhite)
    }

    @Test("单点画笔画成直径 = 线宽的圆点")
    func singlePointPen() {
        let canvas = RenderHarness.render(Annotation(shape: .pen([CGPoint(x: 50, y: 50)]), style: red))
        #expect(RenderHarness.isRed(canvas.pixel(x: 50, y: 50)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 49, y: 49)))
        #expect(canvas.pixel(x: 54, y: 50).isWhite)
    }

    @Test("空点列不绘制")
    func emptyPen() {
        let canvas = RenderHarness.render(Annotation(shape: .pen([]), style: red))
        #expect(canvas.countPixels { !$0.isWhite } == 0)
    }

    @Test("2x 时线宽像素翻倍（沿法线数有色像素）")
    func lineWidthScales() {
        let points = [CGPoint(x: 10, y: 20), CGPoint(x: 90, y: 20)]
        let annotation = Annotation(shape: .pen(points), style: red)
        let oneX = RenderHarness.render(annotation, width: 100, height: 40)
        let twoX = RenderHarness.render(annotation, width: 200, height: 80, scale: 2)
        // regular 画笔线宽 4 pt
        #expect(oneX.countPixels(inColumn: 50, where: RenderHarness.isRed) == 4)
        #expect(twoX.countPixels(inColumn: 100, where: RenderHarness.isRed) == 8)
    }

    @Test("origin 平移：同一全局标注落到目标位图的相对位置")
    func originOffset() {
        let annotation = Annotation(shape: .rectangle(CGRect(x: 120, y: 130, width: 40, height: 40)), style: red)
        let oneX = RenderHarness.render(annotation, origin: CGPoint(x: 100, y: 100))
        #expect(RenderHarness.isRed(oneX.pixel(x: 40, y: 30)))
        #expect(oneX.pixel(x: 40, y: 50).isWhite)

        let twoX = RenderHarness.render(annotation, width: 200, height: 200, origin: CGPoint(x: 100, y: 100), scale: 2)
        #expect(RenderHarness.isRed(twoX.pixel(x: 80, y: 60)))
        #expect(twoX.pixel(x: 80, y: 100).isWhite)
    }

    @Test("负坐标外接屏：origin 为负时同样正确")
    func negativeOrigin() {
        let annotation = Annotation(shape: .rectangle(CGRect(x: 1460, y: -170, width: 40, height: 40)), style: red)
        let canvas = RenderHarness.render(annotation, origin: CGPoint(x: 1440, y: -180))
        #expect(RenderHarness.isRed(canvas.pixel(x: 40, y: 10)))
        #expect(canvas.pixel(x: 40, y: 30).isWhite)
    }

    @Test("文字：排版框内出现墨迹，框外为白")
    func text() {
        let origin = CGPoint(x: 10, y: 20)
        let annotation = Annotation(shape: .text("Hi", origin: origin, maxWidth: 80), style: red)
        let canvas = RenderHarness.render(annotation)
        let box = annotation.bounds.insetBy(dx: -1, dy: -1)
        var inside = 0
        var outside = 0
        for y in 0..<100 {
            for x in 0..<100 where !canvas.pixel(x: x, y: y).isWhite {
                if box.contains(CGPoint(x: x, y: y)) { inside += 1 } else { outside += 1 }
            }
        }
        #expect(inside > 20)
        #expect(outside == 0)
        #expect(canvas.countPixels(where: RenderHarness.isRed) > 0)
    }

    @Test("序号：圆内为色、圆外为白，编号以白色绘制")
    func numberBadge() {
        let annotation = Annotation(shape: .number(center: CGPoint(x: 50, y: 50)), style: red)
        let canvas = RenderHarness.render(annotation, numberLabel: 1)
        #expect(RenderHarness.isRed(canvas.pixel(x: 41, y: 50)))
        #expect(RenderHarness.isRed(canvas.pixel(x: 50, y: 40)))
        #expect(canvas.pixel(x: 35, y: 50).isWhite)
        #expect(canvas.pixel(x: 39, y: 39).isWhite)
        let whiteInside = (44..<57).flatMap { y in (44..<57).map { x in canvas.pixel(x: x, y: y) } }.filter {
            $0.isClose(to: .white, tolerance: 8)
        }
        #expect(!whiteInside.isEmpty)
    }

    @Test("序号无编号时只画实心圆")
    func numberWithoutLabel() {
        let annotation = Annotation(shape: .number(center: CGPoint(x: 50, y: 50)), style: red)
        let canvas = RenderHarness.render(annotation, numberLabel: nil)
        let inside = (44..<57).flatMap { y in (44..<57).map { x in canvas.pixel(x: x, y: y) } }
        #expect(inside.allSatisfy(RenderHarness.isRed))
    }

    @Test("三位数编号时圆加宽为胶囊")
    func numberCapsule() {
        let annotation = Annotation(shape: .number(center: CGPoint(x: 50, y: 50)), style: red)
        let single = RenderHarness.render(annotation, numberLabel: 7)
        let triple = RenderHarness.render(annotation, numberLabel: 100)
        #expect(single.pixel(x: 34, y: 50).isWhite)
        #expect(RenderHarness.isRed(triple.pixel(x: 34, y: 50)))
    }

    @Test("绘制后恢复 context 状态")
    func restoresGraphicsState() {
        let canvas = TestCanvas(width: 50, height: 50)
        let before = canvas.context.ctm
        let annotation = Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 10, height: 10)), style: red)
        let environment = RenderHarness.environment(width: 50, height: 50, origin: CGPoint(x: 3, y: 3), scale: 1)
        AnnotationRenderer.draw(annotation, numberLabel: nil, in: canvas.context, environment: environment)
        AnnotationRenderer.draw(
            AnnotationDocument.empty.adding(annotation), in: canvas.context, environment: environment)
        AnnotationRenderer.drawSelectionOutline(for: annotation, in: canvas.context, environment: environment)
        #expect(canvas.context.ctm == before)
    }
}
