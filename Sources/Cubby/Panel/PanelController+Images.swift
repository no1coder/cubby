import AppKit
import CubbyCore

/// 「只看图片」快捷键（docs/UI-UPGRADE-PLAN.md 第 4 节）
extension PanelController {
    /// 提示胶囊的中心在面板顶边之上这么高；离屏幕左右边缘至少 imagesHintInset（约半个胶囊宽）
    private static let imagesHintOffset: CGFloat = 28
    private static let imagesHintInset: CGFloat = 180

    /// 「只看图片」快捷键（docs/UI-UPGRADE-PLAN.md 第 4 节）：面板未显示 → 打开并切到「图片」；
    /// 已显示但不在「图片」→ 切过去；已在「图片」→ 关闭。通过快捷键进入时在面板上方短暂提示
    func toggleImages() {
        if isShown, viewModel.category == .image {
            hide()
            return
        }
        if !isShown { show(.hotKey) }
        guard isShown else { return }
        viewModel.selectCategory(.image)
        showImagesHint()
    }

    private func showImagesHint() {
        guard let shortcut = settings.imagesHotKey?.displayName else { return }
        let frame = restingFrame ?? panel.frame
        let message =
            viewModel.showsImageGrid
            ? String(
                localized: "\(shortcut) Only images · ←→↑↓ to move in the grid",
                comment: "HUD above the panel after the Only Images shortcut. %@ = the shortcut, e.g. ⌃⇧V")
            : String(
                localized: "\(shortcut) Only images",
                comment: "HUD above the docked bottom panel after the Only Images shortcut. %@ = the shortcut")
        // 面板顶边离菜单栏很近（侧栏、菜单栏图标下方）时胶囊不能跑到菜单栏上或屏幕外：夹在可见区域内，
        // 必要时短暂盖住面板顶部
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let anchor = CGPoint(
            x: min(max(frame.midX, visible.minX + Self.imagesHintInset), visible.maxX - Self.imagesHintInset),
            y: min(frame.maxY + Self.imagesHintOffset, visible.maxY - Self.imagesHintOffset))
        HUDToast.show(message, symbolName: "photo.on.rectangle", tint: .accentColor, at: anchor)
    }
}
