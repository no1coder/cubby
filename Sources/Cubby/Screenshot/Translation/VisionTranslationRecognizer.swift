import CoreGraphics
import CubbyCore
import Foundation

// 截图翻译的文字识别（实现线 T3 拥有，docs/TRANSLATION-DESIGN.md §3.2）。
// 类型名与无参 init 是契约（T2 在 AppDelegate 创建它）；类型本身不标 @available，macOS 26 以下返回空数组。

/// 识别选区文字并按版面分块：macOS 26 的 Vision 文档识别 → 每行归入最小容器 → 假名补识别 → 列表符号 →
/// 全局点 → `TextBlockBuilder`。在调用方的任务里运行（不占主线程），可取消
struct VisionTranslationRecognizer: TranslationTextRecognizing {
    func blocks(in frame: FrozenFrame, selection: CGRect) async throws -> [TextBlock] {
        guard #available(macOS 26, *) else { return [] }
        let groups = try await DocumentTextReader.lineGroups(in: frame, selection: selection)
        try Task.checkCancellation()
        return TextBlockBuilder.blocks(from: groups)
    }
}

/// 选区裁剪图的像素 ↔ 全局点
struct RecognitionCanvas {
    let image: CGImage
    /// 裁剪图左上角在帧位图中的像素坐标
    let pixelOrigin: CGPoint
    let screen: CaptureScreen

    /// 与 ScreenshotExporter.crop 相同的像素矩形；选区为空或在帧外时为 nil
    init?(frame: FrozenFrame, selection: CGRect) {
        let bounds = CGRect(x: 0, y: 0, width: frame.image.width, height: frame.image.height)
        let rect = frame.screen.pixelRect(selection).intersection(bounds)
        guard !rect.isNull, !rect.isEmpty, let image = try? ScreenshotExporter.crop(frame: frame, selection: selection)
        else { return nil }
        self.image = image
        self.pixelOrigin = rect.origin
        self.screen = frame.screen
    }

    /// 裁剪图像素矩形（左上原点）→ 全局点
    func globalRect(_ box: CGRect) -> CGRect {
        let scale = screen.scale
        return CGRect(
            x: screen.frame.minX + (pixelOrigin.x + box.minX) / scale,
            y: screen.frame.minY + (pixelOrigin.y + box.minY) / scale, width: box.width / scale,
            height: box.height / scale)
    }
}
