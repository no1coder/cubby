import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotInput 滚轮换算与光标种类")
struct ScreenshotInputTests {
    // MARK: - 滚轮

    @Test("触控板直接用点数；惯性阶段丢弃；行式滚轮按每行 40 pt 换算")
    func scrollDelta() {
        #expect(ScreenshotInput.scrollDelta(scrollingDeltaY: -3.5, isPrecise: true, isMomentum: false) == -3.5)
        #expect(ScreenshotInput.scrollDelta(scrollingDeltaY: -3.5, isPrecise: true, isMomentum: true) == nil)
        #expect(ScreenshotInput.scrollDelta(scrollingDeltaY: 1, isPrecise: false, isMomentum: false) == 40)
        #expect(ScreenshotInput.scrollDelta(scrollingDeltaY: 0, isPrecise: true, isMomentum: false) == 0)
    }

    // MARK: - 光标

    private typealias Fixture = TopologyFixture

    @Test("悬停与框选：十字；窗口模式：相机")
    func hoverCursor() {
        let hovering = SessionHarness.hovering()
        #expect(hovering.session.cursorKind == .crosshair)
        let selecting = hovering.press(CGPoint(x: 300, y: 300), dragTo: CGPoint(x: 400, y: 400))
        #expect(selecting.session.cursorKind == .crosshair)
        let window = SessionHarness.hovering(at: Fixture.editorPoint)
            .send(.modifiersChanged(.space), .modifiersChanged([]))
        #expect(window.session.isWindowCaptureMode)
        #expect(window.session.cursorKind == .camera)
    }

    @Test("手柄上为对应方向的缩放；选区内为移动；选区外为十字")
    func adjustingCursor() {
        let adjusting = SessionHarness.adjusting()
        let selection = adjusting.session.selection ?? .zero
        for handle in SelectionHandle.allCases {
            let moved = adjusting.send(.mouseMoved(handle.center(in: selection)))
            #expect(moved.session.cursorKind == .resize(handle))
            #expect(moved.session.activeHandle == handle)
        }
        #expect(adjusting.send(.mouseMoved(CGPoint(x: 480, y: 330))).session.cursorKind == .move)
        #expect(adjusting.send(.mouseMoved(CGPoint(x: 1000, y: 800))).session.cursorKind == .crosshair)
    }

    @Test("annotating：文字工具 I 形，其他工具十字；手柄优先")
    func annotatingCursor() {
        let inside = CGPoint(x: 480, y: 330)
        #expect(SessionHarness.annotating(.text).send(.mouseMoved(inside)).session.cursorKind == .iBeam)
        #expect(SessionHarness.annotating(.pen).send(.mouseMoved(inside)).session.cursorKind == .crosshair)
        let corner = CGPoint(x: 200, y: 150)
        #expect(SessionHarness.annotating(.pen).send(.mouseMoved(corner)).session.cursorKind == .resize(.topLeft))
    }

    @Test("选区外的标注可以拖动：移动光标")
    func annotationCursor() {
        let drawn = SessionHarness.adjusting().drawingRectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
            .send(.command(.selectTool(.pointer)))
        #expect(drawn.send(.mouseMoved(CGPoint(x: 300, y: 350))).session.cursorKind == .move)
    }

    @Test("拖动中按拖拽类型：缩放手柄 / 移动 / 绘制")
    func dragCursor() {
        let adjusting = SessionHarness.adjusting()
        let resizing = adjusting.press(CGPoint(x: 760, y: 520), dragTo: CGPoint(x: 800, y: 560))
        #expect(resizing.session.cursorKind == .resize(.bottomRight))
        #expect(resizing.session.activeHandle == .bottomRight)
        let moving = adjusting.press(CGPoint(x: 480, y: 330), dragTo: CGPoint(x: 500, y: 360))
        #expect(moving.session.cursorKind == .move)
        #expect(moving.session.activeHandle == nil)
        let drawing = SessionHarness.annotating(.rectangle).press(
            CGPoint(x: 300, y: 300), dragTo: CGPoint(x: 360, y: 360))
        #expect(drawing.session.cursorKind == .crosshair)
    }

    @Test("编辑文字：编辑框外为箭头")
    func editingCursor() {
        let editing = SessionHarness.annotating(.text).click(CGPoint(x: 300, y: 300))
        #expect(editing.session.phase == .editingText)
        #expect(editing.session.cursorKind == .arrow)
    }
}
