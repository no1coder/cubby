import AppKit
import CubbyCore
import os

/// 应用层的临时副本入口（E9）：必须交出文件路径时（拖到只接受 URL 的目标、用预览打开）解密到
/// `$TMPDIR/Cubby-Shared/`，退出时与下次启动时删除。粘贴与应用内显示始终只在内存中
@MainActor
enum SharedFiles {
    private static let export = SharedFileExport.temporary
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")
    private static let pngExtension = "png"

    /// 把图片条目的原图解密成临时 PNG 副本（文件名取条目标题）；读不到或写入失败时为 nil
    static func exportImage(_ item: ClipItem, source: ClipImageSource?) -> URL? {
        guard let source else { return nil }
        do {
            return try export.export(try source.data(), name: item.title, fileExtension: pngExtension)
        } catch {
            logger.error("Failed to export a shared copy: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 删除全部临时副本
    static func removeLeftovers() {
        do {
            try export.removeAll()
        } catch {
            logger.error("Failed to remove shared copies: \(error.localizedDescription, privacy: .public)")
        }
    }
}
