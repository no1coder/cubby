#if DEBUG
import AppKit
import CubbyCore

/// 地址守护的调试走查（--scenario security:*）：虚构的地址与记录，不读写真实剪贴板、不注册全局热键。
/// 面板场景的条目来自 --demo-history（DesignDemoHistory 里的以太坊、波场、银行卡与一条被替换进来的记录）
enum SecurityDemo {
    static let prefix = "security:"

    /// 演示地址：原值为 EIP-55 的示例地址；替换值首尾各与原值相同、中间 32 位不同（攻击者常用的手法）
    static let original = SensitiveValue(kind: .ethereum, value: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    static let replacement = SensitiveValue(
        kind: .ethereum, value: "0x5aAe" + "1b8De027C4f9A3b07E62d59C0a418B2d" + "eAed")
    static let tron = SensitiveValue(kind: .tron, value: "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7")
    static let bankCard = "4111 1111 1111 1111"
    static let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")

    /// 演示历史里这几条的 ID（DesignDemoHistory 按序号生成）与安全记录里被替换的那条记录
    static let tamperedEntryID = UUID(uuidString: "5EC0E0D0-0000-4000-8000-000000000001") ?? UUID()

    /// 复制后 0.4 秒被替换
    static func incident(checkedKeystrokes: Bool, now: Date = Date()) -> TamperIncident {
        let copy = AddressGuard.Copy(
            value: original, date: now.addingTimeInterval(-0.4), frontmostBundleID: safari.bundleID, source: safari)
        let tamper = AddressGuard.Tamper(
            original: copy, replacement: replacement, date: now, frontmostBundleID: safari.bundleID,
            checkedKeystrokes: checkedKeystrokes)
        return TamperIncident(entryID: tamperedEntryID, tamper: tamper, appName: safari.name)
    }

    /// 设置页与面板用的演示安全记录（新的在前）
    static func log(tamperedItemID: UUID, now: Date) -> SecurityLog {
        let day: TimeInterval = 24 * 3600
        let abbreviated = AddressComparison.abbreviated
        return SecurityLog(entries: [
            SecurityLogEntry(
                date: now.addingTimeInterval(-60), event: .pasteVerified, kind: .ethereum,
                summary: abbreviated(original.value), appName: "Wallet"),
            SecurityLogEntry(
                date: now.addingTimeInterval(-120), event: .restored, kind: .ethereum,
                summary: abbreviated(original.value), appName: safari.name),
            SecurityLogEntry(
                id: tamperedEntryID, date: now.addingTimeInterval(-121), event: .tampered, kind: .ethereum,
                summary: abbreviated(replacement.value), appName: safari.name, tamperedItemID: tamperedItemID),
            SecurityLogEntry(
                date: now.addingTimeInterval(-day + 600), event: .pasteVerified, kind: .tron,
                summary: abbreviated(tron.value), appName: "Chrome"),
        ])
    }
}

extension AppDelegate {
    /// security:alert / security:alert:no-monitoring 警示卡（菜单栏随之变成红色胶囊）；security:hud 粘贴核对 HUD；
    /// security:panel 面板停在演示历史的地址条目上（需要 --demo-history）
    func applySecurityScenario(_ scenario: String) {
        guard let addressGuard else { return }
        switch scenario {
        case "security:alert", "security:alert:no-monitoring":
            let incident = SecurityDemo.incident(checkedKeystrokes: scenario == "security:alert")
            addressGuard.debugInsert(incident, markPending: true)
            tamperAlert?.show(incident)
        case "security:hud":
            guard let anchor = HUDToast.defaultAnchor() else { return }
            PasteCheckHUD.show(SecurityDemo.original, pasted: true, app: "Wallet", at: anchor, duration: .seconds(600))
        case "security:panel":
            showSecurityPanel(addressGuard)
        default:
            break
        }
    }

    /// 以太坊地址为「守护中」，被替换的记录能重新打开警示卡；列表滚到这几条
    private func showSecurityPanel(_ addressGuard: AddressGuardController) {
        guard let panel else { return }
        addressGuard.debugGuard(SecurityDemo.original)
        addressGuard.debugInsert(SecurityDemo.incident(checkedKeystrokes: true), markPending: false)
        panel.show()
        // 选中最后一条（银行卡号），列表滚到底，四条都在视野里
        let target = store?.history.items.first { $0.text == SecurityDemo.bankCard }
        if let target { panel.viewModel.select(target) }
    }
}
#endif
