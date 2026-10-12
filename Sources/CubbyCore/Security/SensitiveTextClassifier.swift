import Foundation

/// 判断一段文本整体是不是一个敏感值（只看整段去首尾空白后的文本，不在长文里搜）。
/// 各类型的校验见 docs/UI-UPGRADE-PLAN.md §6.1：校验和不通过的一律不算
public enum SensitiveTextClassifier {
    /// 最长的候选（Bech32 上限 90），更长的文本直接跳过，避免对长文做无谓的解码
    private static let maxCandidateLength = 90

    /// - Parameter kinds: 只识别这些类型（设置里「守护的内容」）
    public static func classify(
        _ text: String, kinds: Set<SensitiveKind> = Set(SensitiveKind.allCases)
    ) -> SensitiveValue? {
        guard !kinds.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxCandidateLength else { return nil }
        guard let value = recognize(trimmed), kinds.contains(value.kind) else { return nil }
        return value
    }

    /// 按格式识别（不看 kinds）。各格式互斥：以太坊以 0x 开头，Bech32 以 bc1 / ltc1 开头，
    /// Base58Check 地址解码为 25 字节，Solana 为 32 字节，银行卡只含数字与分隔符；
    /// 因此某类型被关掉时不会落到别的类型上（例如比特币地址不会被当成 Solana）
    private static func recognize(_ text: String) -> SensitiveValue? {
        if let kind = ethereum(text) ?? bech32(text) ?? base58Check(text) ?? solana(text) {
            return SensitiveValue(kind: kind, value: text)
        }
        return BankCard.digits(text).map { SensitiveValue(kind: .bankCard, value: $0) }
    }

    // MARK: - 以太坊

    private static let hexDigits = Set("0123456789abcdefABCDEF".utf8)
    private static let ethereumHexLength = 40

    /// 0x + 40 位十六进制；全小写或全大写直接通过，大小写混合必须符合 EIP-55
    private static func ethereum(_ text: String) -> SensitiveKind? {
        guard text.hasPrefix("0x") else { return nil }
        let hex = Array(text.utf8.dropFirst(2))
        guard hex.count == ethereumHexLength, hex.allSatisfy(hexDigits.contains) else { return nil }
        let body = String(decoding: hex, as: UTF8.self)
        if body == body.lowercased() || body == body.uppercased() {
            return .ethereum
        }
        return passesEIP55(body) ? .ethereum : nil
    }

    /// EIP-55：对小写地址做 Keccak-256，第 i 个十六进制半字节 ≥ 8 时第 i 个字母应为大写
    private static func passesEIP55(_ body: String) -> Bool {
        let digest = Keccak256.hash(Array(body.lowercased().utf8))
        for (index, character) in body.utf8.enumerated() where character >= UInt8(ascii: "A") {
            let byte = digest[index / 2]
            let nibble = index.isMultiple(of: 2) ? byte >> 4 : byte & 0x0F
            let isUpper = character <= UInt8(ascii: "F")
            if isUpper != (nibble >= 8) {
                return false
            }
        }
        return true
    }

    // MARK: - Bech32（bc1… / ltc1…）

    private static func bech32(_ text: String) -> SensitiveKind? {
        if Bech32.decodeSegwit(hrp: "bc", text) != nil {
            return .bitcoin
        }
        if Bech32.decodeSegwit(hrp: "ltc", text) != nil {
            return .litecoin
        }
        return nil
    }

    // MARK: - Base58Check（比特币、莱特币、波场）

    /// 版本字节 + 20 字节哈希
    private static let base58CheckPayloadLength = 21
    private static let base58Versions: [UInt8: SensitiveKind] = [
        0x00: .bitcoin, 0x05: .bitcoin,  // 1… P2PKH、3… P2SH（莱特币的旧 P2SH 也是 3…，按比特币算）
        0x30: .litecoin, 0x32: .litecoin,  // L… / M…
        0x41: .tron,  // T…
    ]

    private static func base58Check(_ text: String) -> SensitiveKind? {
        guard let payload = Base58.decodeCheck(text), payload.count == base58CheckPayloadLength,
            let version = payload.first
        else { return nil }
        return base58Versions[version]
    }

    // MARK: - Solana

    private static let solanaLengths = 32...44
    private static let solanaKeyLength = 32

    private static func solana(_ text: String) -> SensitiveKind? {
        guard solanaLengths.contains(text.utf8.count), Base58.decode(text)?.count == solanaKeyLength else {
            return nil
        }
        return .solana
    }
}
