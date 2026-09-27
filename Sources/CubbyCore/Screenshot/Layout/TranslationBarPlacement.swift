import CoreGraphics

/// 工具栏、翻译条与样式条的摆放结果（全局点坐标）
public struct TranslationBarLayout: Equatable, Sendable {
    public let toolbar: CGRect
    /// 截图翻译的翻译条；未显示时为 nil
    public let translationBar: CGRect?
    /// 样式条；未显示时为 nil
    public let styleBar: CGRect?

    public init(toolbar: CGRect, translationBar: CGRect?, styleBar: CGRect?) {
        self.toolbar = toolbar
        self.translationBar = translationBar
        self.styleBar = styleBar
    }
}

/// 翻译条摆放（docs/TRANSLATION-DESIGN.md §1.1）：在工具栏远离选区的一侧、间距 6 pt、与工具栏右对齐；
/// 同时有样式条时样式条排在翻译条之后（更远一侧）。
///
/// 实现：把「翻译条 + 样式条」当作一整块样式条交给 `ToolbarPlacement`（上下是否放得下按整体高度判断），
/// 再在这块里从靠近工具栏的一端依次排开，各自右对齐工具栏并夹紧在屏幕内。
public enum TranslationBarPlacement {
    /// 相邻两条之间的间距（同工具栏与样式条）
    public static let spacing = ToolbarPlacement.styleBarSpacing

    public static func layout(
        toolbarSize: CGSize,
        translationBarSize: CGSize?,
        styleBarSize: CGSize?,
        selection: CGRect,
        screen: CGRect,
        gap: CGFloat = 8,
        inset: CGFloat = 8
    ) -> TranslationBarLayout {
        // 从靠近工具栏到远离工具栏
        let bars = [translationBarSize, styleBarSize]
        let sizes = bars.compactMap { $0 }
        let stack = sizes.isEmpty ? nil : stackSize(sizes)
        let base = ToolbarPlacement.layout(
            toolbarSize: toolbarSize, styleBarSize: stack, selection: selection, screen: screen, gap: gap,
            inset: inset)
        guard let stackFrame = base.styleBar else {
            return TranslationBarLayout(toolbar: base.toolbar, translationBar: nil, styleBar: nil)
        }
        let frames = stacked(sizes, in: stackFrame, toolbar: base.toolbar, side: base.side, screen: screen)
        var remaining = frames[...]
        let placed = bars.map { size in size.flatMap { _ in remaining.popFirst() } }
        return TranslationBarLayout(
            toolbar: base.toolbar, translationBar: placed[0], styleBar: placed[1])
    }

    /// 整块的尺寸：最宽者 × 各条高度之和（含间距）
    private static func stackSize(_ sizes: [CGSize]) -> CGSize {
        let height = sizes.map(\.height).reduce(0, +) + spacing * CGFloat(sizes.count - 1)
        return CGSize(width: sizes.map(\.width).max() ?? 0, height: height)
    }

    /// 在整块里排开：工具栏在下方时从上往下，在上方 / 内侧时从下往上（第一条总是紧挨工具栏）
    private static func stacked(
        _ sizes: [CGSize],
        in stack: CGRect,
        toolbar: CGRect,
        side: ToolbarSide,
        screen: CGRect
    ) -> [CGRect] {
        let downward = side == .below
        let offsets = sizes.indices.map { index in
            sizes[..<index].map { $0.height + spacing }.reduce(0, +)
        }
        return zip(sizes, offsets).map { size, offset in
            let y = downward ? stack.minY + offset : stack.maxY - offset - size.height
            let frame = CGRect(x: toolbar.maxX - size.width, y: y, width: size.width, height: size.height)
            return SelectionGeometry.clamped(frame, to: screen)
        }
    }
}
