import Foundation
import Security

/// 当前运行进程的代码签名信息（用于判断授权失效与诊断）
enum SigningInfo {
    struct Identity: Equatable {
        /// Developer ID / Apple Development 证书所属团队；ad-hoc 签名为 nil
        let teamID: String?
        /// 代码目录哈希（每次构建都会变化）
        let cdhash: String?
        let isAdHoc: Bool
        /// 指定要求（designated requirement）：系统隐私授权条目实际绑定的就是它，
        /// 区分证书类型（同一团队的 Apple Development 与 Developer ID 不同），ad-hoc 时为 cdhash
        let designatedRequirement: String?

        /// 用于判断授权失效的签名键（见 SignedGrant）：首个为当前格式，其余兼容 0.3.2 及更早版本记下的格式
        var authorizationKeys: [String] {
            let legacy = if let teamID, !isAdHoc { "team:\(teamID)" } else { "adhoc:\(cdhash ?? "unknown")" }
            guard let designatedRequirement else { return [legacy] }
            return ["req:\(designatedRequirement)", legacy]
        }

        var summary: String {
            if let teamID, !isAdHoc {
                return String(localized: "Developer (Team \(teamID))", comment: "Diagnostics: code signature")
            }
            return isAdHoc ? "ad-hoc" : String(localized: "Unknown", comment: "Diagnostics: unknown value")
        }
    }

    /// 启动时读取一次并缓存：签名在进程生命周期内不变；而且运行中应用包可能被新版本覆盖，
    /// 再读磁盘会拿到新版本的签名，把它误记为「已授权的签名」（见 SignedGrantRecord）
    static let launched: Identity? = current()

    /// 读取失败（例如未签名的调试可执行文件）时返回 nil
    static func current() -> Identity? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
            let dictionary = info as? [String: Any]
        else { return nil }

        let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let cdhash = (dictionary[kSecCodeInfoUnique as String] as? Data)?
            .map { String(format: "%02x", $0) }
            .joined()
        let codeFlags = (dictionary[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        // kSecCodeSignatureAdhoc = 0x0002
        let isAdHoc = codeFlags & 0x0002 != 0 || teamID == nil
        return Identity(
            teamID: teamID, cdhash: cdhash, isAdHoc: isAdHoc,
            designatedRequirement: designatedRequirement(of: staticCode))
    }

    private static func designatedRequirement(of staticCode: SecStaticCode) -> String? {
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement
        else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }
}
