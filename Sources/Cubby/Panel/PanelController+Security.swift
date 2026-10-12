import AppKit
import CubbyCore

// 面板控制器里的地址守护接线（docs/UI-UPGRADE-PLAN.md §6.3）：Cubby 写入剪贴板时告知守护；
// 粘贴 / 复制敏感值后核对剪贴板里的就是这条，成功时显示 2 秒的核对 HUD 并记一条安全记录

extension PanelController {
    /// 地址守护（AppDelegate 注入）：面板标记、禁止粘贴被替换进来的条目、粘贴核对
    var addressGuard: AddressGuardController? {
        get { viewModel.security }
        set { viewModel.security = newValue }
    }

    /// 红色记录上的「详情」：参数为条目 ID
    var showTamperDetails: ((UUID) -> Void)? {
        get { viewModel.onShowTamperDetails }
        set { viewModel.onShowTamperDetails = newValue }
    }

    /// 条目已写入剪贴板：文本条目告知守护（敏感值成为新的守护对象，其余清掉守护）。
    /// 敏感值返回投递前的核对：发送 ⌘V 前（只复制时在提示前）再读一次剪贴板，一致才粘贴；
    /// 开启「粘贴后核对」时，一致后显示核对 HUD 并记一条安全记录
    func guardWrite(of item: ClipItem) -> PasteCheck? {
        guard let addressGuard, addressGuard.isEnabled, case .text(let text) = item.payload else { return nil }
        addressGuard.cubbyWrote(text)
        guard let value = viewModel.sensitiveValues.value(for: item, kinds: settings.guardedKinds) else { return nil }
        let targetName = viewModel.target?.name
        let anchor = anchor
        return PasteCheck(text: text, showsResult: settings.verifiesPastes) { [weak addressGuard] pasted in
            addressGuard?.recordVerifiedPaste(value, appName: targetName)
            PasteCheckHUD.show(value, pasted: pasted, app: pasted ? targetName : nil, at: anchor)
        }
    }
}
