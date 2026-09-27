import CubbyCore
import CoreGraphics

/// 跨线程传递的位图（CGImage 不可变，可安全共享）
struct OverlayImage: @unchecked Sendable {
    let image: CGImage
}

/// 马赛克的整帧像素化副本：按屏幕缓存，第一次需要时在后台生成（§3.4.5）
///
/// Core 的渲染环境只接受一张像素化副本，因此一次会话内所有马赛克共用同一块大小：
/// 取「中」档笔刷对应的块（`Pixelator.blockSize(forBrushWidth:scale:)`），导出与屏幕显示一致。
@MainActor
final class MosaicPixelation {
    /// 某块屏幕的副本生成完毕（需要重绘标注层）
    var onReady: (() -> Void)?

    private var images: [UInt32: OverlayImage] = [:]
    private var pending: Set<UInt32> = []

    func image(for screenID: UInt32) -> CGImage? {
        images[screenID]?.image
    }

    /// 该屏已就绪或正在生成时不重复开始
    func prepare(_ frame: FrozenFrame) {
        let id = frame.screen.id
        guard images[id] == nil, !pending.contains(id) else { return }
        pending.insert(id)
        let blockSize = Self.blockSize(for: frame.screen)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Pixelator.pixelated(frame.image, blockSize: blockSize).map(OverlayImage.init)
            }.value
            self?.finish(id, result)
        }
    }

    private func finish(_ id: UInt32, _ result: OverlayImage?) {
        pending.remove(id)
        guard let result else { return }
        images[id] = result
        onReady?()
    }

    nonisolated static func blockSize(for screen: CaptureScreen) -> Int {
        Pixelator.blockSize(forBrushWidth: ScreenshotTool.mosaic.brushWidth(for: .regular), scale: screen.scale)
    }
}

/// 一次导出的输入：在后台线程执行 `ScreenshotExporter`（整屏导出最坏约 1.4 s，不能卡住主线程）
struct OverlayExportJob: Sendable {
    let frame: FrozenFrame
    let selection: CGRect
    let document: AnnotationDocument
    /// 译文块（「原文 | 译文」开关在译文时）：画在冻结帧之上、标注之下
    let translation: [TranslatedBlock]
    let pixelated: OverlayImage?
    /// 提取文字还需要不带标注的裁剪
    let needsCleanCrop: Bool

    /// 导出结果；失败时 export 为 nil
    struct Output: @unchecked Sendable {
        let export: ScreenshotExport?
        let clean: CGImage?
    }

    func run() -> Output {
        let hasMosaic = document.annotations.contains { $0.tool == .mosaic }
        let pixelatedFrame =
            pixelated?.image
            ?? (hasMosaic
                ? Pixelator.pixelated(frame.image, blockSize: MosaicPixelation.blockSize(for: frame.screen)) : nil)
        do {
            let export = try ScreenshotExporter.export(
                frame: frame,
                selection: selection,
                document: document,
                translation: translation,
                pixelatedFrame: pixelatedFrame
            )
            let clean = needsCleanCrop ? try ScreenshotExporter.crop(frame: frame, selection: selection) : nil
            return Output(export: export, clean: clean)
        } catch {
            return Output(export: nil, clean: nil)
        }
    }
}
