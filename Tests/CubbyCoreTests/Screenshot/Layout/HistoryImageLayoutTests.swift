import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 晾衣绳放大编辑的图片摆放、缩放档位与按原图像素导出
@Suite("HistoryImageLayout 放大编辑的摆放与缩放")
struct HistoryImageLayoutTests {
    /// 1440 × 900 pt @2x
    private static let screen = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    /// 外接屏：1920 × 1080 @1x，原点在负坐标
    private static let external = CaptureScreen(
        id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)

    private func onGrid(_ rect: CGRect, _ screen: CaptureScreen) -> Bool {
        let values = [
            rect.minX - screen.frame.minX, rect.minY - screen.frame.minY, rect.width, rect.height,
        ].map { $0 * screen.scale }
        return values.allSatisfy { $0.rounded() == $0 }
    }

    @Test("适合：不超过宽 80%、高 70% 与上下保留区；居中；对齐像素网格")
    func fit() throws {
        let layout = try #require(
            HistoryImageLayout.layout(imagePixelSize: CGSize(width: 1600, height: 1000), screen: Self.screen))
        let rect = layout.imageRect
        let band = (top: HistoryImageLayout.topReserve, bottom: 900 - HistoryImageLayout.bottomReserve)
        #expect(rect.width <= 1440 * 0.8 + 0.5)
        #expect(rect.height <= 900 * 0.7 + 0.5)
        #expect(rect.minY >= band.top - 0.5 && rect.maxY <= band.bottom + 0.5)
        #expect(abs(rect.midX - 720) <= 0.5)
        #expect(abs(rect.midY - (band.top + band.bottom) / 2) <= 0.5)
        #expect(onGrid(rect, Self.screen))
        // 高度受限：550 / 1000
        #expect(abs(layout.zoom - 0.55) < 0.0001)
        #expect(layout.zoomPercent == 55)
        #expect(layout.canZoomIn && layout.canZoomOut)
    }

    @Test("小图最多放大到 2×，且「适合」就是上限时不能再放大")
    func smallImageCappedAtTwo() throws {
        let layout = try #require(
            HistoryImageLayout.layout(imagePixelSize: CGSize(width: 100, height: 50), screen: Self.screen))
        #expect(layout.zoom == 2)
        #expect(layout.imageRect.size == CGSize(width: 200, height: 100))
        #expect(!layout.canZoomIn)
        #expect(layout.steppedZoom(1) == 2)
        #expect(layout.steppedZoom(-1) == 1.5)
    }

    @Test("指定缩放夹在允许范围内；放大上限是只留标题行与工具栏时放得下的最大值")
    func explicitZoomClamped() throws {
        let size = CGSize(width: 1600, height: 1000)
        let big = try #require(HistoryImageLayout.layout(imagePixelSize: size, screen: Self.screen, zoom: 5))
        // 竖直范围 900 − 60 − 100 = 740 pt → 0.74
        #expect(abs(big.zoom - 0.74) < 0.0001)
        #expect(big.zoom == big.zoomRange.upperBound)
        #expect(big.imageRect.minY >= HistoryImageLayout.zoomedTopReserve - 0.5)
        #expect(big.imageRect.maxY <= 900 - HistoryImageLayout.zoomedBottomReserve + 0.5)
        #expect(!big.canZoomIn)
        let tiny = try #require(HistoryImageLayout.layout(imagePixelSize: size, screen: Self.screen, zoom: 0.01))
        #expect(tiny.zoom == HistoryImageLayout.minimumZoom)
        #expect(!tiny.canZoomOut)
    }

    @Test("宽图：放大上限按整屏宽减边距计算，比「适合」大")
    func wideImageCanZoomPastFit() throws {
        let size = CGSize(width: 4000, height: 500)
        let fit = try #require(HistoryImageLayout.layout(imagePixelSize: size, screen: Self.screen))
        #expect(abs(fit.zoom - 1440 * 0.8 / 4000) < 0.0001)
        #expect(abs(fit.zoomRange.upperBound - (1440 - 2 * HistoryImageLayout.sideMargin) / 4000) < 0.0001)
        let zoomed = try #require(
            HistoryImageLayout.layout(imagePixelSize: size, screen: Self.screen, zoom: fit.steppedZoom(1)))
        #expect(zoomed.zoom > fit.zoom)
        #expect(zoomed.imageRect.minX >= HistoryImageLayout.sideMargin - 0.5)
    }

    @Test("缩放档位：取下一个更大 / 更小的档位")
    func steps() throws {
        let layout = try #require(
            HistoryImageLayout.layout(
                imagePixelSize: CGSize(width: 400, height: 300), screen: Self.screen, zoom: 0.6))
        #expect(layout.steppedZoom(1) == 0.67)
        #expect(layout.steppedZoom(-1) == 0.5)
        #expect(layout.steppedZoom(0) == 0.6)
        let exact = try #require(
            HistoryImageLayout.layout(imagePixelSize: CGSize(width: 400, height: 300), screen: Self.screen, zoom: 1))
        #expect(exact.steppedZoom(1) == 1.25)
        #expect(exact.steppedZoom(-1) == 0.75)
    }

    @Test("外接屏（负坐标 @1x）：在该屏内居中并对齐像素")
    func externalScreen() throws {
        let layout = try #require(
            HistoryImageLayout.layout(imagePixelSize: CGSize(width: 1000, height: 700), screen: Self.external))
        #expect(Self.external.frame.contains(layout.imageRect))
        #expect(abs(layout.imageRect.midX - Self.external.frame.midX) <= 0.5)
        #expect(onGrid(layout.imageRect, Self.external))
    }

    @Test("无效输入返回 nil；屏幕太矮时退回屏幕中间一半")
    func invalidAndShortScreens() throws {
        #expect(HistoryImageLayout.layout(imagePixelSize: .zero, screen: Self.screen) == nil)
        let flat = CaptureScreen(id: 3, frame: CGRect(x: 0, y: 0, width: 800, height: 300), scale: 1)
        #expect(
            HistoryImageLayout.layout(imagePixelSize: CGSize(width: 10, height: 10), screen: flat.withScale(0)) == nil)
        let layout = try #require(
            HistoryImageLayout.layout(imagePixelSize: CGSize(width: 1000, height: 1000), screen: flat))
        #expect(layout.imageRect.minY >= 75 - 0.5 && layout.imageRect.maxY <= 225 + 0.5)
    }

    @Test("原生倍率与导出矩形：导出恰好是原图像素尺寸（倍率不是整数）")
    func nativeExport() throws {
        let pixels = CGSize(width: 1601, height: 997)
        let layout = try #require(HistoryImageLayout.layout(imagePixelSize: pixels, screen: Self.screen))
        #expect(layout.nativeRect.origin == layout.imageRect.origin)
        #expect(layout.nativeRect.width == layout.imageRect.width)
        #expect(abs(layout.nativeRect.height - layout.imageRect.height) < 1)
        let native = CaptureScreen(id: 1, frame: layout.nativeRect, scale: layout.nativeScale)
        let image = TestImage.coordinates(width: Int(pixels.width), height: Int(pixels.height))
        let rectangle = Annotation(
            shape: .rectangle(layout.imageRect.insetBy(dx: 40, dy: 40)),
            style: AnnotationStyle(color: .red, weight: .regular))
        let export = try ScreenshotExporter.export(
            frame: FrozenFrame(screen: native, image: image),
            selection: layout.nativeRect,
            document: AnnotationDocument.empty.adding(rectangle),
            pixelatedFrame: nil,
            pngScale: 2
        )
        #expect(export.pixelSize == pixels)
        #expect(export.image.width == Int(pixels.width) && export.image.height == Int(pixels.height))
        #expect(ExportFixtures.dpi(of: export.png)?.width == 144)
    }
}

extension CaptureScreen {
    fileprivate func withScale(_ scale: CGFloat) -> CaptureScreen {
        CaptureScreen(id: id, frame: frame, scale: scale)
    }
}
