import CoreGraphics
import Darwin
@testable import CubbyCore

/// 模糊测试用的屏幕 / 窗口拓扑：刻意包含两屏交界、负坐标、屏幕间空隙、小数坐标窗口、跨屏窗口与重叠窗口栈
enum FuzzTopologies {
    static let ownPID: pid_t = 777

    /// 主屏 1440×900 @2x
    static let primary = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    /// 外接屏 1920×1080 @1x，左边与主屏右边重合，上方伸到负坐标
    static let external = CaptureScreen(
        id: 2, frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), scale: 1)
    /// 左下方 1280×800 @2x，只与主屏左下角接触（周围全是空隙）
    static let lower = CaptureScreen(id: 3, frame: CGRect(x: -1280, y: 900, width: 1280, height: 800), scale: 2)

    /// 窗口按 z 序（前 → 后）
    static let windows: [WindowCandidate] = [
        window(10, CGRect(x: 0, y: 0, width: 1440, height: 24), layer: 25),
        window(11, CGRect(x: 300, y: 300, width: 200, height: 200), owner: ownPID),
        window(12, CGRect(x: 800, y: 600, width: 100, height: 100), alpha: 0),
        window(13, CGRect(x: 900, y: 750, width: 1, height: 1)),
        window(14, CGRect(x: 950, y: 700, width: 2, height: 2)),
        // 小数坐标窗口
        window(15, CGRect(x: 10.25, y: 30.75, width: 50.5, height: 40.25)),
        // 三层重叠栈：检查器压在编辑器上，编辑器还有一个同 frame 的孪生窗口
        window(16, CGRect(x: 500, y: 300, width: 400, height: 300)),
        window(17, CGRect(x: 100, y: 100, width: 600, height: 400)),
        window(18, CGRect(x: 100, y: 100, width: 600, height: 400)),
        // 跨主屏与外接屏；在主屏上只露 1.5 pt 的细条
        window(19, CGRect(x: 1200, y: 200, width: 600, height: 300)),
        window(20, CGRect(x: 1438.5, y: 400, width: 300, height: 100)),
        // 外接屏负坐标区域的小数窗口、伸出外接屏上缘的窗口
        window(21, CGRect(x: 1500, y: -170.5, width: 400.25, height: 200.75)),
        window(22, CGRect(x: 2000, y: -300, width: 500, height: 200)),
        // 跨主屏与左下屏（经过两屏之间的空隙）
        window(23, CGRect(x: -100, y: 800, width: 400, height: 300)),
        // 负宽高的 frame（standardized 后有效）
        window(24, CGRect(x: 1300, y: 700, width: -100, height: -50)),
    ]

    static let threeScreens = ScreenTopology(screens: [primary, external, lower], windows: windows, ownPID: ownPID)

    /// 最后面垫一个覆盖全部屏幕的大窗口：任何屏幕上的点都至少有一个窗口候选
    static let coveredDesktop = ScreenTopology(
        screens: [primary, external],
        windows: windows + [window(30, CGRect(x: -2000, y: -1000, width: 6000, height: 3000))],
        ownPID: ownPID
    )

    /// 参与模糊测试的全部拓扑；失败报告只记录下标
    static let all: [ScreenTopology] = [
        threeScreens,
        coveredDesktop,
        TopologyFixture.twoScreens,
        CaptureFixtures.topology(twoScreens: true),
        CaptureFixtures.topology(twoScreens: false),
        TopologyFixture.noWindows,
        TopologyFixture.empty,
    ]

    /// 第 index 个拓扑的独立副本：数组存储不与其他线程共享。
    ///
    /// 各分片并行运行；若共用同一份 static 数组，每次 retain / release 都在同一缓存行上争用，
    /// 实测会让并行模糊测试的 CPU 时间膨胀数倍
    static func isolated(_ index: Int) -> ScreenTopology {
        let shared = all[index]
        return ScreenTopology(
            screens: shared.screens.map { $0 }, windows: shared.windows.map { $0 }, ownPID: shared.ownPID)
    }

    /// 选择拓扑的权重（与 `all` 一一对应）
    static let weights = [40, 12, 20, 12, 6, 6, 4]

    private static func window(
        _ id: UInt32,
        _ frame: CGRect,
        layer: Int = 0,
        owner: pid_t = 100,
        alpha: Double = 1
    ) -> WindowCandidate {
        WindowCandidate(id: id, frame: frame, layer: layer, ownerPID: owner, alpha: alpha)
    }
}
