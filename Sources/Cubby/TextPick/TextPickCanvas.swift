import AppKit
import CubbyCore
import SwiftUI

/// 词块区的 SwiftUI 桥接：NSScrollView 里放自绘的 TextPickCanvasView（不用 SwiftUI ScrollView：
/// 其内部容器视图不接受 first mouse，非 key 窗口里第一次点击可能被吞，docs/DESIGN.md「实现约束」）
struct TextPickCanvas: NSViewRepresentable {
    let controller: TextPickController
    /// 由父视图读取并传入，使文档或选取变化时 SwiftUI 调用 updateNSView
    let version: Int
    let selection: TextPickSelection

    func makeNSView(context: Context) -> TextPickScrollView {
        TextPickScrollView()
    }

    func updateNSView(_ view: TextPickScrollView, context: Context) {
        view.canvas.update(controller: controller, version: version, selection: selection)
    }
}

/// 词块区的滚动视图：透明背景、浮动滚动条（不占排版宽度），尺寸变化时让画布跟随宽度重新排版
final class TextPickScrollView: NSScrollView {
    let canvas = TextPickCanvasView()

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        documentView = canvas
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        canvas.fitToClipView()
    }
}
