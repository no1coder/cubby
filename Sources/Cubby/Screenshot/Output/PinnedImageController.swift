import AppKit
import CubbyCore
import os

/// 贴图集合：创建、复制、存储、关闭。可同时存在多张；退出应用即消失，不持久化
@MainActor
final class PinnedImageController {
    private struct Pin {
        let window: PinnedImageWindow
        /// 截图流程已编码好的 PNG；没有时在复制 / 存储时按需编码
        let png: Data?
        let scale: CGFloat
    }

    private let settings: AppSettings
    /// 贴图 ⌘C 写入的剪贴板：默认为系统剪贴板；调试时可换成独立的命名剪贴板，避免覆盖用户剪贴板
    private let pasteboard: NSPasteboard
    /// 「存储…」的位置选择（与截图的存储共用同一个组件）
    private let savePrompt: any SaveDestinationPrompting
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")
    private var pins: [Pin] = []

    init(
        settings: AppSettings,
        pasteboard: NSPasteboard = .general,
        savePrompt: any SaveDestinationPrompting = ScreenshotSavePrompt.shared
    ) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.savePrompt = savePrompt
    }

    /// 贴图窗口的窗口号：采集冻结帧时保留它们（贴图是用户内容，应出现在下一次截图里）
    var windowIDs: Set<UInt32> {
        Set(pins.compactMap { UInt32(exactly: $0.window.windowNumber) })
    }

    var count: Int {
        pins.count
    }

    /// 截图的「贴图」出口：与选区原位、1:1 重合（选区是全局点，这里换算为 AppKit 坐标）
    @discardableResult
    func pin(_ export: ScreenshotExport) -> PinnedImageWindow {
        let frame = ScreenTopologyProvider.toAppKit(export.selection)
        return pin(image: export.image, png: export.png, scale: export.screen.scale, frame: frame)
    }

    /// 在给定位置（AppKit 屏幕坐标）以 1:1 贴图；frame 的尺寸即点尺寸
    @discardableResult
    func pin(image: CGImage, png: Data?, scale: CGFloat, frame: CGRect) -> PinnedImageWindow {
        let window = PinnedImageWindow(image: image, frame: frame)
        let pin = Pin(window: window, png: png, scale: scale)
        window.onCopy = { [weak self, weak window] in
            if let window { self?.copy(window) }
        }
        window.onSave = { [weak self, weak window] in
            if let window { self?.save(window) }
        }
        window.onClose = { [weak self, weak window] in
            if let window { self?.close(window) }
        }
        pins = pins + [pin]
        window.present()
        return window
    }

    /// 以屏幕上一点为中心贴图（阶段 2：从历史贴图）
    @discardableResult
    func pin(image: CGImage, pixelSize: CGSize, scale: CGFloat, at appKitCenter: CGPoint) -> PinnedImageWindow {
        let size = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        let frame = CGRect(
            x: appKitCenter.x - size.width / 2,
            y: appKitCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return pin(image: image, png: nil, scale: scale, frame: frame)
    }

    func closeAll() {
        pins.forEach { $0.window.close() }
        pins = []
    }

    // MARK: - 动作

    private func copy(_ window: PinnedImageWindow) {
        guard let pin = pin(for: window) else { return }
        let anchor = center(of: window)
        Task {
            guard let png = await Self.pngData(for: pin) else {
                NSSound.beep()
                return
            }
            do {
                // 带自身写入标记：贴图入历史时已记录过，剪贴板监听不会重复记录
                try ScreenshotPasteboard.write(png: png, to: pasteboard)
            } catch {
                logger.error("Failed to copy pinned screenshot")
                NSSound.beep()
                return
            }
            HUDToast.show(String(localized: "Copied to clipboard", comment: "HUD after copying an item"), at: anchor)
        }
    }

    /// 「存储…」：与截图的存储共用同一个对话框组件（§9.4），起始目录与记住的文件夹也相同
    private func save(_ window: PinnedImageWindow) {
        guard let pin = pin(for: window) else { return }
        let anchor = center(of: window)
        let focus = FocusRestorer.capture()
        let directory = ScreenshotSaveLocation.resolved(preferred: settings.screenshotSaveDirectory)
        Task {
            let url = await savePrompt.chooseDestination(
                suggestedName: ScreenshotFileNaming.fileName(date: Date()), directory: directory, screen: window.screen)
            focus.restore()
            guard let url else { return }
            guard let png = await Self.pngData(for: pin) else {
                NSSound.beep()
                return
            }
            // 贴图时已入过历史，这里只写文件
            showSaveResult(await ScreenshotSaveWriter.write(png, to: url, settings: settings), anchor: anchor)
        }
    }

    private func showSaveResult(_ result: Result<URL, ScreenshotFileSaver.SaveError>, anchor: CGPoint) {
        switch result {
        case .success(let url):
            HUDToast.show(ScreenshotSaveWriter.savedMessage(for: url), at: anchor)
        case .failure(let error):
            logger.error("Failed to save pinned screenshot: \(error.logDescription, privacy: .public)")
            HUDToast.show(
                String(localized: "Couldn't save the screenshot", comment: "HUD when saving a screenshot fails"),
                symbolName: "exclamationmark.triangle.fill",
                tint: .orange,
                at: anchor
            )
        }
    }

    private func close(_ window: PinnedImageWindow) {
        window.close()
        pins = pins.filter { $0.window !== window }
    }

    // MARK: - 辅助

    private func pin(for window: PinnedImageWindow) -> Pin? {
        pins.first { $0.window === window }
    }

    private func center(of window: NSWindow) -> CGPoint {
        CGPoint(x: window.frame.midX, y: window.frame.midY)
    }

    /// 截图流程已有 PNG 时直接用；否则（演示图、将来从历史贴图）在后台编码
    private static func pngData(for pin: Pin) async -> Data? {
        if let png = pin.png { return png }
        let image = pin.window.image
        let scale = pin.scale
        return await Task.detached(priority: .userInitiated) {
            ScreenshotExporter.pngData(image, scale: scale)
        }.value
    }
}

#if DEBUG
extension PinnedImageController {
    /// 调试场景 screenshot:pin：用合成图片演示两张贴图（第一张为 key，便于检查 key 状态下的圆角阴影）
    func pinDemo() {
        guard let screen = NSScreen.main else { return }
        let scale = screen.backingScaleFactor
        let visible = screen.visibleFrame
        let sizes = [CGSize(width: 480, height: 300), CGSize(width: 240, height: 150)]
        let centers = [
            CGPoint(x: visible.midX - 80, y: visible.midY + 40),
            CGPoint(x: visible.midX + 260, y: visible.midY - 200),
        ]
        for (size, center) in zip(sizes, centers) {
            guard let image = Self.demoImage(size: size, scale: scale) else { continue }
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
            pin(image: image, pixelSize: pixelSize, scale: scale, at: center)
        }
        pins.first?.window.makeKey()
    }

    /// 合成图片：对角渐变 + 网格 + 左上角色块，边缘与圆角处对比明显
    private static func demoImage(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let colors = [NSColor.systemTeal.cgColor, NSColor.systemIndigo.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: nil) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(scale)
        let step = 40 * scale
        for x in stride(from: step, to: bounds.width, by: step) {
            context.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height)])
        }
        for y in stride(from: step, to: bounds.height, by: step) {
            context.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)])
        }
        context.setFillColor(NSColor.systemOrange.cgColor)
        context.fill(CGRect(x: 0, y: bounds.height - step, width: step, height: step))
        return context.makeImage()
    }
}
#endif
