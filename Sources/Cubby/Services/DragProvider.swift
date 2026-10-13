import AppKit
import CubbyCore

/// 为文本与文件卡片的拖出提供数据（SwiftUI onDrag）。
/// 图片条目不经过这里：改由 ImageDragSource 交出文件承诺 + 图片数据（E9，不写临时明文副本）
@MainActor
enum DragProvider {
    static func provider(for item: ClipItem) -> NSItemProvider {
        switch item.payload {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .image:
            return NSItemProvider()
        case .files(let paths):
            let existing = paths.first { FileManager.default.fileExists(atPath: $0) }
            return
                existing
                .flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        }
    }
}
