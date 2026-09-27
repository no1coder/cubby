import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("PanelPlacement 锚点下方 / 居中 / 侧边定位")
struct PanelPlacementAnchorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 300, height: 400)

    // MARK: - frame(size:below:)

    @Test("放在锚点正下方并水平居中，默认间距 6")
    func belowAnchorCentered() {
        let anchor = CGRect(x: 500, y: 780, width: 30, height: 20)
        let frame = PanelPlacement.frame(size: size, below: anchor, visibleFrame: screen)
        // x = 515 - 150；y = 780 - 6 - 400
        #expect(frame == CGRect(x: 365, y: 374, width: 300, height: 400))
    }

    @Test("自定义间距")
    func belowAnchorCustomGap() {
        let anchor = CGRect(x: 500, y: 780, width: 30, height: 20)
        let frame = PanelPlacement.frame(size: size, below: anchor, visibleFrame: screen, gap: 0)
        #expect(frame.maxY == anchor.minY)
    }

    @Test(
        "锚点靠近右 / 左边缘时水平方向被夹回可见区域",
        arguments: [
            (CGFloat(990), CGFloat(700)),
            (CGFloat(-20), CGFloat(0)),
        ])
    func belowAnchorClampsHorizontally(_ anchorX: CGFloat, _ expectedX: CGFloat) {
        let anchor = CGRect(x: anchorX, y: 780, width: 20, height: 20)
        let frame = PanelPlacement.frame(size: size, below: anchor, visibleFrame: screen)
        #expect(frame.minX == expectedX)
        #expect(screen.contains(frame))
    }

    @Test("锚点下方空间不足时贴住可见区域底部")
    func belowAnchorClampsVertically() {
        let anchor = CGRect(x: 500, y: 200, width: 30, height: 20)
        let frame = PanelPlacement.frame(size: size, below: anchor, visibleFrame: screen)
        #expect(frame.minY == 0)
        #expect(frame.size == size)
    }

    @Test("尺寸超过可见区域时缩小到可见区域")
    func belowAnchorOversized() {
        let anchor = CGRect(x: 500, y: 780, width: 30, height: 20)
        let frame = PanelPlacement.frame(size: CGSize(width: 5000, height: 5000), below: anchor, visibleFrame: screen)
        #expect(frame == screen)
    }

    // MARK: - centered

    @Test("居中并略偏上（高度的 8%）")
    func centeredSlightlyAbove() {
        let frame = PanelPlacement.centered(size: size, in: screen)
        // x = 500 - 150；y = 400 - 200 + 64
        #expect(frame == CGRect(x: 350, y: 264, width: 300, height: 400))
    }

    @Test("非零原点的副屏同样居中")
    func centeredOnSecondaryScreen() {
        let secondary = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let frame = PanelPlacement.centered(size: size, in: secondary)
        #expect(frame == CGRect(x: -870, y: 422, width: 300, height: 400))
        #expect(secondary.contains(frame))
    }

    @Test("接近满高时上移量被夹回，不超出顶部")
    func centeredClampsTop() {
        let tall = CGSize(width: 300, height: 780)
        let frame = PanelPlacement.centered(size: tall, in: screen)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.minY == 20)
    }

    @Test("尺寸超过可见区域时等于可见区域")
    func centeredOversized() {
        #expect(PanelPlacement.centered(size: CGSize(width: 3000, height: 3000), in: screen) == screen)
    }

    // MARK: - frame(size:beside:)

    @Test("优先放在宿主左侧，高度与宿主一致且顶部对齐")
    func besidePrefersLeft() {
        let host = CGRect(x: 600, y: 200, width: 300, height: 400)
        let frame = PanelPlacement.frame(size: CGSize(width: 250, height: 999), beside: host, visibleFrame: screen)
        // x = 600 - 8 - 250
        #expect(frame == CGRect(x: 342, y: 200, width: 250, height: 400))
        #expect(frame.maxY == host.maxY)
        #expect(frame.maxX + 8 == host.minX)
    }

    @Test("左侧恰好放得下时仍放左侧")
    func besideExactLeftFit() {
        let host = CGRect(x: 258, y: 100, width: 300, height: 400)
        let frame = PanelPlacement.frame(size: CGSize(width: 250, height: 100), beside: host, visibleFrame: screen)
        #expect(frame.minX == 0)
    }

    @Test("左侧放不下时放到右侧")
    func besideFallsBackToRight() {
        let host = CGRect(x: 100, y: 200, width: 300, height: 400)
        let frame = PanelPlacement.frame(size: CGSize(width: 250, height: 100), beside: host, visibleFrame: screen)
        #expect(frame == CGRect(x: 408, y: 200, width: 250, height: 400))
    }

    @Test("左右都放不下时夹回可见区域（允许与宿主重叠）")
    func besideNoRoomClamps() {
        let host = CGRect(x: 50, y: 0, width: 900, height: 400)
        let frame = PanelPlacement.frame(size: CGSize(width: 250, height: 100), beside: host, visibleFrame: screen)
        #expect(frame == CGRect(x: 750, y: 0, width: 250, height: 400))
        #expect(screen.contains(frame))
    }

    @Test("自定义间距")
    func besideCustomGap() {
        let host = CGRect(x: 600, y: 200, width: 300, height: 400)
        let frame = PanelPlacement.frame(
            size: CGSize(width: 250, height: 1), beside: host, visibleFrame: screen, gap: 20)
        #expect(frame.minX == 330)
    }

    @Test("宽度超过可见区域时缩到可见区域宽度")
    func besideOversizedWidth() {
        let host = CGRect(x: 600, y: 200, width: 300, height: 400)
        let frame = PanelPlacement.frame(size: CGSize(width: 5000, height: 1), beside: host, visibleFrame: screen)
        #expect(frame.width == screen.width)
        #expect(frame.height == host.height)
        #expect(screen.contains(frame))
    }

    @Test("副屏（负坐标原点）上优先左侧")
    func besideOnSecondaryScreen() {
        let secondary = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let host = CGRect(x: -1000, y: 300, width: 300, height: 400)
        let frame = PanelPlacement.frame(size: CGSize(width: 250, height: 1), beside: host, visibleFrame: secondary)
        #expect(frame == CGRect(x: -1258, y: 300, width: 250, height: 400))
    }

    @Test("宿主位于可见区域内任意位置时，侧边面板都完整可见且顶部对齐")
    func besideAlwaysInside() {
        let hostSize = CGSize(width: 300, height: 400)
        for x in stride(from: 0.0, through: 700.0, by: 50.0) {
            for y in stride(from: 0.0, through: 400.0, by: 50.0) {
                let host = CGRect(origin: CGPoint(x: x, y: y), size: hostSize)
                let frame = PanelPlacement.frame(
                    size: CGSize(width: 250, height: 10), beside: host, visibleFrame: screen)
                #expect(screen.contains(frame), "host=\(String(describing: host))")
                #expect(frame.maxY == host.maxY)
            }
        }
    }
}
