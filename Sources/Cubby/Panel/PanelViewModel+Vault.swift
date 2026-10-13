import CubbyCore
import Foundation

/// 加密 Vault 在面板上的呈现（docs/HISTORY-ENCRYPTION-DESIGN.md §4、E8 ①）：
/// 「历史已锁定」横幅随 Vault 状态实时出现 / 消失（重试成功后立即消失）；准备 / 迁移期间列表处显示占位
extension PanelViewModel {
    /// 实时的「历史已锁定」横幅
    var vaultWarning: PanelWarning? {
        vault?.status == .locked ? .historyLocked : nil
    }

    /// Vault 还在准备或迁移：列表处显示「正在加密历史…」占位（期间复制的内容就绪后并入历史）
    var isVaultPreparing: Bool {
        vault?.status.isPreparing == true
    }

    /// 「历史已锁定」的「重试」：重新读取钥匙串，成功后合并内存中的条目并开启写盘。返回是否处理
    func performVaultAction(_ warning: PanelWarning) -> Bool {
        guard warning == .historyLocked else { return false }
        vault?.retryUnlock()
        return true
    }
}

extension PanelWarning {
    /// 「历史已锁定」与读取历史的其他问题同一位置：排在「从临时位置运行」之后、权限类提醒之前
    static func insertingVault(_ warning: PanelWarning?, into warnings: [PanelWarning]) -> [PanelWarning] {
        guard let warning, !warnings.contains(warning) else { return warnings }
        let index = warnings.first == .runningFromTemporaryLocation ? 1 : 0
        return Array(warnings[..<index]) + [warning] + warnings[index...]
    }
}
