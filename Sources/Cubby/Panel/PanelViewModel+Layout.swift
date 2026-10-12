import CoreGraphics
import CubbyCore

/// 面板排布（docs/UI-UPGRADE-PLAN.md 第 3 节）：浮动 / 右侧侧栏 / 底部横条
extension PanelViewModel {
    /// 当前排布：AppSettings 可观察，视图随设置变化切换
    var layout: PanelLayout {
        settings.panelPosition.layout
    }

    /// 「图片」分类在浮动面板与侧栏里以两列网格显示（横条本来就是一排方卡，不另做网格）
    var showsImageGrid: Bool {
        category == .image && layout != .shelf
    }

    /// 键盘移动选中项时一行有几格：网格里 ↑ / ↓ 移动一整行
    var selectionColumns: Int {
        showsImageGrid ? layout.imageGridColumns : 1
    }

    /// ← / → 移动选中项（搜索框为空时）：横条与图片网格
    var arrowsMoveHorizontally: Bool {
        layout.isHorizontal || showsImageGrid
    }

    /// 顶栏布局按钮：浮动 → 右侧 → 底部 → 浮动（回到上次选的浮动位置）
    func cycleLayout() {
        settings.panelPosition = settings.panelPosition.cycledLayout(floatingFallback: settings.floatingPanelPosition)
        onLayoutChange?()
    }

    /// 收起详情区并结束其中的工作（翻译卡的翻译、拆词卡的状态），不只是隐藏窗口
    func closeDetailPane() {
        translation?.card.close()
        textPick.close()
        setDetailPane(nil)
    }

    /// 横条报告选中卡片的位置；只在变化时通知（滚动中每帧都会报告）
    func shelfSelectionMoved(toX x: CGFloat) {
        guard shelfAnchorX.map({ abs($0 - x) > 0.5 }) ?? true else { return }
        shelfAnchorX = x
        onShelfAnchorChange?()
    }
}
