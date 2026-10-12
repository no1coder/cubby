import Foundation

/// 地址守护识别的敏感内容类型（docs/UI-UPGRADE-PLAN.md §6.1）。rawValue 写入设置，不要改
public enum SensitiveKind: String, Codable, CaseIterable, Sendable {
    case bitcoin
    case ethereum
    case tron
    case solana
    case litecoin
    case bankCard
}

/// 识别出的敏感值：类型 + 规范化后的值（去首尾空白；银行卡号只保留数字）
public struct SensitiveValue: Equatable, Hashable, Sendable {
    public let kind: SensitiveKind
    public let value: String

    public init(kind: SensitiveKind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// 是不是同一个值：以太坊地址不分大小写（EIP-55 校验写法与全小写是同一个地址），其余逐字相同
    public func isSame(as other: SensitiveValue) -> Bool {
        guard kind == other.kind else { return false }
        guard kind == .ethereum else { return value == other.value }
        return value.lowercased() == other.value.lowercased()
    }
}
