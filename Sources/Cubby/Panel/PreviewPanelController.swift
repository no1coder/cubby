import AppKit
import SwiftUI
import CubbyCore

/// 主面板旁的详情区面板（空格预览 / 翻译卡 / 拆词卡，K1）：不成为 key window，键盘焦点始终留在主面板。
/// 高度随内容自适应（短内容紧凑、长内容与主面板等高），顶部与主面板对齐，显示期间随选中项实时更新。
@MainActor
final class PreviewPanelController {
    /// 超过该长度的文本在 440 宽下必然超过主面板高度，无需测量
    private static let longTextBytes = 1_500

    private let panel = ClipPanel(
        size: NSSize(width: PreviewMetrics.width, height: PreviewMetrics.minHeight),
        isKeyable: false
    )
    private let viewModel: PanelViewModel
    /// 预览内容只在面板显示期间挂载（见 PreviewPanelView）
    private let mount = PreviewMount()
    private var anchor: (host: CGRect, visible: CGRect)?
    /// 条目内容不可变，测量结果按（条目，详情区）缓存，连续切换选中项时不重复离屏布局
    private var heightCache: [HeightKey: CGFloat] = [:]

    private enum HeightKey: Hashable {
        case preview(UUID)
        case translation(TranslationCardLayout.Key)
    }

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        let rootView = PreviewPanelView(viewModel: viewModel, mount: mount) { [weak self] in self?.relayout() }
        let hostingView = FirstMouseHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        panel.contentView = PanelChrome.makeContainer(for: hostingView)
        // 翻译卡的悬停（对照高亮、图片块原文气泡）在这个不可成为 key 的窗口里也要收到移动事件
        panel.acceptsMouseMovedEvents = true
    }

    var isVisible: Bool {
        panel.isVisible
    }

    #if DEBUG
    /// 面板 E2E：详情区窗口（点击按钮、拖动分隔线、确认高度）
    var window: NSWindow { panel }
    #endif

    /// - Parameter hostFrame: 主面板落位后的最终位置（入场动画中不能用动画帧，否则纵向差 8pt）
    func show(beside hostFrame: CGRect, visibleFrame: CGRect) {
        anchor = (hostFrame, visibleFrame)
        mount.isActive = true
        panel.setFrame(targetFrame(), display: true)
        // 在上屏前同步挂载并排好内容：淡入的第一帧就有内容，不会先闪一帧空白
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.prefersReducedMotion ? Motion.fade : Motion.previewFade
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        anchor = nil
        heightCache.removeAll()
        // 同步卸载内容：隐藏期间选中项变化不再排版预览，同时立即释放预览文本的排版结果与预览大图
        mount.isActive = false
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderOut(nil)
    }

    /// 选中项、详情区或翻译卡布局变化时按新内容调整高度；减弱动态效果时直接跳到新高度
    func relayout() {
        guard panel.isVisible, anchor != nil else { return }
        let frame = targetFrame()
        guard frame != panel.frame else { return }
        guard !Motion.prefersReducedMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.previewResize
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func targetFrame() -> CGRect {
        guard let anchor else { return panel.frame }
        let full = PanelPlacement.frame(
            size: CGSize(width: PreviewMetrics.width, height: anchor.host.height),
            beside: anchor.host,
            visibleFrame: anchor.visible
        )
        let height = min(max(idealHeight(), minHeight), full.height)
        // 顶部与主面板对齐
        return CGRect(x: full.minX, y: full.maxY - height, width: full.width, height: height)
    }

    private var minHeight: CGFloat {
        switch viewModel.detailPane {
        case .translation: TranslationCardMetrics.minHeight
        case .textPick: TextPickMetrics.minHeight
        case .preview, nil: PreviewMetrics.minHeight
        }
    }

    /// 以不受约束的高度测量内容的理想高度；图片按宽高比计算，长文本直接取最大高度
    private func idealHeight() -> CGFloat {
        if viewModel.detailPane == .translation {
            return translationHeight()
        }
        if viewModel.detailPane == .textPick {
            return textPickHeight()
        }
        guard let item = viewModel.selectedItem else { return PreviewMetrics.minHeight }
        if case .image(let ref) = item.payload {
            return Self.imageHeight(ref, chrome: PreviewMetrics.headerHeight + PanelMetrics.footerHeight)
        }
        if (item.text?.utf8.count ?? 0) > Self.longTextBytes {
            return .greatestFiniteMagnitude
        }
        if let cached = heightCache[.preview(item.id)] { return cached }
        let probe = NSHostingView(
            rootView:
                ClipPreviewView(item: item, viewModel: viewModel)
                .frame(width: PreviewMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
        )
        let height = probe.fittingSize.height
        heightCache[.preview(item.id)] = height
        return height
    }

    /// 翻译卡：图片 = 图片高度 + 头部 / 工具条 / 底栏；文本按最终内容估算（流式过程中不跳动）
    private func translationHeight() -> CGFloat {
        guard let controller = viewModel.translation?.card, let card = controller.card,
            let item = viewModel.store.item(id: card.itemID)
        else { return TranslationCardMetrics.minHeight }
        let key = TranslationCardLayout.key(for: card)
        if case .image(let ref) = item.payload, !key.showsState {
            return Self.imageHeight(ref, chrome: TranslationCardMetrics.chromeHeight - 1)
        }
        if let cached = heightCache[.translation(key)] { return cached }
        let body = TranslationCardLayout.bodyHeight(for: card, item: item, controller: controller)
        let height = TranslationCardMetrics.chromeHeight + body
        heightCache[.translation(key)] = height
        return height
    }

    /// 拆词卡（docs/TEXT-PICK-DESIGN.md §3）：头部 + 底栏 + 词块区内容 + 结果条（按两行预留，选取出现时不跳动）；
    /// 不支持的条目为状态页；长文本在后台分词期间直接取最大高度（必然超过主面板高度）
    private func textPickHeight() -> CGFloat {
        let controller = viewModel.textPick
        if controller.isUnsupported {
            return TextPickMetrics.chromeHeight + TranslationCardMetrics.stateMinHeight
        }
        guard let layout = controller.layout(width: TextPickMetrics.contentWidth) else {
            return .greatestFiniteMagnitude
        }
        return TextPickMetrics.chromeHeight + TextPickTypesetter.contentHeight(of: layout)
            + TextPickMetrics.resultReservedHeight
    }

    /// 头部（与工具条）+ 底栏 + 上下留白 + 图片按宽度等比缩放后的高度（不放大到超过原始像素）。
    /// 横图不再撑满主面板高度、上下大片留白；竖图仍会被主面板高度截住（在 targetFrame 中）
    private static func imageHeight(_ ref: ImageRef, chrome bars: CGFloat) -> CGFloat {
        // 两条 0.5pt 分割线
        let dividers: CGFloat = 1
        let chrome = bars + PreviewMetrics.imageInset * 2 + dividers
        let contentWidth = min(PreviewMetrics.width - PreviewMetrics.imageInset * 2, CGFloat(ref.width))
        guard ref.width > 0 else { return .greatestFiniteMagnitude }
        return (chrome + contentWidth * CGFloat(ref.height) / CGFloat(ref.width)).rounded(.up)
    }
}
