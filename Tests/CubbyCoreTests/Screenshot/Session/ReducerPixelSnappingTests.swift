import CoreGraphics
import Darwin
import Testing
@testable import CubbyCore

/// 选区吸附到像素网格：尺寸标签的数值必须与导出 PNG 的像素尺寸一致
@Suite("ScreenshotReducer · 选区吸附像素网格")
struct ReducerPixelSnappingTests {
    private static let retina = ExportFixtures.retina
    private static let external = ExportFixtures.external
    /// 小数坐标的窗口（@2x 屏）
    private static let fractional = WindowCandidate(
        id: 1, frame: CGRect(x: 10.25, y: 10.75, width: 50.5, height: 30.25), layer: 0, ownerPID: 1, alpha: 1)
    /// 只有 2 pt 落在 @2x 屏右缘的窗口
    private static let sliver = WindowCandidate(
        id: 2, frame: CGRect(x: 98, y: 5, width: 300, height: 20), layer: 0, ownerPID: 1, alpha: 1)
    /// 只有 2 pt 落在 @1x 外接屏左缘的窗口
    private static let externalSliver = WindowCandidate(
        id: 3, frame: CGRect(x: 1300, y: -100, width: 142, height: 30), layer: 0, ownerPID: 1, alpha: 1)
    private static let topology = ScreenTopology(
        screens: [retina, external], windows: [fractional, sliver, externalSliver], ownPID: 999)

    /// 按住 ⌘ 关闭选区边缘磁吸：这里只验证像素网格吸附（小数窗口的边缘就在拖拽点旁边，磁吸会改变结果）
    private func start(at cursor: CGPoint = CGPoint(x: 90, y: 70)) -> SessionHarness {
        SessionHarness.hovering(at: cursor, topology: Self.topology).modifiers(.command)
    }

    /// 选区四边乘以缩放都是整数
    private func isOnPixelGrid(_ rect: CGRect?, scale: CGFloat) -> Bool {
        guard let rect else { return false }
        return [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { ($0 * scale).rounded() == $0 * scale }
    }

    /// 尺寸标签文本与导出 PNG 的像素尺寸一致
    private func labelMatchesExport(_ session: ScreenshotSession, screen: CaptureScreen) throws -> Bool {
        let selection = try #require(session.selection)
        let export = try ScreenshotExporter.export(
            frame: ExportFixtures.frame(screen), selection: selection, document: .empty, pixelatedFrame: nil)
        let exported = "\(Int(export.pixelSize.width)) × \(Int(export.pixelSize.height))"
        return SizeLabelPlacement.text(for: selection, scale: screen.scale) == exported
    }

    @Test("@2x：小数坐标拖出的选区吸附到半点网格，标签 == 导出尺寸")
    func retinaDrag() throws {
        let result = start().drag(from: CGPoint(x: 10.3, y: 20.2), to: CGPoint(x: 15.3, y: 25.2))
        #expect(result.session.selection == CGRect(x: 10.5, y: 20, width: 5, height: 5))
        #expect(result.session.phase == .adjusting)
        #expect(try labelMatchesExport(result.session, screen: Self.retina))
    }

    @Test("@1x（负坐标外接屏）：原点吸附到最近的像素、尺寸四舍五入到整像素")
    func externalDrag() throws {
        let result = start().drag(from: CGPoint(x: 1450.4, y: -170.4), to: CGPoint(x: 1457.9, y: -160.8))
        // 7.5 × 9.6 pt → 8 × 10 px
        #expect(result.session.selection == CGRect(x: 1450, y: -170, width: 8, height: 10))
        #expect(try labelMatchesExport(result.session, screen: Self.external))
    }

    @Test("@1x 上 ⇧ 拖边手柄产生的 .5 被吸附")
    func squareEdgeResizeSnaps() throws {
        let adjusting = start().drag(from: CGPoint(x: 1450, y: -170), to: CGPoint(x: 1490, y: -130))
        let result = adjusting.modifiers([.shift, .command]).drag(
            from: CGPoint(x: 1490, y: -150), to: CGPoint(x: 1495, y: -150))
        #expect(result.session.selection == CGRect(x: 1450, y: -172, width: 45, height: 45))
        #expect(try labelMatchesExport(result.session, screen: Self.external))
    }

    @Test("@2x：按小数位移移动选区后仍在网格上")
    func moveSnaps() throws {
        let adjusting = start().drag(from: CGPoint(x: 10.3, y: 20.2), to: CGPoint(x: 40.3, y: 50.2))
        #expect(adjusting.session.selection == CGRect(x: 10.5, y: 20, width: 30, height: 30))
        let result = adjusting.drag(from: CGPoint(x: 25, y: 35), to: CGPoint(x: 29.3, y: 35.7))
        #expect(result.session.selection == CGRect(x: 15, y: 20.5, width: 30, height: 30))
        #expect(try labelMatchesExport(result.session, screen: Self.retina))
    }

    @Test("⇧ 拖出的正方形在小数坐标下吸附后仍是正方形")
    func squareStaysSquare() {
        let result = start().modifiers([.shift, .command]).drag(
            from: CGPoint(x: 10.3, y: 20.2), to: CGPoint(x: 40.6, y: 70.9))
        let selection = result.session.selection
        #expect(selection?.width == selection?.height)
        #expect(isOnPixelGrid(selection, scale: 2))
    }

    @Test("拖左边手柄时右边保持不动")
    func leftEdgeResizeKeepsRightEdge() {
        let adjusting = start().drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 60))
        let result = adjusting.drag(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 25.3, y: 40))
        #expect(result.session.selection == CGRect(x: 25.5, y: 20, width: 54.5, height: 40))
    }

    @Test("单击小数坐标的窗口：选区吸附")
    func clickFractionalWindow() throws {
        let result = start().click(CGPoint(x: 30, y: 30))
        #expect(result.session.selection == CGRect(x: 10.5, y: 11, width: 50.5, height: 30.5))
        #expect(try labelMatchesExport(result.session, screen: Self.retina))
    }

    @Test(
        "一组小数坐标的拖拽：选区总在网格上、标签 == 导出尺寸",
        arguments: [
            (CGPoint(x: 1.1, y: 2.2), CGPoint(x: 33.33, y: 44.44)),
            (CGPoint(x: 70.7, y: 60.6), CGPoint(x: 20.25, y: 5.75)),
            (CGPoint(x: 50.49, y: 40.51), CGPoint(x: 99.99, y: 79.99)),
            (CGPoint(x: 1500.5, y: -100.5), CGPoint(x: 1455.25, y: -170.75)),
        ])
    func dragsStayOnGrid(_ from: CGPoint, _ to: CGPoint) throws {
        let result = start().drag(from: from, to: to)
        let screen = from.x >= Self.external.frame.minX ? Self.external : Self.retina
        #expect(isOnPixelGrid(result.session.selection, scale: screen.scale))
        #expect(try labelMatchesExport(result.session, screen: screen))
    }

    @Test("跨屏窗口只有 2 pt 落在当前屏：单击得到的选区至少 minSize，且仍在屏幕内")
    func sliverWindowGetsMinimumSize() {
        let retina = start().click(CGPoint(x: 99, y: 10))
        #expect(retina.session.selection == CGRect(x: 96, y: 5, width: 4, height: 20))
        let external = start().click(CGPoint(x: 1441, y: -95))
        #expect(external.session.selection == CGRect(x: 1440, y: -100, width: 4, height: 10))
        let confirmed = start(at: CGPoint(x: 99, y: 10)).send(.command(.confirm))
        #expect(confirmed.session.selection == CGRect(x: 96, y: 5, width: 4, height: 20))
    }
}
