/// 系统隐私授权（辅助功能、屏幕录制）的状态，区分「从未授权」与「授权已失效」
public enum SignedGrantStatus: String, Sendable {
    case granted
    case notGranted
    /// 曾经授权过，但签名变化导致系统设置里的旧条目不再匹配（开关仍显示开启）
    case stale
}

public struct SignedGrantEvaluation: Equatable, Sendable {
    public let status: SignedGrantStatus
    /// 需要写回的签名键；nil 表示记录无需变化
    public let keyToRecord: String?

    public init(status: SignedGrantStatus, keyToRecord: String?) {
        self.status = status
        self.keyToRecord = keyToRecord
    }
}

/// 系统授权条目绑定代码签名的「指定要求」（designated requirement）：
/// 证书类型变化（同一团队的 Apple Development 与 Developer ID 也算）或 ad-hoc 重新签名后，
/// 系统设置里的开关仍显示开启，但对新版本不再生效。
/// 每次确认授权有效时记下当时的签名键；之后未授权且记录与当前签名都不匹配，即判定为失效。
public enum SignedGrant {
    /// - Parameters:
    ///   - isGranted: 系统接口报告的当前授权状态
    ///   - recorded: 最近一次确认授权有效时记下的签名键
    ///   - currentKeys: 当前签名可接受的签名键，首个为当前格式（写入记录用），其余兼容旧版本记下的格式；
    ///     读不到签名时为空
    public static func evaluate(isGranted: Bool, recorded: String?, currentKeys: [String]) -> SignedGrantEvaluation {
        if isGranted {
            let key = currentKeys.first.flatMap { $0 == recorded ? nil : $0 }
            return SignedGrantEvaluation(status: .granted, keyToRecord: key)
        }
        guard let recorded, !currentKeys.isEmpty, !currentKeys.contains(recorded) else {
            return SignedGrantEvaluation(status: .notGranted, keyToRecord: nil)
        }
        return SignedGrantEvaluation(status: .stale, keyToRecord: nil)
    }
}
