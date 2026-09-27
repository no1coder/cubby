import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("MagnifierPlacement 放大镜摆放")
struct MagnifierPlacementTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let size = CGSize(width: 136, height: 180)

    private func frame(_ cursor: CGPoint, screen: CGRect = screen, size: CGSize = size) -> CGRect {
        MagnifierPlacement.frame(size: size, cursor: cursor, screen: screen)
    }

    @Test(
        "默认右下，溢出时按轴翻转（四角）",
        arguments: [
            (CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 120)),
            (CGPoint(x: 1400, y: 100), CGPoint(x: 1244, y: 120)),
            (CGPoint(x: 100, y: 850), CGPoint(x: 120, y: 650)),
            (CGPoint(x: 1400, y: 850), CGPoint(x: 1244, y: 650)),
            (CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)),
            (CGPoint(x: 1440, y: 0), CGPoint(x: 1284, y: 20)),
            (CGPoint(x: 0, y: 900), CGPoint(x: 20, y: 700)),
            (CGPoint(x: 1440, y: 900), CGPoint(x: 1284, y: 700)),
        ])
    func flipsPerAxis(_ cursor: CGPoint, _ origin: CGPoint) {
        #expect(frame(cursor) == CGRect(origin: origin, size: Self.size))
    }

    @Test("恰好贴边时不翻转")
    func exactFitDoesNotFlip() {
        #expect(frame(CGPoint(x: 1284, y: 700)) == CGRect(x: 1304, y: 720, width: 136, height: 180))
    }

    @Test("翻转后仍溢出时夹紧在屏幕内")
    func clampsAfterFlip() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 300)
        #expect(frame(CGPoint(x: 150, y: 150), screen: small) == CGRect(x: 0, y: 0, width: 136, height: 180))
    }

    @Test("屏幕比放大镜还小时尺寸被夹到屏幕")
    func screenSmallerThanMagnifier() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(frame(CGPoint(x: 50, y: 50), screen: tiny) == tiny)
    }

    @Test("负坐标外接屏与自定义偏移")
    func negativeOriginScreen() {
        let external = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        #expect(
            frame(CGPoint(x: -1900, y: -1070), screen: external) == CGRect(x: -1880, y: -1050, width: 136, height: 180))
        #expect(frame(CGPoint(x: -10, y: -10), screen: external) == CGRect(x: -166, y: -210, width: 136, height: 180))
        let custom = MagnifierPlacement.frame(
            size: Self.size, cursor: CGPoint(x: 100, y: 100), screen: Self.screen, offset: 10)
        #expect(custom.origin == CGPoint(x: 110, y: 110))
    }
}
