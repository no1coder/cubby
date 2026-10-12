import AppKit
import CubbyCore
import SwiftUI

/// 放大编辑一次渲染所需的标题行状态与回调
struct HistoryEditRender {
    let header: HistoryEditHeaderModel
    let icon: NSImage?
    let onZoom: (Int) -> Void
    let onClose: () -> Void
}

/// 晾衣绳放大编辑：图片上方的标题行、工具栏下方的快捷键提示，以及工具栏居中于图片下方
extension OverlayScreenView {
    /// 标题行不窄于这个宽度（小图时向两侧伸出，居中于图片）
    private static let minimumHeaderWidth: CGFloat = 420

    /// 工具栏摆放所依据的矩形：放大编辑时换成「图片下方居中、与工具栏同宽」的窄条，
    /// 让 `TranslationBarPlacement` 把工具栏（以及右对齐它的样式条、翻译条）放在图片正下方，并留出更宽的间距
    func toolbarAnchor(for selection: CGRect, locked: Bool) -> CGRect {
        guard locked else { return selection }
        let width = min(toolbarFittingWidth, selection.width)
        let extra = max(HistoryEditTokens.toolbarGap - OverlayTokens.toolbarGap, 0)
        return CGRect(
            x: selection.midX - width / 2, y: selection.minY, width: width, height: selection.height + extra)
    }

    func renderHistoryEdit(_ render: HistoryEditRender?, selection: CGRect?) {
        guard let render, let selection, space.intersects(selection) else {
            historyHeader?.isHidden = true
            historyHint?.isHidden = true
            return
        }
        layoutHeader(render, selection: space.pixelAligned(selection))
        layoutHint(selection: space.pixelAligned(selection))
    }

    // MARK: - 私有

    private func layoutHeader(_ render: HistoryEditRender, selection: CGRect) {
        let header = historyHeader ?? makeHeader(render)
        if historyHeaderModel != render.header || header.isHidden {
            historyHeaderModel = render.header
            header.rootView = HistoryEditHeader(
                model: render.header, icon: render.icon, onZoom: render.onZoom, onClose: render.onClose)
        }
        let width = max(selection.width, Self.minimumHeaderWidth)
        let global = CGRect(
            x: selection.midX - width / 2,
            y: selection.minY - HistoryEditTokens.headerGap - HistoryEditTokens.headerHeight,
            width: width,
            height: HistoryEditTokens.headerHeight)
        let bounds = space.screen.frame.insetBy(dx: OverlayTokens.screenMargin, dy: OverlayTokens.screenMargin)
        header.frame = alignedViewRect(SelectionGeometry.clamped(global, to: bounds))
        header.isHidden = false
    }

    private func layoutHint(selection: CGRect) {
        let hint = historyHint ?? makeHint()
        // 提示内容不变：只在第一次布局时测量（之后每次鼠标移动都会重新渲染）
        let size = hint.frame.isEmpty ? hint.fittingSize : hint.frame.size
        let rounded = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        // 工具栏、样式条、翻译条中最低的一个（视图坐标 y 向下，与全局点同向）
        let lowestChrome = chromeFrames.map { space.globalRect(fromView: $0).maxY }.max()
        let preferred = space.screen.frame.maxY - HistoryEditTokens.hintBottomInset - rounded.height
        let below = (lowestChrome ?? selection.maxY) + HistoryEditTokens.hintGap
        let global = CGRect(
            x: selection.midX - rounded.width / 2, y: max(preferred, below),
            width: rounded.width, height: rounded.height)
        hint.frame = alignedViewRect(SelectionGeometry.clamped(global, to: space.screen.frame))
        hint.isHidden = false
    }

    private func makeHeader(_ render: HistoryEditRender) -> FirstMouseHostingView<HistoryEditHeader> {
        let header = FirstMouseHostingView(
            rootView: HistoryEditHeader(
                model: render.header, icon: render.icon, onZoom: render.onZoom, onClose: render.onClose))
        header.sizingOptions = []
        addSubview(header, positioned: .above, relativeTo: canvas)
        historyHeader = header
        return header
    }

    private func makeHint() -> NSHostingView<HistoryEditHint> {
        let hint = OverlayPassthroughHostingView(rootView: HistoryEditHint())
        hint.sizingOptions = []
        addSubview(hint, positioned: .above, relativeTo: canvas)
        historyHint = hint
        return hint
    }
}

/// 不接收鼠标的 SwiftUI 宿主（提示行只是文字，点击落到画布上）
final class OverlayPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
