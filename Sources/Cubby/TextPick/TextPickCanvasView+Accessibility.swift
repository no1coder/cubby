import AppKit
import CubbyCore

// 词块区的读屏支持（docs/DESIGN.md「可访问性」）：整块区域是一个「词块」分组，每块是一个按钮元素——
// 朗读块的文字，已选的块值为「已选」，按下（VO-空格）切换选取。元素在读屏器第一次查询时才创建（上万块也只建一次），
// 位置按需从排版换算，滚动后仍准确

extension TextPickCanvasView {
    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityLabel() -> String? {
        TextPickCopy.canvasLabel
    }

    override func accessibilityChildren() -> [Any]? {
        if let accessibilityTokens { return accessibilityTokens }
        let elements = tokens.indices.map { TextPickTokenElement(index: $0, canvas: self) }
        accessibilityTokens = elements
        return elements
    }

    /// 某块在屏幕上的位置（读屏器的高亮框）
    func screenFrame(ofToken index: Int) -> CGRect {
        guard let frame = chipFrame(index), let window else { return .zero }
        return window.convertToScreen(convert(frame, to: nil))
    }

    func tokenText(at index: Int) -> String? {
        tokens.indices.contains(index) ? tokens[index].text : nil
    }

    /// 读屏器的「按下」：与单击一样切换这一块
    func toggleFromAccessibility(_ index: Int) -> Bool {
        guard tokens.indices.contains(index) else { return false }
        commit(selection.toggling(index))
        return true
    }
}

/// 一块词的读屏元素。NSAccessibilityElement 没有主线程隔离，读屏查询总在主线程到达，按主线程访问画布
final class TextPickTokenElement: NSAccessibilityElement {
    let index: Int
    private weak var canvas: TextPickCanvasView?

    init(index: Int, canvas: TextPickCanvasView) {
        self.index = index
        self.canvas = canvas
        super.init()
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityParent() -> Any? {
        canvas
    }

    override func accessibilityFrame() -> NSRect {
        let (canvas, index) = (canvas, index)
        return MainActor.assumeIsolated { canvas?.screenFrame(ofToken: index) ?? .zero }
    }

    override func accessibilityLabel() -> String? {
        let (canvas, index) = (canvas, index)
        return MainActor.assumeIsolated { canvas?.tokenText(at: index) }
    }

    override func isAccessibilitySelected() -> Bool {
        let (canvas, index) = (canvas, index)
        return MainActor.assumeIsolated { canvas?.selection.contains(index) ?? false }
    }

    override func accessibilityValue() -> Any? {
        isAccessibilitySelected() ? TextPickCopy.selectedValue : nil
    }

    override func accessibilityHelp() -> String? {
        TextPickCopy.tokenHelp
    }

    override func accessibilityPerformPress() -> Bool {
        let (canvas, index) = (canvas, index)
        return MainActor.assumeIsolated { canvas?.toggleFromAccessibility(index) ?? false }
    }
}
