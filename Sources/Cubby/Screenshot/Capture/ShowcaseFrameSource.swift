#if DEBUG
import CoreGraphics
import CubbyCore
import Foundation

/// README 展示场景的冻结帧：合成的桌面（渐变壁纸 + 发布说明 + 下载量仪表盘），用来拍截图标注的宣传图。
/// 与 FixtureFrameSource 一样不需要屏幕录制权限，也不会截到用户的真实屏幕；窗口列表与画面一致，悬停识别可用
struct ShowcaseFrameSource: FrameSource, WindowImageSource {
    let screens: [CaptureScreen]
    let copy: ShowcaseCopy

    func capture(excludingPID: pid_t, exceptWindowIDs: Set<UInt32>, timeout: Duration) async throws -> CaptureSession {
        guard let primary = screens.first else { throw FrameCaptureError.noDisplays }
        let frames = try screens.map { screen in
            let layout = screen == primary ? ShowcaseLayout(screen: screen) : nil
            guard let image = ShowcasePainter.desktop(for: screen, layout: layout, copy: copy) else {
                throw FrameCaptureError.noDisplays
            }
            return FrozenFrame(screen: screen, image: image)
        }
        let windows = ShowcaseLayout(screen: primary).candidates
        let topology = ScreenTopology(screens: screens, windows: windows, ownPID: excludingPID)
        return CaptureSession(topology: topology, frames: frames)
    }

    /// 只画这一个窗口：圆角外透明，includeShadow 时四周留出阴影
    func captureWindow(id: UInt32, includeShadow: Bool, timeout: Duration) async throws -> WindowImage {
        guard let screen = screens.first,
            [ShowcaseLayout.notesID, ShowcaseLayout.dashboardID].contains(id),
            let image = ShowcasePainter.window(
                id: id, layout: ShowcaseLayout(screen: screen), copy: copy, scale: screen.scale,
                includeShadow: includeShadow)
        else { throw FrameCaptureError.windowNotFound }
        return WindowImage(image: image, scale: screen.scale)
    }
}
#endif
