import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotDebugScenario 调试场景预置会话")
struct ScreenshotDebugScenarioTests {
    private typealias Fixture = TopologyFixture
    private let standard = CGRect(x: 200, y: 150, width: 560, height: 370)

    private func scenario(_ name: String, topology: ScreenTopology = Fixture.twoScreens) -> ScreenshotSession? {
        ScreenshotDebugScenario.session(named: name, topology: topology, styles: .default)
    }

    @Test(
        "每个场景名返回非 nil 且阶段正确",
        arguments: [
            ("hovering", ScreenshotPhase.hovering),
            ("selecting", .selecting),
            ("adjusting", .adjusting),
            ("annotating", .annotating),
            ("annotating:rectangle", .annotating),
            ("annotating:mosaic", .annotating),
            ("annotating:pointer", .adjusting),
            ("text", .editingText),
            ("tiny", .adjusting),
            ("edge", .adjusting),
            ("fullscreen", .adjusting),
            ("hover-cycle", .hovering),
            ("window-mode", .hovering),
            ("arrow-guide", .annotating),
            ("magnet", .selecting),
            ("shift-line", .annotating),
        ])
    func phases(_ name: String, _ phase: ScreenshotPhase) {
        #expect(scenario(name)?.phase == phase)
    }

    @Test("arrow-guide：正在画的箭头吸附成水平并显示辅助线")
    func arrowGuideScenario() throws {
        let session = try #require(scenario("arrow-guide"))
        #expect(session.arrowSnapGuide != nil)
        guard case .drawing(let annotation) = session.drag, case .arrow(let from, let to) = annotation.shape else {
            Issue.record("应在画箭头")
            return
        }
        #expect(from.y == to.y)
    }

    @Test("shift-line：按住 ⇧ 的画笔只有首尾两点")
    func shiftLineScenario() throws {
        let session = try #require(scenario("shift-line"))
        guard case .drawing(let annotation) = session.drag, case .pen(let points) = annotation.shape else {
            Issue.record("应在画画笔")
            return
        }
        #expect(points.count == 2)
    }

    @Test("magnet：选区左边吸附到最前面窗口的右边")
    func magnetScenario() throws {
        let session = try #require(scenario("magnet"))
        let window = try #require(WindowHitTester.eligibleWindows(in: Fixture.twoScreens).first)
        #expect(session.selection?.minX == window.frame.maxX)
    }

    @Test("未知名称与非会话场景返回 nil", arguments: ["", "bogus", "pin", "permission", "annotating:bogus", "annotating:"])
    func unknownNames(_ name: String) {
        #expect(scenario(name) == nil)
    }

    @Test("没有屏幕时返回 nil")
    func noScreens() {
        #expect(scenario("adjusting", topology: Fixture.empty) == nil)
    }

    @Test("hovering：光标在窗口上")
    func hovering() throws {
        let session = try #require(scenario("hovering"))
        let hover = try #require(session.hover)
        #expect(hover.windowID != nil)
        #expect(hover == WindowHitTester.hoverTarget(at: session.cursor, topology: Fixture.twoScreens))
        let bare = try #require(scenario("hovering", topology: Fixture.noWindows))
        #expect(bare.hover == .screen(Fixture.primary))
    }

    @Test("selecting：拖拽 (200,150)→(760,520) 进行中")
    func selecting() throws {
        let session = try #require(scenario("selecting"))
        #expect(session.selection == standard)
        #expect(session.cursor == CGPoint(x: 760, y: 520))
        #expect(session.drag == .creatingSelection(anchor: CGPoint(x: 200, y: 150), previous: nil))
        #expect(session.screenID == Fixture.primary.id)
        let dragged = ScreenshotReducer.reduce(
            session, event: .mouseDragged(CGPoint(x: 800, y: 600)), topology: Fixture.twoScreens)
        #expect(dragged.session.selection == CGRect(x: 200, y: 150, width: 600, height: 450))
        let released = ScreenshotReducer.reduce(
            dragged.session, event: .mouseUp(CGPoint(x: 800, y: 600)), topology: Fixture.twoScreens)
        #expect(released.session.phase == .adjusting)
    }

    @Test("adjusting：标准选区，工具栏在下方")
    func adjusting() throws {
        let session = try #require(scenario("adjusting"))
        #expect(session.selection == standard)
        #expect(session.screenID == Fixture.primary.id)
        #expect(session.isToolbarVisible)
    }

    @Test("annotating：8 种标注各一 + 序号 1–3，选中箭头，工具为箭头")
    func annotating() throws {
        let session = try #require(scenario("annotating"))
        let document = session.document
        let tools = document.annotations.map { $0.tool }
        #expect(tools == [.rectangle, .ellipse, .arrow, .pen, .highlighter, .mosaic, .text, .number, .number, .number])
        let numbers = document.annotations.filter { $0.tool == .number }.map { document.numberLabel(for: $0.id) }
        #expect(numbers == [1, 2, 3])
        #expect(Set(document.annotations.map { $0.id }).count == document.annotations.count)
        let selected = try #require(session.selectedAnnotation)
        #expect(document.annotation(id: selected)?.tool == .arrow)
        #expect(session.tool == .arrow)
        #expect(session.styleBarTool == .arrow)
    }

    @Test("annotating:<tool>：激活指定工具，不选中标注")
    func annotatingTool() throws {
        for tool in ScreenshotTool.allCases where tool != .pointer {
            let session = try #require(scenario("annotating:\(tool.rawValue)"))
            #expect(session.tool == tool)
            #expect(session.selectedAnnotation == nil)
            #expect(session.styleBarTool == tool)
            #expect(session.document.annotations.count == 10)
        }
        let pointer = try #require(scenario("annotating:pointer"))
        #expect(pointer.tool == .pointer)
    }

    @Test("场景中新增标注的 id 不与预置标注冲突")
    func scenarioContinuesSerial() throws {
        let session = try #require(scenario("annotating:rectangle"))
        let harness = SessionHarness(session: session).drag(from: CGPoint(x: 300, y: 450), to: CGPoint(x: 350, y: 500))
        let ids = harness.session.document.annotations.map { $0.id }
        #expect(ids.count == 11)
        #expect(Set(ids).count == 11)
    }

    @Test("text：文本框编辑中，预填中英文")
    func text() throws {
        let session = try #require(scenario("text"))
        let editing = try #require(session.textEditing)
        #expect(editing.text == "Hello \u{4F60}\u{597D}")
        #expect(editing.existing == nil)
        #expect(editing.maxWidth == standard.maxX - editing.origin.x)
        #expect(session.tool == .text)
        let committed = ScreenshotReducer.reduce(session, event: .command(.escape), topology: Fixture.twoScreens)
        #expect(committed.session.document.annotations.count == 1)
    }

    @Test("tiny / edge / fullscreen 的选区")
    func selections() throws {
        #expect(try #require(scenario("tiny")).selection?.size == CGSize(width: 12, height: 10))
        let edge = try #require(scenario("edge")?.selection)
        #expect(edge.maxX == Fixture.primary.frame.maxX)
        #expect(edge.maxY == Fixture.primary.frame.maxY)
        let layout = ToolbarPlacement.layout(
            toolbarSize: CGSize(width: 520, height: 36), styleBarSize: nil, selection: edge,
            screen: Fixture.primary.frame)
        #expect(layout.side == .above)
        #expect(try #require(scenario("fullscreen")).selection == Fixture.primary.frame)
    }

    @Test("hover-cycle：光标在重叠窗口上，depth = 1")
    func hoverCycle() throws {
        let session = try #require(scenario("hover-cycle"))
        let candidates = WindowHitTester.candidates(at: session.cursor, in: Fixture.twoScreens)
        #expect(candidates.count >= 3)
        #expect(session.hoverDepth == 1)
        #expect(session.hover == candidates[1])
        let tabbed = ScreenshotReducer.reduce(
            session, event: .command(.cycleHover(forward: false)), topology: Fixture.twoScreens)
        #expect(tabbed.session.hover == candidates[0])
        let single = try #require(scenario("hover-cycle", topology: Fixture.singleScreen))
        #expect(single.hover == .screen(Fixture.primary))
        #expect(single.hoverDepth == 1)
    }

    @Test("window-mode：窗口模式开启且目标是窗口；没有窗口时返回 nil")
    func windowMode() throws {
        let session = try #require(scenario("window-mode"))
        #expect(session.isWindowCaptureMode)
        #expect(session.hover?.windowID != nil)
        #expect(!session.isMagnifierVisible)
        #expect(scenario("window-mode", topology: Fixture.noWindows) == nil)
    }

    @Test("样式透传，场景可重复生成")
    func stylesAndDeterminism() {
        let styles = ToolStyles.default.setting(AnnotationStyle(color: .blue, weight: .heavy), for: .arrow)
        let session = ScreenshotDebugScenario.session(named: "annotating", topology: Fixture.twoScreens, styles: styles)
        #expect(session?.styles == styles)
        #expect(scenario("annotating") == scenario("annotating"))
    }

    @Test("场景名列表")
    func names() {
        #expect(ScreenshotDebugScenario.names.contains("hover-cycle"))
        #expect(ScreenshotDebugScenario.names.contains("window-mode"))
        let missing = ScreenshotDebugScenario.names.filter { scenario($0) == nil }
        #expect(missing.isEmpty)
    }
}
