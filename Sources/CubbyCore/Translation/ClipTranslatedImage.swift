import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 历史图片译后成图的输出（docs/CLIP-TRANSLATION-DESIGN.md §5.3，纯函数）
public enum ClipTranslatedImage {
    /// 译后图片的 PNG：沿用原图的 DPI（没有时不写 DPI，贴图与粘贴时按与原图相同的规则取倍率）；编码失败为 nil
    public static func pngData(_ image: CGImage, dpi: Double?) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let properties: [CFString: Any] =
            dpi.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            .map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// 缓存的 segments：按识别块 id 顺序每块一项，已翻译的为译文（去掉首尾空白），未翻译或译文为空的为 nil。
    /// 图片译文的 segments 只用于搜索与「复制译文文字」，译后成图才是主体：总长（UTF-16）超过 maxLength 时，
    /// 超出部分的块记为 nil，保证整条译文仍能缓存（ClipTranslationLimits 拒绝超长的译文）
    public static func segments(
        blockIDs: [Int], translations: [Int: String],
        maxLength: Int = ClipTranslationLimits.standard.maxStoredLength
    ) -> [String?] {
        let texts = blockIDs.sorted().map { id in
            translations[id].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap {
                $0.isEmpty ? nil : $0
            }
        }
        var total = 0
        return texts.map { text in
            guard let text else { return nil }
            total += text.utf16.count
            return total <= maxLength ? text : nil
        }
    }
}
