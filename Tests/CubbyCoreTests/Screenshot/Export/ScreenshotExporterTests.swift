import AppKit
import CoreGraphics
import ImageIO
import Testing
@testable import CubbyCore

@Suite("ScreenshotExporter 裁剪与导出")
struct ScreenshotExporterTests {
    private let red = AnnotationStyle(color: .red, weight: .regular)

    @Test("导出像素尺寸 = 选区 × scale，内容为帧中对应像素")
    func exportSizeAndContent() throws {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        let selection = CGRect(x: 10, y: 20, width: 30, height: 15)
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: selection,
            document: .empty,
            pixelatedFrame: nil
        )
        #expect(export.pixelSize == CGSize(width: 60, height: 30))
        #expect(export.image.width == 60 && export.image.height == 30)
        #expect(export.selection == selection)
        #expect(export.screen == ExportFixtures.retina)

        let canvas = TestCanvas(image: export.image)
        #expect(canvas.pixel(x: 0, y: 0) == Pixel(20, 40, 128))
        #expect(canvas.pixel(x: 59, y: 29) == Pixel(79, 69, 128))
    }

    @Test("负坐标 1x 外接屏：按屏幕局部像素裁剪")
    func exportOnExternalScreen() throws {
        let frame = ExportFixtures.frame(ExportFixtures.external)
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: CGRect(x: 1450, y: -170, width: 20, height: 10),
            document: .empty,
            pixelatedFrame: nil
        )
        #expect(export.pixelSize == CGSize(width: 20, height: 10))
        #expect(TestCanvas(image: export.image).pixel(x: 0, y: 0) == Pixel(10, 10, 128))
    }

    @Test("小数选区向外取整，避免半像素缝")
    func fractionalSelectionIsIntegral() throws {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: CGRect(x: 10.3, y: 20.2, width: 5, height: 5),
            document: .empty,
            pixelatedFrame: nil
        )
        // (20.6, 40.4) – (30.6, 50.4) → (20, 40) – (31, 51)
        #expect(export.pixelSize == CGSize(width: 11, height: 11))
        #expect(TestCanvas(image: export.image).pixel(x: 0, y: 0) == Pixel(20, 40, 128))
    }

    @Test("越界选区被截到屏幕内")
    func selectionClippedToScreen() throws {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: CGRect(x: 90, y: 70, width: 30, height: 30),
            document: .empty,
            pixelatedFrame: nil
        )
        #expect(export.pixelSize == CGSize(width: 20, height: 20))
    }

    @Test("帧位图比屏幕像素尺寸小时按位图范围截取")
    func selectionClippedToImage() throws {
        let screen = ExportFixtures.retina
        let frame = FrozenFrame(screen: screen, image: TestImage.coordinates(width: 150, height: 100))
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: screen.frame,
            document: .empty,
            pixelatedFrame: nil
        )
        #expect(export.pixelSize == CGSize(width: 150, height: 100))
    }

    @Test(
        "空选区或屏外选区抛 emptySelection",
        arguments: [
            CGRect(x: 10, y: 10, width: 0, height: 20),
            CGRect(x: 500, y: 500, width: 20, height: 20),
            CGRect.null,
        ]
    )
    func emptySelectionThrows(selection: CGRect) {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        #expect(throws: ScreenshotExportError.emptySelection) {
            try ScreenshotExporter.export(frame: frame, selection: selection, document: .empty, pixelatedFrame: nil)
        }
        #expect(throws: ScreenshotExportError.emptySelection) {
            try ScreenshotExporter.crop(frame: frame, selection: selection)
        }
    }

    @Test("PNG 可被 NSBitmapImageRep 解回且尺寸一致；DPI = 72 × scale")
    func pngRoundTripAndDPI() throws {
        let retina = try ScreenshotExporter.export(
            frame: ExportFixtures.frame(ExportFixtures.retina),
            selection: CGRect(x: 0, y: 0, width: 50, height: 40),
            document: .empty,
            pixelatedFrame: nil
        )
        let rep = try #require(NSBitmapImageRep(data: retina.png))
        #expect(rep.pixelsWide == 100 && rep.pixelsHigh == 80)
        #expect(ImageFixtures.isPNG(retina.png))
        let retinaDPI = try #require(ExportFixtures.dpi(of: retina.png))
        #expect(retinaDPI.width == 144 && retinaDPI.height == 144)
        // 按点尺寸显示：Preview 用 DPI 换算
        #expect(rep.size == CGSize(width: 50, height: 40))

        let external = try ScreenshotExporter.export(
            frame: ExportFixtures.frame(ExportFixtures.external),
            selection: CGRect(x: 1440, y: -180, width: 10, height: 10),
            document: .empty,
            pixelatedFrame: nil
        )
        #expect(ExportFixtures.dpi(of: external.png)?.width == 72)
    }

    @Test("带标注的导出与 crop 的差异只在标注像素")
    func annotationsOnlyChangeTheirPixels() throws {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        let selection = CGRect(x: 10, y: 10, width: 60, height: 50)
        let rect = Annotation(shape: .rectangle(CGRect(x: 20, y: 20, width: 30, height: 20)), style: red)
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: selection,
            document: AnnotationDocument.empty.adding(rect),
            pixelatedFrame: nil
        )
        let clean = TestCanvas(image: try ScreenshotExporter.crop(frame: frame, selection: selection))
        let annotated = TestCanvas(image: export.image)
        #expect(clean.width == annotated.width && clean.height == annotated.height)

        // 选区原点 (10, 10) pt → 标注顶边 y = 20 pt 在导出图中为像素 y = 20
        let stroke = Rectangle(minX: 20, minY: 20, maxX: 80, maxY: 60, halfWidth: 3)
        var changedOutsideStroke = 0
        for y in 0..<annotated.height {
            for x in 0..<annotated.width {
                let changed = annotated.pixel(x: x, y: y) != clean.pixel(x: x, y: y)
                if changed && !stroke.near(x: x, y: y) { changedOutsideStroke += 1 }
            }
        }
        #expect(changedOutsideStroke == 0)
        #expect(RenderHarness.isRed(annotated.pixel(x: 50, y: 20)))
        #expect(annotated.pixel(x: 50, y: 40) == clean.pixel(x: 50, y: 40))
    }

    @Test("选区外的标注被裁掉")
    func annotationsOutsideSelectionAreCropped() throws {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        let selection = CGRect(x: 0, y: 0, width: 40, height: 40)
        let outside = Annotation(shape: .rectangle(CGRect(x: 60, y: 50, width: 20, height: 20)), style: red)
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: selection,
            document: AnnotationDocument.empty.adding(outside),
            pixelatedFrame: nil
        )
        let clean = try ScreenshotExporter.crop(frame: frame, selection: selection)
        #expect(export.image.dataProvider?.data == TestCanvas(image: clean).makeImage().dataProvider?.data)
    }

    @Test("导出中的马赛克使用像素化副本，与帧像素对齐")
    func mosaicInExport() throws {
        let frame = ExportFixtures.frame(ExportFixtures.external)
        let pixelated = try #require(Pixelator.pixelated(frame.image, blockSize: 8))
        let mosaic = Annotation(
            shape: .mosaic([CGPoint(x: 1470, y: -130), CGPoint(x: 1510, y: -130)]),
            style: red
        )
        let export = try ScreenshotExporter.export(
            frame: frame,
            selection: CGRect(x: 1460, y: -160, width: 60, height: 60),
            document: AnnotationDocument.empty.adding(mosaic),
            pixelatedFrame: pixelated
        )
        let expected = TestCanvas(image: pixelated)
        #expect(TestCanvas(image: export.image).pixel(x: 30, y: 30) == expected.pixel(x: 50, y: 50))
    }

    @Test("crop 返回帧中对应区域的独立位图")
    func cropContent() throws {
        let frame = ExportFixtures.frame(ExportFixtures.retina)
        let image = try ScreenshotExporter.crop(frame: frame, selection: CGRect(x: 5, y: 5, width: 10, height: 10))
        #expect(image.width == 20 && image.height == 20)
        #expect(TestCanvas(image: image).pixel(x: 3, y: 4) == Pixel(13, 14, 128))
    }

    @Test("pngData 写入 DPI；导出结果可跨并发域传递")
    func pngDataAndSendable() async throws {
        let image = TestImage.solid(width: 4, height: 4, .black)
        let png = try #require(ScreenshotExporter.pngData(image, scale: 3))
        #expect(ExportFixtures.dpi(of: png)?.width == 216)

        let export = try ScreenshotExporter.export(
            frame: ExportFixtures.frame(ExportFixtures.retina),
            selection: CGRect(x: 0, y: 0, width: 4, height: 4),
            document: .empty,
            pixelatedFrame: nil
        )
        let size = await Task.detached { export.pixelSize }.value
        #expect(size == CGSize(width: 8, height: 8))
    }

    @Test("ScreenshotExport 可由调用方直接构造")
    func memberwiseInit() {
        let image = TestImage.solid(width: 2, height: 2, .white)
        let export = ScreenshotExport(
            image: image,
            png: Data([1]),
            pixelSize: CGSize(width: 2, height: 2),
            selection: CGRect(x: 0, y: 0, width: 1, height: 1),
            screen: ExportFixtures.retina
        )
        #expect(export.png == Data([1]))
        #expect(export.screen.scale == 2)
    }
}

/// 描边矩形附近的像素判定（含抗锯齿半宽）
private struct Rectangle {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let halfWidth: Int

    func near(x: Int, y: Int) -> Bool {
        let withinX = x >= minX - halfWidth && x <= maxX + halfWidth
        let withinY = y >= minY - halfWidth && y <= maxY + halfWidth
        let nearVertical = abs(x - minX) <= halfWidth || abs(x - maxX) <= halfWidth
        let nearHorizontal = abs(y - minY) <= halfWidth || abs(y - maxY) <= halfWidth
        return (withinY && nearVertical) || (withinX && nearHorizontal)
    }
}
