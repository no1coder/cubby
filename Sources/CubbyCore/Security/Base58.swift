import CryptoKit
import Foundation

/// 比特币字母表的 Base58（不含 0 O I l），以及带双 SHA-256 校验和的 Base58Check
enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    private static let checksumLength = 4

    /// 字符 → 数值，不在字母表里的为 nil
    private static let digits: [UInt8: UInt8] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, UInt8($0.offset)) })

    /// 解码；含字母表以外的字符（含非 ASCII，其 UTF-8 字节都不在字母表里）时为 nil。每个前导 1 对应一个零字节
    static func decode(_ text: String) -> [UInt8]? {
        let characters = Array(text.utf8)
        var number: [UInt8] = []  // 大端字节，逐位乘 58 累加
        for character in characters {
            guard let digit = digits[character] else { return nil }
            var carry = Int(digit)
            for index in number.indices.reversed() {
                carry += Int(number[index]) * 58
                number[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                number.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }
        let leadingZeros = characters.prefix { $0 == alphabet[0] }.count
        // number 为 0 时可能留下前导零字节，去掉后再按前导 1 补零
        let significant = number.drop { $0 == 0 }
        return [UInt8](repeating: 0, count: leadingZeros) + significant
    }

    /// Base58Check：校验和通过时返回去掉最后 4 字节校验和的负载（含版本字节），否则为 nil
    static func decodeCheck(_ text: String) -> [UInt8]? {
        guard let bytes = decode(text), bytes.count > checksumLength else { return nil }
        let payload = Array(bytes.dropLast(checksumLength))
        let checksum = Array(bytes.suffix(checksumLength))
        let first = SHA256.hash(data: payload)
        let second = SHA256.hash(data: Data(first))
        return Array(second.prefix(checksumLength)) == checksum ? payload : nil
    }
}
