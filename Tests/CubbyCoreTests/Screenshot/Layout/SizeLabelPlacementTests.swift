import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("SizeLabelPlacement 尺寸标签")
struct SizeLabelPlacementTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let label = CGSize(width: 80, height: 20)

    private func layout(_ selection: CGRect, screen: CGRect = screen) -> SizeLabelLayout {
        SizeLabelPlacement.layout(labelSize: Self.label, selection: selection, screen: screen)
    }

    @Test("默认在选区左上角外侧上方 8 pt（离角手柄留出放大后的余量，评审 P2-1）")
    func aboveOutside() {
        #expect(SizeLabelPlacement.defaultGap == 8)
        let result = layout(CGRect(x: 200, y: 150, width: 560, height: 370))
        #expect(result == SizeLabelLayout(frame: CGRect(x: 200, y: 122, width: 80, height: 20), side: .aboveOutside))
    }

    @Test("上方放不下时放到选区下方外侧")
    func belowOutside() {
        let result = layout(CGRect(x: 200, y: 10, width: 560, height: 370))
        #expect(result == SizeLabelLayout(frame: CGRect(x: 200, y: 388, width: 80, height: 20), side: .belowOutside))
    }

    @Test("上下都放不下时放在内侧左上 8 pt")
    func inside() {
        let result = layout(Self.screen)
        #expect(result == SizeLabelLayout(frame: CGRect(x: 8, y: 8, width: 80, height: 20), side: .inside))
    }

    @Test("恰好放得下时仍在上方")
    func exactFitAbove() {
        let result = layout(CGRect(x: 200, y: 28, width: 100, height: 100))
        #expect(result.side == .aboveOutside)
        #expect(result.frame.minY == 0)
    }

    @Test("贴右边缘时水平夹紧在屏幕内")
    func clampsHorizontally() {
        let result = layout(CGRect(x: 1400, y: 150, width: 40, height: 40))
        #expect(result.frame == CGRect(x: 1360, y: 122, width: 80, height: 20))
    }

    @Test("极小选区标签在外侧")
    func tinySelectionOutside() {
        let result = layout(CGRect(x: 300, y: 300, width: 12, height: 10))
        #expect(result.side == .aboveOutside)
    }

    @Test("自定义间距")
    func customGap() {
        let result = SizeLabelPlacement.layout(
            labelSize: Self.label, selection: CGRect(x: 200, y: 150, width: 100, height: 100), screen: Self.screen,
            gap: 10)
        #expect(result.frame.minY == 120)
    }

    @Test(
        "文本为像素尺寸（点 × 缩放，四舍五入）",
        arguments: [
            (CGRect(x: 0, y: 0, width: 640, height: 360), CGFloat(2), "1280 × 720"),
            (CGRect(x: 0, y: 0, width: 100, height: 50), CGFloat(1), "100 × 50"),
            (CGRect(x: 0, y: 0, width: 10.25, height: 10.75), CGFloat(2), "21 × 22"),
            (CGRect(x: 0, y: 0, width: 33.3, height: 20), CGFloat(1.5), "50 × 30"),
        ])
    func text(_ selection: CGRect, _ scale: CGFloat, _ expected: String) {
        #expect(SizeLabelPlacement.text(for: selection, scale: scale) == expected)
    }

    @Test(
        "标签像素尺寸与 CaptureScreen.pixelRect（导出所用）一致，含小数坐标",
        arguments: [
            (CGRect(x: 10.3, y: 20.2, width: 5, height: 5), CGFloat(2)),
            (CGRect(x: 0.25, y: 0.75, width: 3.3, height: 7.9), CGFloat(2)),
            (CGRect(x: 10.4, y: 20.6, width: 7.5, height: 9.6), CGFloat(1)),
            (CGRect(x: 100, y: 50, width: 640, height: 360), CGFloat(2)),
        ])
    func textMatchesPixelRect(_ selection: CGRect, _ scale: CGFloat) {
        let screen = CaptureScreen(id: 0, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: scale)
        let pixels = screen.pixelRect(selection).size
        #expect(SizeLabelPlacement.text(for: selection, scale: scale) == "\(Int(pixels.width)) × \(Int(pixels.height))")
    }
}
