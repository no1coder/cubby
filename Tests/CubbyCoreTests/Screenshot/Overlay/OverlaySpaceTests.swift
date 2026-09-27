import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("OverlaySpace 覆盖层坐标换算与像素对齐")
struct OverlaySpaceTests {
    private static let retina = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    /// 外接屏在主屏左上方的负坐标
    private static let external = CaptureScreen(
        id: 2, frame: CGRect(x: -1920, y: -300, width: 1920, height: 1080), scale: 1)
    private static let triple = CaptureScreen(id: 3, frame: CGRect(x: 1440, y: 0, width: 800, height: 600), scale: 3)

    @Test("全局点 ↔ 视图点（翻转视图：减去屏幕原点）")
    func viewPoints() {
        let space = OverlaySpace(screen: Self.external)
        let global = CGPoint(x: -1900, y: -280)
        #expect(space.viewPoint(global) == CGPoint(x: 20, y: 20))
        #expect(space.globalPoint(fromView: CGPoint(x: 20, y: 20)) == global)
        let rect = CGRect(x: -1800, y: -200, width: 100, height: 50)
        #expect(space.viewRect(rect) == CGRect(x: 120, y: 100, width: 100, height: 50))
        #expect(space.globalRect(fromView: space.viewRect(rect)) == rect)
    }

    @Test("视图矩形先标准化（负尺寸）")
    func viewRectStandardizes() {
        let space = OverlaySpace(screen: Self.retina)
        let flipped = CGRect(x: 300, y: 200, width: -100, height: -50)
        #expect(space.viewRect(flipped) == CGRect(x: 200, y: 150, width: 100, height: 50))
    }

    @Test("图层坐标 y 向上：以屏幕高度翻转")
    func layerCoordinates() {
        let space = OverlaySpace(screen: Self.retina)
        #expect(space.layerPoint(CGPoint(x: 10, y: 0)) == CGPoint(x: 10, y: 900))
        #expect(space.layerPoint(CGPoint(x: 10, y: 900)) == CGPoint(x: 10, y: 0))
        let rect = CGRect(x: 100, y: 100, width: 200, height: 300)
        #expect(space.layerRect(rect) == CGRect(x: 100, y: 500, width: 200, height: 300))
    }

    @Test("向外取整到设备像素，与导出的 pixelRect 同一口径", arguments: [retina, external, triple])
    func pixelAlignedMatchesExport(screen: CaptureScreen) {
        let space = OverlaySpace(screen: screen)
        let rect = CGRect(
            x: screen.frame.minX + 10.3, y: screen.frame.minY + 20.7, width: 100.26, height: 50.49)
        let aligned = space.pixelAligned(rect)
        #expect(aligned.contains(rect))
        let pixels = screen.pixelRect(aligned)
        #expect(pixels == screen.pixelRect(rect))
        // 像素化后的边界正好落在像素上
        for value in [aligned.minX, aligned.minY, aligned.maxX, aligned.maxY] {
            let local = value * screen.scale
            #expect(abs(local - local.rounded()) < 1e-6)
        }
    }

    @Test("pixelRounded 四舍五入到设备像素")
    func pixelRounded() {
        #expect(OverlaySpace(screen: Self.retina).pixelRounded(10.3) == 10.5)
        #expect(OverlaySpace(screen: Self.retina).pixelRounded(10.2) == 10)
        #expect(OverlaySpace(screen: Self.external).pixelRounded(10.6) == 11)
    }

    @Test("描边中心：奇数像素宽的线落在半像素上，偶数宽落在整像素上")
    func strokeCenter() {
        // 1x：1 pt = 1 px（奇数）→ 中心 .5
        #expect(OverlaySpace(screen: Self.external).strokeCenter(10.2, width: 1) == 10.5)
        // 2x：1 pt = 2 px（偶数）→ 中心在整像素
        #expect(OverlaySpace(screen: Self.retina).strokeCenter(10.2, width: 1) == 10)
        // 2x：1.5 pt = 3 px（奇数）→ 中心在半像素（0.25 pt）
        #expect(OverlaySpace(screen: Self.retina).strokeCenter(10.2, width: 1.5) == 10.25)
        // 3x：1 pt = 3 px（奇数）
        let center = OverlaySpace(screen: Self.triple).strokeCenter(10, width: 1)
        #expect(abs(center * 3 - (center * 3).rounded(.down) - 0.5) < 1e-9)
    }

    @Test("与屏幕相交判定：空矩形与 null 不相交")
    func intersects() {
        let space = OverlaySpace(screen: Self.retina)
        #expect(space.intersects(CGRect(x: 1400, y: 800, width: 100, height: 200)))
        #expect(!space.intersects(CGRect(x: 1500, y: 0, width: 10, height: 10)))
        #expect(!space.intersects(.null))
    }
}
