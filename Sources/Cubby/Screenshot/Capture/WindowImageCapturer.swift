import CoreGraphics
import CoreVideo
import CubbyCore
import Foundation
import ScreenCaptureKit
import os

/// 纯净窗口截图（设计文档 §9.3）：SCContentFilter(desktopIndependentWindow:) + SCScreenshotManager。
/// 不受其他窗口遮挡；按窗口所在屏幕的原生像素采集；圆角外保持透明（BGRA、shouldBeOpaque = false）。
///
/// 实测（macOS 26）：过滤器的 contentRect 只是窗口本身，不含阴影；带阴影时若按它设输出尺寸，
/// 窗口 + 阴影会被整体缩小塞进去（scalesToFit 默认开启）。因此带阴影时关闭 scalesToFit、
/// 四周多留 shadowMargin 的画布（内容贴左上角 1:1 输出），再裁到非透明像素的外接矩形。
/// includeShadow 为 false 时设置 ignoreShadowsSingleWindow，输出恰为窗口尺寸
struct WindowImageCapturer: WindowImageSource {
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")
    /// 带阴影时每条边额外留出的画布（点）：系统窗口阴影实测约 23（非 key）至 45（key）点
    private static let shadowMargin: CGFloat = 100

    func captureWindow(id: UInt32, includeShadow: Bool, timeout: Duration) async throws -> WindowImage {
        try await CaptureDeadline.run(timeout) {
            try await Self.capture(id: id, includeShadow: includeShadow)
        }
    }

    private static func capture(id: UInt32, includeShadow: Bool) async throws -> WindowImage {
        let clock = ContinuousClock()
        let start = clock.now
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw FrozenFrameCapturer.mapped(error)
        }
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw FrameCaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = configuration(for: filter, scale: scale, includeShadow: includeShadow)
        let captured: CGImage
        do {
            captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw FrozenFrameCapturer.mapped(error)
        }
        let image = includeShadow ? (AlphaBounds.cropped(captured) ?? captured) : captured
        logger.notice(
            """
            Window capture: \(image.width, privacy: .public)×\(image.height, privacy: .public) px, \
            shadow \(includeShadow, privacy: .public), \
            \(FrozenFrameCapturer.milliseconds(clock.now - start), privacy: .public) ms
            """
        )
        return WindowImage(image: image, scale: scale)
    }

    /// 不带阴影：输出 = 窗口（点）× 缩放；带阴影：四周加 shadowMargin，且不缩放
    private static func configuration(
        for filter: SCContentFilter,
        scale: CGFloat,
        includeShadow: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let margin = includeShadow ? shadowMargin * 2 : 0
        configuration.width = Int(((filter.contentRect.width + margin) * scale).rounded())
        configuration.height = Int(((filter.contentRect.height + margin) * scale).rounded())
        configuration.scalesToFit = !includeShadow
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // 保留圆角外的透明像素
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = !includeShadow
        return configuration
    }
}
