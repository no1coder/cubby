import Foundation
import Testing
@testable import CubbyCore

/// 地址校验用到的底层算法：Keccak-256、Base58、Bech32 / Bech32m
@Suite("地址校验底层算法")
struct SecurityPrimitivesTests {
    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keccak

    @Test("Keccak-256 空输入（原始 Keccak 填充，不是 SHA3-256）")
    func keccakEmpty() {
        #expect(
            hex(Keccak256.hash([]))
                == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    }

    @Test("Keccak-256 短文本")
    func keccakHelloWorld() {
        #expect(
            hex(Keccak256.hash(Array("hello world".utf8)))
                == "47173285a8d7341e5e972fc677286384f802f8ef42a5ec5f03bbfa254cb01fad")
    }

    /// 同一个海绵结构换成 SHA3 的填充（0x06）后与 Python hashlib.sha3_256 对照，覆盖跨块与恰好整块的输入
    @Test(
        "海绵结构用 SHA3 填充时与标准 SHA3-256 一致（含跨块、整块边界）",
        arguments: [
            (0, "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"),
            (135, "7d080d7ba978a75c8a7d1f9be566c859084509c9c2b4928435c225d5777d98e3"),
            (136, "e772c9cf9eb9c991cdfcf125001b454fdbc0a95f188d1b4c844aa032ad6e075e"),
        ])
    func sha3Boundaries(length: Int, expected: String) {
        #expect(hex(Keccak256.hash([UInt8](repeating: 0, count: length), padding: 0x06)) == expected)
    }

    @Test("海绵结构处理多块输入")
    func sha3MultiBlock() {
        let input = (0..<200).map { UInt8($0) }
        #expect(
            hex(Keccak256.hash(input, padding: 0x06))
                == "5f728f63bf5ee48c77f453c0490398fa645b8d4c4e56be9a41cfec344d6ca899")
    }

    // MARK: - Base58

    @Test("Base58 解码：前导 1 是零字节")
    func base58LeadingOnes() {
        #expect(Base58.decode("11111111111111111111111111111111") == [UInt8](repeating: 0, count: 32))
        #expect(Base58.decode("1") == [0])
        #expect(Base58.decode("") == [])
        #expect(Base58.decode("2") == [1])
        #expect(Base58.decode("z") == [57])
        #expect(Base58.decode("21") == [58])
    }

    @Test("Base58 拒绝字母表以外的字符（0 O I l 与非 ASCII）", arguments: ["0", "O", "I", "l", "abc+", "é", "1 1"])
    func base58RejectsInvalidCharacters(text: String) {
        #expect(Base58.decode(text) == nil)
    }

    @Test("Base58Check：校验和通过时返回去掉校验和的负载")
    func base58Check() throws {
        let payload = try #require(Base58.decodeCheck("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"))
        #expect(payload.count == 21)
        #expect(payload.first == 0x00)
        #expect(Base58.decodeCheck("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb") == nil)
        #expect(Base58.decodeCheck("111") == nil)
    }

    // MARK: - Bech32

    @Test("Bech32 隔离见证解码：版本与程序")
    func bech32Segwit() throws {
        let decoded = try #require(Bech32.decodeSegwit(hrp: "bc", "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4"))
        #expect(decoded.version == 0)
        #expect(hex(decoded.program) == "751e76e8199196d454941c45d1b3a323f1433bd6")
    }

    @Test("Bech32 前缀不匹配时不解码")
    func bech32WrongHRP() {
        #expect(Bech32.decodeSegwit(hrp: "ltc", "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4") == nil)
        #expect(Bech32.decodeSegwit(hrp: "bc", "tb1qqypqxpq9qcrsszg2pvxq6rs0zqg3yyc5r7fxez") == nil)
    }

    @Test(
        "Bech32 拒绝格式问题",
        arguments: [
            "bc1",  // 没有数据
            "1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",  // 没有前缀
            "bcqw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",  // 没有分隔符
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb",  // 数据里出现 b（不在字母表）
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t\u{7F}",  // 控制字符
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t\u{E9}",  // 非 ASCII
        ])
    func bech32RejectsMalformed(text: String) {
        #expect(Bech32.decodeSegwit(hrp: "bc", text) == nil)
    }

    @Test("Bech32 超过 90 个字符时拒绝")
    func bech32TooLong() {
        let long = "bc1q" + String(repeating: "q", count: 90)
        #expect(Bech32.decodeSegwit(hrp: "bc", long) == nil)
    }
}
