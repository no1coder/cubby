import AppKit
import CubbyCore

/// 为卡片拖拽提供数据：文本、图片文件、文件。
/// 图片暂时解密成临时副本再拖出（E9；拖到访达改用文件承诺 NSFilePromiseProvider 在后续阶段完成）
@MainActor
enum DragProvider {
    /// - Parameter imageFile: 图片条目才调用：生成临时副本
    static func provider(for item: ClipItem, imageFile: () -> URL?) -> NSItemProvider {
        switch item.payload {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .image:
            return imageFile().flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
        case .files(let paths):
            let existing = paths.first { FileManager.default.fileExists(atPath: $0) }
            return
                existing
                .flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        }
    }
}
