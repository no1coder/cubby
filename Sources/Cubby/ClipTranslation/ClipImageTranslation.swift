import CoreGraphics
import CubbyCore
import Foundation
import os

/// 历史图片翻译的后台部分（docs/CLIP-TRANSLATION-DESIGN.md §5）：解码原图（带 DPI）→ 合成帧 → 过滤候选块 →
/// 逐块排版 → 整图渲染为 PNG。识别器与引擎由调用方在同一任务里驱动，取消即停止
enum ClipImageTranslation {
    /// 合成帧与原图 DPI（译后 PNG 沿用）
    struct Source: Sendable {
        let frame: FrozenFrame
        let selection: CGRect
        let dpi: Double?
    }

    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ClipTranslation")

    /// 读取并解码原图（整图解码），包装成原点在 (0,0) 的合成屏幕；读不到或无法解码时为 nil
    @concurrent
    static func load(_ url: URL) async -> Source? {
        guard let data = try? Data(contentsOf: url), let decoded = HistoryImageFrame.decode(data) else {
            return nil
        }
        let made = HistoryImageFrame.make(image: decoded.image, scale: HistoryImageFrame.scale(dpi: decoded.dpi))
        return Source(frame: made.frame, selection: made.selection, dpi: decoded.dpi)
    }

    /// 需要翻译的块：疑似密钥、没有字母、代码、已是目标语言的块不发送（图片里的疑似密钥即使确认过也不发送）
    @concurrent
    static func candidates(_ blocks: [TextBlock], target: String) async -> [TextBlock] {
        TranslationCandidates.translatable(blocks, target: target, hidden: [])
    }

    /// 一块译文的版面（历史图片没有选区限制，只受整帧约束）
    @concurrent
    static func place(_ block: TextBlock, translation: String, in frame: FrozenFrame) async -> TranslatedBlock {
        TranslationPlacer.place(block, translation: translation, in: frame)
    }

    /// 原图 + 各块版面 → 译后 PNG（沿用原图 DPI）；失败为 nil
    @concurrent
    static func render(_ source: Source, blocks: [TranslatedBlock]) async -> Data? {
        do {
            let image = try HistoryImageFrame.render(source.frame, blocks: blocks.sorted { $0.blockID < $1.blockID })
            return ClipTranslatedImage.pngData(image, dpi: source.dpi)
        } catch {
            logger.error("Rendering the translated image failed")
            return nil
        }
    }
}
