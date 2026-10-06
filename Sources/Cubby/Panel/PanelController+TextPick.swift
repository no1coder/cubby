import AppKit
import CubbyCore

// 面板控制器里的拆词接线（docs/TEXT-PICK-DESIGN.md P9、P10）：把粘贴 / 复制所选接到粘贴流程。
// 结果以纯文本写入剪贴板并带本应用的写入标记——监听器跳过，不在历史里堆出片段条目

extension PanelController {
    func configureTextPick() {
        viewModel.onPastePicked = { [weak self] request in self?.performPicked(request) }
        viewModel.onCopyPicked = { [weak self] request in self?.paster.write(plainText: request.text) ?? false }
    }

    /// 粘贴所选：写入后与条目粘贴同一投递段——提升原条目 → 无动画隐藏面板 → ⌘V（没有直接粘贴时提示已复制）
    private func performPicked(_ request: TextPickRequest) {
        guard paster.write(plainText: request.text) else {
            NSSound.beep()
            viewModel.showToast(.error(TextPickCopy.copyFailed))
            return
        }
        paster.deliver(
            promoting: request.itemID, copyOnly: false, target: viewModel.target, anchor: anchor,
            copied: PanelPaster.copiedMessage, pasted: nil
        ) { hide(animated: false) }
    }
}
