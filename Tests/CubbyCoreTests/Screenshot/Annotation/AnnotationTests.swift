import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 构造各类标注的简写（regular 档、红色）
enum AnnotationSamples {
    static let regular = AnnotationStyle(color: .red, weight: .regular)

    static func make(_ shape: AnnotationShape, style: AnnotationStyle = regular) -> Annotation {
        Annotation(shape: shape, style: style)
    }

    /// 每种 shape 各一个，用于参数化测试
    static let allShapes: [AnnotationShape] = [
        .rectangle(CGRect(x: 10, y: 20, width: 100, height: 50)),
        .ellipse(CGRect(x: 10, y: 20, width: 100, height: 50)),
        .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70)),
        .pen([CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 30), CGPoint(x: 80, y: 20)]),
        .highlighter([CGPoint(x: 10, y: 20), CGPoint(x: 90, y: 20)]),
        .mosaic([CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 40)]),
        .text("Hello", origin: CGPoint(x: 10, y: 20), maxWidth: 200),
        .number(center: CGPoint(x: 10, y: 20)),
    ]
}

@Suite("AnnotationID 标注标识")
struct AnnotationIDTests {
    @Test("每次创建都唯一；rawValue 相同则相等")
    func uniqueness() {
        #expect(AnnotationID() != AnnotationID())
        let uuid = UUID()
        #expect(AnnotationID(rawValue: uuid) == AnnotationID(rawValue: uuid))
        #expect(AnnotationID(rawValue: uuid).rawValue == uuid)
    }

    @Test("JSON 编解码往返")
    func codable() throws {
        let id = AnnotationID()
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(AnnotationID.self, from: data) == id)
    }
}

@Suite("Annotation 几何：tool / bounds")
struct AnnotationBoundsTests {
    @Test("shape → tool 映射")
    func toolMapping() {
        let tools = AnnotationSamples.allShapes.map { AnnotationSamples.make($0).tool }
        #expect(tools == [.rectangle, .ellipse, .arrow, .pen, .highlighter, .mosaic, .text, .number])
    }

    @Test("矩形 / 椭圆 bounds 外扩半个线宽（regular = 3 pt）")
    func rectangleAndEllipseBounds() {
        let rect = CGRect(x: 10, y: 10, width: 100, height: 50)
        let expected = CGRect(x: 8.5, y: 8.5, width: 103, height: 53)
        #expect(AnnotationSamples.make(.rectangle(rect)).bounds == expected)
        #expect(AnnotationSamples.make(.ellipse(rect)).bounds == expected)
    }

    @Test("反向拖出的矩形先归一化")
    func negativeRectIsStandardized() {
        let flipped = CGRect(x: 110, y: 60, width: -100, height: -50)
        let bounds = AnnotationSamples.make(.rectangle(flipped)).bounds
        #expect(bounds == CGRect(x: 8.5, y: 8.5, width: 103, height: 53))
    }

    @Test("heavy 档外扩更多")
    func heavierWeightExpandsMore() {
        let rect = CGRect(x: 10, y: 10, width: 100, height: 50)
        let heavy = AnnotationSamples.make(.rectangle(rect), style: AnnotationStyle(color: .red, weight: .heavy))
        #expect(heavy.bounds == rect.insetBy(dx: -2.5, dy: -2.5))
    }

    @Test("箭头 bounds 包含首尾两端")
    func arrowBounds() {
        let tail = CGPoint(x: 10, y: 20)
        let head = CGPoint(x: 110, y: 70)
        let bounds = AnnotationSamples.make(.arrow(from: tail, to: head)).bounds
        #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(tail))
        #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(head))
        #expect(bounds.width < 130)
    }

    @Test("画笔 / 荧光笔 / 马赛克 bounds 外扩半个线宽或笔刷宽")
    func freehandBounds() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)]
        #expect(AnnotationSamples.make(.pen(points)).bounds == CGRect(x: -2, y: -2, width: 24, height: 4))
        #expect(AnnotationSamples.make(.highlighter(points)).bounds == CGRect(x: -9, y: -9, width: 38, height: 18))
        #expect(AnnotationSamples.make(.mosaic(points)).bounds == CGRect(x: -12, y: -12, width: 44, height: 24))
    }

    @Test("单点画笔 bounds 以该点为中心")
    func singlePointPenBounds() {
        let bounds = AnnotationSamples.make(.pen([CGPoint(x: 50, y: 50)])).bounds
        #expect(abs(bounds.midX - 50) < 0.01)
        #expect(abs(bounds.midY - 50) < 0.01)
        #expect(bounds.width >= 4)
    }

    @Test("空点列的 bounds 为空")
    func emptyPointsBounds() {
        #expect(AnnotationSamples.make(.pen([])).bounds.isEmpty)
    }

    @Test("文字 bounds = origin + TextLayout 排版尺寸")
    func textBounds() {
        let annotation = AnnotationSamples.make(.text("Hello", origin: CGPoint(x: 50, y: 60), maxWidth: 300))
        let size = TextLayout.size(of: "Hello", fontSize: 20, maxWidth: 300)
        #expect(annotation.bounds == CGRect(origin: CGPoint(x: 50, y: 60), size: size))
        #expect(size.width > 0 && size.height > 0)
    }

    @Test("序号 bounds = 以中心为圆心、直径按档的正方形")
    func numberBounds() {
        let annotation = AnnotationSamples.make(.number(center: CGPoint(x: 100, y: 100)))
        #expect(annotation.bounds == CGRect(x: 87, y: 87, width: 26, height: 26))
    }
}

@Suite("Annotation 命中测试")
struct AnnotationHitTestTests {
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test("矩形按描边环命中：边上命中，内部空白不命中")
    func rectangleRing() {
        let annotation = AnnotationSamples.make(.rectangle(rect))
        #expect(annotation.hitTest(CGPoint(x: 200, y: 100), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 100, y: 150), tolerance: 0))
        #expect(!annotation.hitTest(CGPoint(x: 200, y: 150), tolerance: 6))
        #expect(!annotation.hitTest(CGPoint(x: 200, y: 90), tolerance: 6))
    }

    @Test("矩形容差边界：线宽一半 + 容差以内命中")
    func rectangleTolerance() {
        let annotation = AnnotationSamples.make(.rectangle(rect))
        // 描边半宽 1.5 + 容差 6 = 7.5
        #expect(annotation.hitTest(CGPoint(x: 200, y: 92.6), tolerance: 6))
        #expect(!annotation.hitTest(CGPoint(x: 200, y: 92.4), tolerance: 6))
    }

    @Test("椭圆按轮廓命中：最右点命中，中心不命中")
    func ellipseOutline() {
        let annotation = AnnotationSamples.make(.ellipse(rect))
        #expect(annotation.hitTest(CGPoint(x: 300, y: 150), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 200, y: 104), tolerance: 6))
        #expect(!annotation.hitTest(CGPoint(x: 200, y: 150), tolerance: 6))
        #expect(!annotation.hitTest(CGPoint(x: 100, y: 100), tolerance: 2))
    }

    @Test("箭头：箭杆与头部命中，远处不命中")
    func arrowHit() {
        let annotation = AnnotationSamples.make(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0)))
        #expect(annotation.hitTest(CGPoint(x: 100, y: 0), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 195, y: 0), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 100, y: 5), tolerance: 6))
        #expect(!annotation.hitTest(CGPoint(x: 100, y: 20), tolerance: 6))
    }

    @Test("画笔按到线距离命中")
    func penDistance() {
        let annotation = AnnotationSamples.make(.pen([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]))
        #expect(annotation.hitTest(CGPoint(x: 50, y: 0), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 50, y: 7.9), tolerance: 6))
        #expect(!annotation.hitTest(CGPoint(x: 50, y: 8.1), tolerance: 6))
    }

    @Test("荧光笔与马赛克按笔刷宽命中")
    func brushDistance() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        #expect(AnnotationSamples.make(.highlighter(points)).hitTest(CGPoint(x: 50, y: 8.9), tolerance: 0))
        #expect(!AnnotationSamples.make(.highlighter(points)).hitTest(CGPoint(x: 50, y: 9.5), tolerance: 0))
        #expect(AnnotationSamples.make(.mosaic(points)).hitTest(CGPoint(x: 50, y: 11.9), tolerance: 0))
        #expect(!AnnotationSamples.make(.mosaic(points)).hitTest(CGPoint(x: 50, y: 12.5), tolerance: 0))
    }

    @Test("单点画笔在点附近命中")
    func singlePointPen() {
        let annotation = AnnotationSamples.make(.pen([CGPoint(x: 50, y: 50)]))
        #expect(annotation.hitTest(CGPoint(x: 51, y: 50), tolerance: 0))
        #expect(!annotation.hitTest(CGPoint(x: 60, y: 50), tolerance: 2))
    }

    @Test("空点列永不命中")
    func emptyPointsNeverHit() {
        #expect(!AnnotationSamples.make(.pen([])).hitTest(.zero, tolerance: 100))
    }

    @Test("文字按排版框命中（含容差）")
    func textBox() {
        let annotation = AnnotationSamples.make(.text("Hello world", origin: CGPoint(x: 100, y: 100), maxWidth: 400))
        let bounds = annotation.bounds
        #expect(annotation.hitTest(CGPoint(x: bounds.midX, y: bounds.midY), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: bounds.maxX + 3, y: bounds.midY), tolerance: 4))
        #expect(!annotation.hitTest(CGPoint(x: bounds.maxX + 5, y: bounds.midY), tolerance: 4))
    }

    @Test("序号按圆形区域命中")
    func numberDisc() {
        let annotation = AnnotationSamples.make(.number(center: CGPoint(x: 100, y: 100)))
        #expect(annotation.hitTest(CGPoint(x: 100, y: 100), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 112.9, y: 100), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 116, y: 100), tolerance: 4))
        // 圆外接正方形的角落不命中
        #expect(!annotation.hitTest(CGPoint(x: 112, y: 112), tolerance: 0))
    }
}

@Suite("Annotation 不可变变换")
struct AnnotationTransformTests {
    @Test("translated 平移每种 shape 的全部几何", arguments: AnnotationSamples.allShapes)
    func translatedShiftsBounds(shape: AnnotationShape) {
        let annotation = AnnotationSamples.make(shape)
        let moved = annotation.translated(by: CGVector(dx: 15, dy: -7))

        #expect(moved.id == annotation.id)
        #expect(moved.style == annotation.style)
        #expect(moved.tool == annotation.tool)
        #expect(abs(moved.bounds.minX - annotation.bounds.minX - 15) < 0.001)
        #expect(abs(moved.bounds.minY - annotation.bounds.minY + 7) < 0.001)
        #expect(abs(moved.bounds.width - annotation.bounds.width) < 0.001)
    }

    @Test("translated 的具体几何值")
    func translatedValues() {
        let delta = CGVector(dx: 1, dy: 2)
        let moved = AnnotationSamples.allShapes.map { AnnotationSamples.make($0).translated(by: delta).shape }
        #expect(moved[0] == .rectangle(CGRect(x: 11, y: 22, width: 100, height: 50)))
        #expect(moved[2] == .arrow(from: CGPoint(x: 11, y: 22), to: CGPoint(x: 111, y: 72)))
        #expect(moved[3] == .pen([CGPoint(x: 11, y: 22), CGPoint(x: 41, y: 32), CGPoint(x: 81, y: 22)]))
        #expect(moved[6] == .text("Hello", origin: CGPoint(x: 11, y: 22), maxWidth: 200))
        #expect(moved[7] == .number(center: CGPoint(x: 11, y: 22)))
    }

    @Test("withStyle 只改样式")
    func withStyle() {
        let annotation = AnnotationSamples.make(.number(center: .zero))
        let blue = AnnotationStyle(color: .blue, weight: .heavy)
        let restyled = annotation.withStyle(blue)
        #expect(restyled.style == blue)
        #expect(restyled.id == annotation.id)
        #expect(restyled.shape == annotation.shape)
        #expect(annotation.style == AnnotationSamples.regular)
    }

    @Test("withText 只替换文字内容；非文字标注返回自身")
    func withText() {
        let text = AnnotationSamples.make(.text("old", origin: CGPoint(x: 5, y: 6), maxWidth: 80))
        let updated = text.withText("new")
        #expect(updated.shape == .text("new", origin: CGPoint(x: 5, y: 6), maxWidth: 80))
        #expect(updated.id == text.id)

        let rect = AnnotationSamples.make(.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(rect.withText("x") == rect)
    }
}
