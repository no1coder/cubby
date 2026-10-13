import AppKit
import CubbyCore
import SwiftUI
import UniformTypeIdentifiers

/// 图片条目拖出（docs/HISTORY-ENCRYPTION-DESIGN.md E9）：SwiftUI 的 onDrag 只能交出 NSItemProvider，
/// 访达拿不到文件承诺，所以由拖动手势启动 AppKit 拖拽会话，交出 ImageFilePromise。
/// 手势与单击、双击、长按同时识别（移动超过 4pt 时长按与单击都会失败，交给拖出）
struct ImageDragSource: ViewModifier {
    let source: ClipImageSource?
    let title: String

    @State private var session = ImageDragSession()

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: TextPickMetrics.longPressMaxDistance)
                .onChanged { _ in
                    guard let source else { return }
                    session.beginIfNeeded(source: source, title: title)
                }
                .onEnded { _ in session.reset() }
        )
    }
}

/// 一次拖动手势对应的拖拽会话：手势的每次变化都会回调，只在第一次启动会话
@MainActor
final class ImageDragSession: NSObject, NSDraggingSource {
    /// 拖动预览的最长边（点）
    private static let previewMaxSide: CGFloat = 160
    private static let previewOpacity: CGFloat = 0.85

    private var isDragging = false

    func beginIfNeeded(source: ClipImageSource, title: String) {
        guard !isDragging, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
            let view = event.window?.contentView
        else { return }
        isDragging = true
        let item = NSDraggingItem(pasteboardWriter: ImageFilePromise(source: source, title: title))
        let image = Self.preview(for: source)
        let size = Self.fitted(image.size)
        let point = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
            contents: Self.faded(image))
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    /// 手势结束或拖拽会话结束（会话期间 SwiftUI 可能收不到松开事件）都复位
    func reset() {
        isDragging = false
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        MainActor.assumeIsolated { reset() }
    }

    /// 拖动预览：已缓存的卡片缩略图 → 预生成的小缩略图 → PNG 文件图标
    private static func preview(for source: ClipImageSource) -> NSImage {
        if let cached = ImageCache.shared.cachedThumbnail(for: source, maxPixelSize: ImageThumbnail.pixelSize) {
            return cached
        }
        if let data = source.thumbnailData(), let image = NSImage(data: data) {
            return image
        }
        return NSWorkspace.shared.icon(for: .png)
    }

    private static func fitted(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: previewMaxSide, height: previewMaxSide) }
        let scale = min(1, previewMaxSide / max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// 半透明的预览，与系统拖拽观感一致
    private static func faded(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: previewOpacity)
            return true
        }
    }
}
