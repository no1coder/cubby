import CoreGraphics
import CubbyCore
import os

/// 覆盖层的结果：C 产出，B（ScreenshotCoordinator）消费。
/// 「存储」不在这里：它先请求位置、可能取消并回到覆盖层，走 `ScreenshotOverlayDelegate.overlay(_:didRequestSave:)`
enum ScreenshotResult {
    case copy(ScreenshotExport)
    case pin(ScreenshotExport)
    /// clean = 无标注的裁剪图，供 OCR
    case extractText(ScreenshotExport, clean: CGImage)
    /// 放大镜当前显示的颜色文本（HEX 或 RGB）
    case copyColor(String)
    /// 纯净窗口截图（设计文档 §9.3，对应 ScreenshotOutcome.captureWindow）：不导出选区，
    /// 由协调器在覆盖层关闭后按窗口 id 单独采集，再复制并入历史
    case captureWindow(windowID: UInt32, includeShadow: Bool)
    /// ⌘T 提取文字时开关在「译文」（截图翻译）：直接复制译文，不再 OCR；selection 用于 HUD 位置
    case translatedText(String, selection: CGRect)
    case cancel
    case failed(ScreenshotFailure)
}

enum ScreenshotFailure: Equatable {
    case exportFailed
    case noScreen
}

@MainActor
protocol ScreenshotOverlayDelegate: AnyObject {
    /// 覆盖层结束（任何出口）；调用前覆盖层窗口应已 orderOut
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didFinishWith result: ScreenshotResult)
    /// 样式条改动了某个工具的样式（reducer 的 .stylesChanged），协调器写回 AppSettings.annotationStyles
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didChangeStyles styles: ToolStyles)
    /// 「存储」出口（§9.4）：覆盖层已隐藏但**保留会话**（选区、标注、撤销栈），导出完成后请求存储。
    /// 委托之后必须二选一：存好了（或无法恢复）调 `overlay.dismiss()` 释放覆盖层；
    /// 用户在存储对话框点了取消调 `overlay.resume()`，覆盖层回到点「存储」之前的样子。
    /// 这两个调用都不会再触发 didFinishWith
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestSave export: ScreenshotExport)
    /// 截图翻译失败后的「去设置」「下载语言」：覆盖层已暂停（隐藏但保留会话，同存储对话框）。
    /// 委托 `await provider.resolve(failure)` 之后调 `overlay.resumeAfterResolving(retry:)`，或 `dismiss()`
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestResolving failure: TranslationFailure)
    /// 翻译条「复制译文」：写剪贴板并入历史（遵守暂停记录与密钥规则），覆盖层保持打开
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didRequestCopyingText text: String, selection: CGRect)
}

@MainActor
protocol ScreenshotOverlayPresenting: AnyObject {
    /// capture：帧与拓扑；initial：起始会话（正常为 .initial(styles:cursor:topology:)，调试场景为预置值）
    init(capture: CaptureSession, initial: ScreenshotSession, delegate: any ScreenshotOverlayDelegate)
    func present()
    /// 外部取消（快捷键再按、显示器变化）；必须回调 didFinishWith(.cancel)。
    /// 例外：导出进行中（isFinishing）不取消，导出完成后回调真实结果
    func cancel()
    /// 当前阶段（协调器判断「再按快捷键」是否允许取消）
    var phase: ScreenshotPhase { get }
    var hasAnnotations: Bool { get }
    /// 出口已确认、正在后台导出（覆盖层已隐藏）：此时 cancel() 不生效，协调器也应忽略再按快捷键
    var isFinishing: Bool { get }
    /// 存储对话框取消：重新显示覆盖层，恢复到点「存储」之前的会话，用户可以继续编辑或改走其他出口
    func resume()
    /// 存储流程结束：释放暂停中的覆盖层（不回调委托）
    func dismiss()
    /// 启用截图翻译（上屏前由协调器调用；会话的 isTranslationAvailable 需同时为 true）
    func attachTranslation(_ services: ScreenshotTranslationServices)
    /// 「去设置」「下载语言」处理完：覆盖层带着原来的会话重新上屏；retry 为 true 时自动重试翻译
    func resumeAfterResolving(retry: Bool)
}

/// 占位实现：在覆盖层交付前让协调器可编译、调试场景可跑通数据链路。
/// present() 记录采集概况后立即回调 .cancel
@MainActor
final class NoOverlay: ScreenshotOverlayPresenting {
    private let capture: CaptureSession
    private let initial: ScreenshotSession
    private weak var delegate: (any ScreenshotOverlayDelegate)?
    private var isFinished = false
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")

    init(capture: CaptureSession, initial: ScreenshotSession, delegate: any ScreenshotOverlayDelegate) {
        self.capture = capture
        self.initial = initial
        self.delegate = delegate
    }

    var phase: ScreenshotPhase { initial.phase }
    var hasAnnotations: Bool { initial.hasAnnotations }
    var isFinishing: Bool { false }

    func present() {
        let sizes = capture.frames.map { "\($0.image.width)x\($0.image.height)" }.joined(separator: ", ")
        logger.notice(
            """
            NoOverlay: \(self.capture.frames.count, privacy: .public) frame(s) [\(sizes, privacy: .public)], \
            \(self.capture.topology.windows.count, privacy: .public) window(s), \
            phase \(String(describing: self.initial.phase), privacy: .public), \
            hover depth \(self.initial.hoverDepth, privacy: .public), \
            window mode \(self.initial.isWindowCaptureMode, privacy: .public)
            """
        )
        cancel()
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        delegate?.overlay(self, didFinishWith: .cancel)
    }

    /// 占位实现从不请求存储，没有可恢复或释放的状态
    func resume() {}
    func dismiss() {}
    /// 占位实现不提供翻译
    func attachTranslation(_ services: ScreenshotTranslationServices) {}
    func resumeAfterResolving(retry: Bool) {}
}
