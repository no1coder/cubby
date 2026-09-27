#if DEBUG
import CoreGraphics
import CubbyCore
import Foundation

/// 调试夹具：合成一张「桌面」代替真实屏幕，不需要屏幕录制权限，也不会截到用户的真实内容。
///
/// 第一块屏幕上有 3 个互相重叠的假窗口（前 → 后：Editor、Preview、Terminal，三者有共同重叠区，
/// 供 Tab / 滚轮逐层切换验证），外加 layer ≠ 0 的菜单栏与程序坞；背景是 20 pt 细网格 + 100 pt 刻度、
/// 8 色色板与棋盘格（看得清马赛克与放大镜）。窗口列表与画面完全一致，悬停识别可用
struct FixtureFrameSource: FrameSource, WindowImageSource {
    let screens: [CaptureScreen]

    func capture(excludingPID: pid_t, exceptWindowIDs: Set<UInt32>, timeout: Duration) async throws -> CaptureSession {
        guard let primary = screens.first else { throw FrameCaptureError.noDisplays }
        let frames = try screens.map { screen in
            let windows = screen == primary ? FixtureLayout.windows : []
            guard let image = FixturePainter.desktop(for: screen, windows: windows) else {
                throw FrameCaptureError.noDisplays
            }
            return FrozenFrame(screen: screen, image: image)
        }
        let candidates = FixtureLayout.all(screenSize: primary.frame.size).map { $0.candidate(on: primary) }
        let topology = ScreenTopology(screens: screens, windows: candidates, ownPID: excludingPID)
        return CaptureSession(topology: topology, frames: frames)
    }

    /// 只画这一个假窗口：圆角外透明，includeShadow 时四周留出阴影
    func captureWindow(id: UInt32, includeShadow: Bool, timeout: Duration) async throws -> WindowImage {
        guard let window = FixtureLayout.windows.first(where: { $0.id == id }), let screen = screens.first,
            let image = FixturePainter.window(window, scale: screen.scale, includeShadow: includeShadow)
        else { throw FrameCaptureError.windowNotFound }
        return WindowImage(image: image, scale: screen.scale)
    }
}

/// 假窗口：局部点坐标（相对屏幕左上角）
struct FixtureWindow: Sendable {
    let id: UInt32
    let title: String
    let frame: CGRect
    let layer: Int
    let tint: RGBAColor

    func candidate(on screen: CaptureScreen) -> WindowCandidate {
        WindowCandidate(
            id: id,
            frame: frame.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY),
            layer: layer,
            // 假进程号：不能与 Cubby 自身相同，否则会被悬停识别排除
            ownerPID: pid_t(Int32(id)),
            alpha: 1
        )
    }
}

enum FixtureLayout {
    static let menuBarHeight: CGFloat = 24
    private static let dockSize = CGSize(width: 480, height: 64)

    /// 普通窗口，前 → 后；三者在 (560...720, 200...370) 处共同重叠
    static let windows = [
        FixtureWindow(
            id: 9001, title: "Editor", frame: CGRect(x: 340, y: 200, width: 460, height: 300), layer: 0,
            tint: RGBAColor(red: 0.25, green: 0.47, blue: 0.95)),
        FixtureWindow(
            id: 9002, title: "Preview", frame: CGRect(x: 560, y: 140, width: 420, height: 320), layer: 0,
            tint: RGBAColor(red: 0.95, green: 0.55, blue: 0.2)),
        FixtureWindow(
            id: 9003, title: "Terminal", frame: CGRect(x: 200, y: 110, width: 520, height: 260), layer: 0,
            tint: RGBAColor(red: 0.2, green: 0.7, blue: 0.45)),
    ]

    /// 全部窗口（菜单栏 layer 24、程序坞 layer 20 在最前），前 → 后
    static func all(screenSize: CGSize) -> [FixtureWindow] {
        let chrome = RGBAColor(red: 0.9, green: 0.9, blue: 0.92)
        let menuBar = CGRect(x: 0, y: 0, width: screenSize.width, height: menuBarHeight)
        let dock = CGRect(
            x: (screenSize.width - dockSize.width) / 2, y: screenSize.height - dockSize.height - 8,
            width: dockSize.width, height: dockSize.height)
        return [
            FixtureWindow(id: 9101, title: "Menu Bar", frame: menuBar, layer: 24, tint: chrome),
            FixtureWindow(id: 9102, title: "Dock", frame: dock, layer: 20, tint: chrome),
        ] + windows
    }
}
#endif
