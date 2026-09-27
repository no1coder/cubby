import CoreGraphics
import CubbyCore
import Foundation

/// 冻结帧的来源：真实采集（FrozenFrameCapturer）或调试夹具（FixtureFrameSource）
protocol FrameSource: Sendable {
    /// 采集所有屏幕。excludingPID 的窗口不出现在帧里；exceptWindowIDs 中的窗口（贴图）例外，照常出现
    func capture(excludingPID: pid_t, exceptWindowIDs: Set<UInt32>, timeout: Duration) async throws -> CaptureSession
}

/// 纯净窗口截图（设计文档 §9.3）的来源
protocol WindowImageSource: Sendable {
    /// 按原生像素采集单个窗口；圆角外保持透明；includeShadow 为 false 时不带系统窗口阴影
    func captureWindow(id: UInt32, includeShadow: Bool, timeout: Duration) async throws -> WindowImage
}

/// 单个窗口的位图及其点 → 像素缩放（PNG 的 DPI 与贴图尺寸都要用到）
struct WindowImage: Sendable {
    let image: CGImage
    let scale: CGFloat
}

enum FrameCaptureError: Error {
    /// 没有屏幕录制权限（或用户在系统弹窗中拒绝）
    case notAuthorized
    /// 超时：macOS 15+ 周期性确认弹窗期间采集会挂起（设计文档 §6 R2）
    case timedOut
    case noDisplays
    /// 纯净窗口截图时目标窗口已不存在
    case windowNotFound
    case underlying(any Error)

    /// 日志用的固定名称（不含路径等用户信息）
    var logName: String {
        switch self {
        case .notAuthorized: "notAuthorized"
        case .timedOut: "timedOut"
        case .noDisplays: "noDisplays"
        case .windowNotFound: "windowNotFound"
        case .underlying(let error): "underlying(\((error as NSError).domain) \((error as NSError).code))"
        }
    }
}
