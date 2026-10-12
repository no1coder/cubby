import Foundation

/// 隔离见证地址的 Bech32（BIP173，见证版本 0）与 Bech32m（BIP350，见证版本 1–16）解码
enum Bech32 {
    struct Segwit: Equatable {
        let version: Int
        let program: [UInt8]
    }

    private enum Encoding {
        case bech32
        case bech32m
    }

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
    private static let values: [UInt8: UInt8] = Dictionary(
        uniqueKeysWithValues: charset.enumerated().map { ($0.element, UInt8($0.offset)) })
    private static let generator: [UInt32] = [0x3B6A_57B2, 0x2650_8E6D, 0x1EA1_19FA, 0x3D42_33DD, 0x2A14_62B3]
    private static let bech32Constant: UInt32 = 1
    private static let bech32mConstant: UInt32 = 0x2BC8_30A3
    private static let maxLength = 90
    private static let checksumLength = 6
    private static let separator = UInt8(ascii: "1")

    /// 按 hrp（如 bc、ltc）解码隔离见证地址；格式、校验和、版本与程序长度任一不合规则为 nil
    static func decodeSegwit(hrp expectedHRP: String, _ text: String) -> Segwit? {
        guard let (hrp, data, encoding) = decode(text), hrp == expectedHRP, let version = data.first,
            version <= 16
        else { return nil }
        // 版本 0 必须用 Bech32，其余用 Bech32m
        guard encoding == (version == 0 ? .bech32 : .bech32m),
            let program = convertToBytes(Array(data.dropFirst())),
            (2...40).contains(program.count),
            version != 0 || program.count == 20 || program.count == 32
        else { return nil }
        return Segwit(version: Int(version), program: program)
    }

    /// 通用解码：返回小写 hrp、去掉校验和的 5 位数据与校验和类型
    private static func decode(_ text: String) -> (String, [UInt8], Encoding)? {
        let bytes = Array(text.utf8)
        guard bytes.count <= maxLength, bytes.allSatisfy({ (33...126).contains($0) }) else { return nil }
        // 不允许大小写混合
        let hasLower = bytes.contains { (97...122).contains($0) }
        let hasUpper = bytes.contains { (65...90).contains($0) }
        guard !(hasLower && hasUpper) else { return nil }
        let lowered = Array(text.lowercased().utf8)
        guard let separatorIndex = lowered.lastIndex(of: separator), separatorIndex >= 1,
            separatorIndex + checksumLength + 1 <= lowered.count
        else { return nil }

        let hrp = Array(lowered[..<separatorIndex])
        var data: [UInt8] = []
        for character in lowered[(separatorIndex + 1)...] {
            guard let value = values[character] else { return nil }
            data.append(value)
        }
        let checksum = polymod(expandedHRP(hrp) + data)
        let encoding: Encoding
        switch checksum {
        case bech32Constant: encoding = .bech32
        case bech32mConstant: encoding = .bech32m
        default: return nil
        }
        return (String(decoding: hrp, as: UTF8.self), Array(data.dropLast(checksumLength)), encoding)
    }

    private static func expandedHRP(_ hrp: [UInt8]) -> [UInt8] {
        hrp.map { $0 >> 5 } + [0] + hrp.map { $0 & 31 }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1FF_FFFF) << 5 ^ UInt32(value)
            for (index, constant) in generator.enumerated() where (top >> UInt32(index)) & 1 == 1 {
                checksum ^= constant
            }
        }
        return checksum
    }

    /// 5 位 → 8 位转换；剩余补位超过 4 位或不全为零则无效（BIP173 规定不补位）
    private static func convertToBytes(_ data: [UInt8]) -> [UInt8]? {
        let from = 5
        let to = 8
        var accumulator = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << to) - 1
        // 只保留尚未输出的位，避免长输入时左移溢出
        let maxAccumulator = (1 << (from + to - 1)) - 1
        for value in data {
            accumulator = ((accumulator << from) | Int(value)) & maxAccumulator
            bits += from
            while bits >= to {
                bits -= to
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        guard bits < from, (accumulator << (to - bits)) & maxValue == 0 else { return nil }
        return result
    }
}
