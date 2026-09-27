import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenTopology 屏幕与窗口拓扑")
struct ScreenTopologyTests {
    private let topology = CaptureFixtures.topology()

    @Test("按点查找所在屏幕")
    func screenContainingPoint() {
        #expect(topology.screen(containing: CGPoint(x: 100, y: 100)) == CaptureFixtures.primary)
        #expect(topology.screen(containing: CGPoint(x: 1500, y: -100)) == CaptureFixtures.external)
    }

    @Test("屏幕之间的空隙返回 nil")
    func gapReturnsNil() {
        // 主屏高 900，外接屏在 x ≥ 1440；(100, 950) 不在任何屏幕内
        #expect(topology.screen(containing: CGPoint(x: 100, y: 950)) == nil)
        #expect(topology.screen(containing: CGPoint(x: 1000, y: -10)) == nil)
    }

    @Test("屏幕重叠（镜像）时取第一个")
    func overlappingPicksFirst() {
        let mirror = CaptureScreen(id: 9, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 1)
        let overlapping = ScreenTopology(screens: [mirror, CaptureFixtures.primary], windows: [], ownPID: 1)
        #expect(overlapping.screen(containing: CGPoint(x: 10, y: 10))?.id == 9)
    }

    @Test("按 id 查找屏幕")
    func screenByID() {
        #expect(topology.screen(id: 2) == CaptureFixtures.external)
        #expect(topology.screen(id: 99) == nil)
    }

    @Test("保留窗口 z 序与自身 PID，可比较")
    func storesWindowsAndPID() {
        #expect(topology.windows.map(\.id) == [12, 13, 10, 11])
        #expect(topology.ownPID == CaptureFixtures.ownPID)
        #expect(topology == CaptureFixtures.topology())
        #expect(topology != CaptureFixtures.topology(twoScreens: false))
    }

    @Test("WindowCandidate 保存全部字段，可哈希")
    func windowCandidateFields() {
        let window = CaptureFixtures.editorWindow
        #expect(window.id == 10)
        #expect(window.frame == CGRect(x: 100, y: 100, width: 600, height: 400))
        #expect(window.layer == 0)
        #expect(window.ownerPID == CaptureFixtures.otherPID)
        #expect(window.alpha == 1)
        #expect(Set([window, window, CaptureFixtures.menuBar]).count == 2)
    }
}

@Suite("CaptureSession 冻结帧集合")
struct CaptureSessionTests {
    @Test("FrozenFrame 保存屏幕与位图")
    func frozenFrameFields() {
        let image = TestImage.solid(width: 4, height: 2, .black)
        let frame = FrozenFrame(screen: CaptureFixtures.primary, image: image)
        #expect(frame.screen == CaptureFixtures.primary)
        #expect(frame.image.width == 4)
    }

    @Test("按屏幕 id 取帧；缺失返回 nil")
    func frameForScreen() {
        let primaryFrame = FrozenFrame(
            screen: CaptureFixtures.primary, image: TestImage.solid(width: 4, height: 4, .white))
        let externalFrame = FrozenFrame(
            screen: CaptureFixtures.external,
            image: TestImage.solid(width: 2, height: 2, .black)
        )
        let session = CaptureSession(topology: CaptureFixtures.topology(), frames: [primaryFrame, externalFrame])

        #expect(session.frame(for: 2)?.image.width == 2)
        #expect(session.frame(for: 1)?.screen == CaptureFixtures.primary)
        #expect(session.frame(for: 7) == nil)
        #expect(session.topology == CaptureFixtures.topology())
        #expect(session.frames.count == 2)
    }

    @Test("冻结帧可跨并发域传递")
    func sendableAcrossTasks() async {
        let frame = FrozenFrame(screen: CaptureFixtures.primary, image: TestImage.solid(width: 3, height: 3, .black))
        let session = CaptureSession(topology: CaptureFixtures.topology(), frames: [frame])
        let width = await Task.detached { session.frame(for: 1)?.image.width }.value
        #expect(width == 3)
    }
}
