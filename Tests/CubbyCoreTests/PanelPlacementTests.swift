import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("PanelPlacement 面板定位")
struct PanelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 300, height: 400)

    @Test("默认放在鼠标右下方")
    func defaultsToBottomRight() {
        let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: 100, y: 700), visibleFrame: screen)
        #expect(frame == CGRect(x: 112, y: 288, width: 300, height: 400))
    }

    @Test("右侧放不下时翻转到鼠标左侧")
    func flipsLeftOnRightOverflow() {
        let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: 900, y: 700), visibleFrame: screen)
        #expect(frame == CGRect(x: 588, y: 288, width: 300, height: 400))
    }

    @Test("下方放不下时翻转到鼠标上方")
    func flipsUpOnBottomOverflow() {
        let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: 100, y: 200), visibleFrame: screen)
        #expect(frame == CGRect(x: 112, y: 212, width: 300, height: 400))
    }

    @Test("右下角同时溢出时翻转到左上")
    func flipsBothDirections() {
        let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: 900, y: 200), visibleFrame: screen)
        #expect(frame == CGRect(x: 588, y: 212, width: 300, height: 400))
    }

    @Test("恰好贴边时不翻转")
    func exactFitDoesNotFlip() {
        // 700 + 300 = 1000 右边缘正好对齐；412 - 12 - 400 = 0 下边缘正好对齐
        let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: 688, y: 412), visibleFrame: screen)
        #expect(frame == CGRect(x: 700, y: 0, width: 300, height: 400))
    }

    @Test("尺寸大于可见区域时被夹紧到可见区域")
    func clampsOversizedPanel() {
        let frame = PanelPlacement.frame(
            size: CGSize(width: 2000, height: 2000),
            mouse: CGPoint(x: 500, y: 400),
            visibleFrame: screen
        )
        #expect(frame == screen)
    }

    @Test("翻转后仍越界时被夹回可见区域")
    func clampsAfterFlip() {
        let tall = CGSize(width: 300, height: 700)
        let frame = PanelPlacement.frame(size: tall, mouse: CGPoint(x: 100, y: 300), visibleFrame: screen)
        #expect(frame == CGRect(x: 112, y: 100, width: 300, height: 700))
    }

    @Test("非零原点的副屏同样正确计算")
    func secondaryScreenWithOffsetOrigin() {
        let secondary = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: -200, y: 300), visibleFrame: secondary)
        // 右侧放不下 → 左翻；下方放不下 → 上翻
        #expect(frame == CGRect(x: -512, y: 312, width: 300, height: 400))
        #expect(secondary.contains(frame))
    }

    @Test("自定义偏移量")
    func customOffset() {
        let frame = PanelPlacement.frame(
            size: size, mouse: CGPoint(x: 100, y: 700), visibleFrame: screen, offset: 0
        )
        #expect(frame == CGRect(x: 100, y: 300, width: 300, height: 400))
    }

    @Test("鼠标在任意位置（含屏幕外）时面板都完整位于可见区域内")
    func alwaysInsideVisibleFrame() {
        let xs = stride(from: -100.0, through: 1100.0, by: 50.0)
        let ys = stride(from: -100.0, through: 900.0, by: 50.0)
        for x in xs {
            for y in ys {
                let frame = PanelPlacement.frame(size: size, mouse: CGPoint(x: x, y: y), visibleFrame: screen)
                #expect(screen.contains(frame), "mouse=(\(x), \(y)) frame=\(String(describing: frame))")
                #expect(frame.size == size)
            }
        }
    }
}
