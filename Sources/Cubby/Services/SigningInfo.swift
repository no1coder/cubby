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

        /// 系统辅助功能授权所绑定的「身份」：有团队 ID 时按团队 + bundle 绑定，ad-hoc 时绑定 cdhash
        var authorizationKey: String {
            if let teamID, !isAdHoc { return "team:\(teamID)" }
            return "adhoc:\(cdhash ?? "unknown")"
        }

        var summary: String {
            if let teamID, !isAdHoc {
                return String(localized: "Developer (Team \(teamID))", comment: "Diagnostics: code signature")
            }
            return isAdHoc ? "ad-hoc" : String(localized: "Unknown", comment: "Diagnostics: unknown value")
        }
    }

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
        return Identity(teamID: teamID, cdhash: cdhash, isAdHoc: isAdHoc)
    }
}
