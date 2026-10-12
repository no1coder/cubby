import Foundation

/// Keccak-256（以太坊用的原始 Keccak，填充字节 0x01；与 SHA3-256 的区别只在填充 0x06）。
/// 只用于 EIP-55 校验，输入很短，不追求速度
enum Keccak256 {
    /// 256 位输出时的吞吐量：1600 − 2 × 256 位 = 136 字节
    private static let rate = 136
    private static let outputLength = 32

    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]

    /// ρ 步各 lane 的循环左移位数（按 x + 5y 索引）
    private static let rotations: [UInt64] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14,
    ]

    /// - Parameter padding: 域分隔填充字节，Keccak 为 0x01；传 0x06 即 SHA3-256（测试里用来对照标准实现）
    static func hash(_ message: [UInt8], padding: UInt8 = 0x01) -> [UInt8] {
        var padded = message
        padded.append(padding)
        while padded.count % rate != 0 {
            padded.append(0)
        }
        padded[padded.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        for blockStart in stride(from: 0, to: padded.count, by: rate) {
            for lane in 0..<(rate / 8) {
                state[lane] ^= littleEndianWord(padded, at: blockStart + lane * 8)
            }
            permute(&state)
        }

        var output: [UInt8] = []
        output.reserveCapacity(outputLength)
        for lane in 0..<(outputLength / 8) {
            for byte in 0..<8 {
                output.append(UInt8(truncatingIfNeeded: state[lane] >> (UInt64(byte) * 8)))
            }
        }
        return output
    }

    private static func littleEndianWord(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { word, index in
            word | UInt64(bytes[offset + index]) << (UInt64(index) * 8)
        }
    }

    private static func rotateLeft(_ value: UInt64, _ count: UInt64) -> UInt64 {
        count == 0 ? value : (value << count) | (value >> (64 - count))
    }

    /// Keccak-f[1600]：24 轮 θ ρ π χ ι
    private static func permute(_ state: inout [UInt64]) {
        for roundConstant in roundConstants {
            // θ
            var columns = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                columns[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }
            for x in 0..<5 {
                let mix = columns[(x + 4) % 5] ^ rotateLeft(columns[(x + 1) % 5], 1)
                for y in stride(from: 0, to: 25, by: 5) {
                    state[x + y] ^= mix
                }
            }
            // ρ 与 π：B[y, 2x + 3y] = rot(A[x, y])
            var moved = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    let index = x + 5 * y
                    moved[y + 5 * ((2 * x + 3 * y) % 5)] = rotateLeft(state[index], rotations[index])
                }
            }
            // χ
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 {
                    state[x + y] = moved[x + y] ^ (~moved[(x + 1) % 5 + y] & moved[(x + 2) % 5 + y])
                }
            }
            // ι
            state[0] ^= roundConstant
        }
    }
}
