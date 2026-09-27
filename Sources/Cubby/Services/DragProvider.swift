import AppKit
import CubbyCore

/// 为卡片拖拽提供数据：文本、图片文件、文件
@MainActor
enum DragProvider {
    static func provider(for item: ClipItem, imageURL: URL?) -> NSItemProvider {
        switch item.payload {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .image:
            return imageURL.flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
        case .files(let paths):
            let existing = paths.first { FileManager.default.fileExists(atPath: $0) }
            return
                existing
                .flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        }
    }
}
