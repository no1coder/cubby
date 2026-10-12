import Foundation
import CubbyCore

/// 地址守护的界面文案（警示卡、面板标记、粘贴核对 HUD、设置 › 剪贴板安全共用）
enum SecurityCopy {
    // MARK: - 类型名称

    /// 设置里的「守护的内容」标签：以太坊写明包含 EVM 链，其余同短名称
    static func chipTitle(_ kind: SensitiveKind) -> String {
        guard kind == .ethereum else { return shortName(kind) }
        return String(localized: "Ethereum & EVM chains", comment: "Settings › Security: guarded content chip")
    }

    /// 短名称：警示卡「以太坊 · 校验通过」、设置里的标签、银行卡的徽标
    static func shortName(_ kind: SensitiveKind) -> String {
        switch kind {
        case .bitcoin: String(localized: "Bitcoin", comment: "Short name of a guarded kind")
        case .ethereum: String(localized: "Ethereum", comment: "Short name of a guarded kind")
        case .tron: String(localized: "TRON", comment: "Short name of a guarded kind")
        case .solana: String(localized: "Solana", comment: "Short name of a guarded kind")
        case .litecoin: String(localized: "Litecoin", comment: "Short name of a guarded kind")
        case .bankCard: String(localized: "Bank card", comment: "Short name of a guarded kind")
        }
    }

    /// 完整名称：卡片上的「以太坊地址 · 校验通过」（句首）与警示卡「你复制以太坊地址 0.4 秒后…」（句中）。
    /// 只有银行卡号在英文里句首与句中写法不同
    static func name(_ kind: SensitiveKind, midSentence: Bool = false) -> String {
        switch kind {
        case .bitcoin: String(localized: "Bitcoin address", comment: "Name of a guarded kind")
        case .ethereum: String(localized: "Ethereum address", comment: "Name of a guarded kind")
        case .tron: String(localized: "TRON address", comment: "Name of a guarded kind")
        case .solana: String(localized: "Solana address", comment: "Name of a guarded kind")
        case .litecoin: String(localized: "Litecoin address", comment: "Name of a guarded kind")
        case .bankCard:
            midSentence
                ? String(localized: "bank card number", comment: "Name of a guarded kind in the middle of a sentence")
                : String(localized: "Bank card number", comment: "Name of a guarded kind at the start of a line")
        }
    }

    /// 「以太坊地址 · 校验通过」；Solana 地址没有校验和，只能说「格式正确」
    /// - Parameter short: 警示卡用短名称（「以太坊 · 校验通过」）
    static func checkLine(_ kind: SensitiveKind, short: Bool = false) -> String {
        let name = short ? shortName(kind) : self.name(kind)
        guard kind != .solana else {
            return String(
                localized: "\(name) · valid format",
                comment: "A guarded value without a checksum (Solana) has the right format. %@ = kind")
        }
        return String(
            localized: "\(name) · checksum valid",
            comment: "A guarded value passed its checksum. %@ = kind, e.g. “Ethereum address”")
    }

    // MARK: - 面板

    static var guarding: String {
        String(localized: "Guarding", comment: "Badge on the address Cubby is guarding (the one you copied last)")
    }

    static var verified: String {
        String(localized: "Verified", comment: "Badge on an address whose checksum is valid")
    }

    static var tamperedSource: String {
        String(
            localized: "Unknown source · replaced the previous item",
            comment: "Header of a history item that replaced the address you copied")
    }

    static var tamperedNote: String {
        String(
            localized: "Not in ⌘1–⌘9 · can't be pasted or copied",
            comment: "Footnote on a history item that replaced the address you copied")
    }

    static var details: String {
        String(localized: "Details", comment: "Button on a replaced item: show the replacement warning again")
    }

    /// 试图粘贴 / 复制被替换进来的条目时底栏的说明
    static var blocked: String {
        String(
            localized: "This item replaced what you copied, so Cubby won't paste or copy it",
            comment: "Panel footer after trying to paste a replaced item")
    }

    // MARK: - 粘贴核对 HUD

    static func pastedMatches(_ app: String) -> String {
        String(
            localized: "Pasted to “\(app)”, matches what you copied",
            comment: "HUD after pasting an address from Cubby and checking it. %@ = app name")
    }

    static var pastedMatchesNoApp: String {
        String(localized: "Pasted, matches what you copied", comment: "HUD after pasting an address and checking it")
    }

    static var copiedMatches: String {
        String(localized: "Copied, matches what you copied", comment: "HUD after copying an address and checking it")
    }

    // MARK: - 菜单栏

    static var statusPill: String {
        String(localized: "Address Replaced", comment: "Status item pill while a replaced address is not handled")
    }
}
