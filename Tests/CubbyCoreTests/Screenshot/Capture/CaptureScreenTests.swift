import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("CaptureScreen 点与像素换算")
struct CaptureScreenTests {
    private let primary = CaptureFixtures.primary
    private let external = CaptureFixtures.external

    @Test("pixelSize = frame 尺寸 × scale")
    func pixelSize() {
        #expect(primary.pixelSize == CGSize(width: 2880, height: 1800))
        #expect(external.pixelSize == CGSize(width: 1920, height: 1080))
    }

    @Test("非整数缩放时 pixelSize 四舍五入")
    func pixelSizeRoundsFractionalScale() {
        let screen = CaptureScreen(id: 3, frame: CGRect(x: 0, y: 0, width: 1001, height: 501), scale: 1.5)
        #expect(screen.pixelSize == CGSize(width: 1502, height: 752))
    }

    @Test("id 即 Identifiable 的标识")
    func identifiable() {
        #expect(primary.id == 1)
        #expect(Set([primary, external, primary]).count == 2)
    }

    @Test("全局点 → 屏幕局部点（含负坐标外接屏）")
    func localPoint() {
        #expect(primary.localPoint(CGPoint(x: 10, y: 20)) == CGPoint(x: 10, y: 20))
        #expect(external.localPoint(CGPoint(x: 1440, y: -180)) == .zero)
        #expect(external.localPoint(CGPoint(x: 1500.5, y: -100)) == CGPoint(x: 60.5, y: 80))
    }

    @Test(
        "全局点 → 像素点：× scale 后向下取整",
        arguments: [
            (CGPoint(x: 10, y: 20), CGPoint(x: 20, y: 40)),
            (CGPoint(x: 10.3, y: 20.7), CGPoint(x: 20, y: 41)),
            (CGPoint(x: 0.24, y: 0.49), CGPoint(x: 0, y: 0)),
        ]
    )
    func pixelPointOnRetina(global: CGPoint, expected: CGPoint) {
        #expect(primary.pixelPoint(global) == expected)
    }

    @Test("1x 负坐标屏的像素点")
    func pixelPointOnExternal() {
        #expect(external.pixelPoint(CGPoint(x: 1441.9, y: -179.1)) == CGPoint(x: 1, y: 0))
        #expect(external.pixelPoint(CGPoint(x: 1439.5, y: -180)) == CGPoint(x: -1, y: 0))
    }

    @Test("pixelRect：× scale 后向外取整")
    func pixelRectIntegral() {
        let rect = primary.pixelRect(CGRect(x: 10.25, y: 20.3, width: 100.1, height: 50))
        // 20.5 → 20，40.6 → 40；右边 (10.25 + 100.1) × 2 = 220.7 → 221；下边 (20.3 + 50) × 2 = 140.6 → 141
        #expect(rect == CGRect(x: 20, y: 40, width: 201, height: 101))
    }

    @Test("pixelRect 与帧相交，不超出像素范围")
    func pixelRectClampedToFrame() {
        let rect = primary.pixelRect(CGRect(x: -10, y: 800, width: 100, height: 200))
        #expect(rect == CGRect(x: 0, y: 1600, width: 180, height: 200))
    }

    @Test("负坐标外接屏的 pixelRect")
    func pixelRectOnExternal() {
        let rect = external.pixelRect(CGRect(x: 1540, y: -80, width: 300, height: 200))
        #expect(rect == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test("完全在屏外的 pixelRect 为空")
    func pixelRectOutsideIsEmpty() {
        let rect = primary.pixelRect(CGRect(x: 2000, y: 0, width: 10, height: 10))
        #expect(rect.isEmpty)
        #expect(rect == .zero)
    }

    @Test("contains：左 / 上边缘包含，右 / 下边缘不含")
    func containsEdges() {
        #expect(primary.contains(CGPoint(x: 0, y: 0)))
        #expect(primary.contains(CGPoint(x: 1439.9, y: 899.9)))
        #expect(!primary.contains(CGPoint(x: 1440, y: 10)))
        #expect(!primary.contains(CGPoint(x: 10, y: 900)))
        #expect(!primary.contains(CGPoint(x: -0.1, y: 10)))
        #expect(external.contains(CGPoint(x: 1440, y: -180)))
        #expect(!external.contains(CGPoint(x: 1440, y: 900)))
    }
}
