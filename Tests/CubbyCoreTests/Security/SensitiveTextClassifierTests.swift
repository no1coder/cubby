import Foundation
import Testing
@testable import CubbyCore

/// 加密货币地址识别（BIP173 / BIP350 官方向量只取主网 bc）
@Suite("敏感内容识别：加密货币地址")
struct SensitiveTextClassifierTests {
    private func kind(_ text: String) -> SensitiveKind? {
        SensitiveTextClassifier.classify(text)?.kind
    }

    // MARK: - 比特币

    @Test(
        "比特币 Base58Check（1… / 3…）",
        arguments: [
            "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
            "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy",
            "16L5yRNPTuciSgXGHqYwn9N6NeoKqopAu",
            "31nM1WuowNDzocNxPPW9NQWJEtwWpjfcLj",
        ])
    func bitcoinBase58(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .bitcoin, value: text))
    }

    @Test(
        "比特币 Bech32 / Bech32m 有效向量（BIP173、BIP350）",
        arguments: [
            "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4",
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
            "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y",
            "BC1SW50QGDZ25J",
            "bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs",
            "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0",
        ])
    func bitcoinBech32Valid(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .bitcoin, value: text))
    }

    @Test(
        "比特币 Bech32 / Bech32m 无效向量（BIP350）",
        arguments: [
            // 见证版本 1 却用 Bech32 校验和
            "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd",
            // 版本 16 用 Bech32
            "BC1S0XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ54WELL",
            // 版本 0 用 Bech32m
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh",
            // BIP173 时代的 v1 地址（Bech32），BIP350 后无效
            "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7k7grplx",
            // 非法字符 o
            "bc1p38j9r5y49hruaue7wxjce0updqjuyyx0kh56v8s25huc6995vvpql3jow4",
            // 见证版本 17
            "BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R",
            // 程序长度 1
            "bc1pw5dgrnzv",
            // 程序长度 41
            "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav253zgeav",
            // 版本 0 程序长度 16
            "BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P",
            // 大小写混合
            "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq",
            // 补零超过 4 位
            "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qwwzcrf",
            // 8→5 位转换的补位不为零
            "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j",
            // 数据段为空
            "bc1gmk9yu",
            // 版本 0 程序长度 25（不是 20 / 32）
            "bc1qqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9cc7vgsh7",
            // 测试网
            "tb1qqypqxpq9qcrsszg2pvxq6rs0zqg3yyc5r7fxez",
        ])
    func bitcoinBech32Invalid(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == nil)
    }

    @Test(
        "Base58Check 校验和错误、版本不对、长度不对时不算",
        arguments: [
            "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb",  // 改了最后一位
            "mfcHP2WMCVLsVZA8yrovmhMgxNFW9r98xw",  // 测试网版本 0x6f
            "12D2adLM3UKy4Z4giRbReR6gjWx1w6Dz",  // 版本 0 但只有 24 字节
        ])
    func base58CheckInvalid(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == nil)
    }

    // MARK: - 以太坊

    @Test(
        "以太坊 EIP-55 有效地址与全小写 / 全大写",
        arguments: [
            "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
            "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
            "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
            "0x52908400098527886E0F7030069857D2E4169EE7",
            "0xde709f2102306220921060314715629080e2fb77",
            "0x0000000000000000000000000000000000000000",
        ])
    func ethereumValid(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .ethereum, value: text))
    }

    @Test("以太坊大小写混合时翻转任意一个字母的大小写都不通过")
    func ethereumFlippedCase() {
        let address = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        var characters = Array(address)
        for index in characters.indices.dropFirst(2) where characters[index].isLetter {
            let original = characters[index]
            characters[index] = Character(
                original.isUppercase ? original.lowercased() : original.uppercased())
            #expect(SensitiveTextClassifier.classify(String(characters)) == nil, "index \(index)")
            characters[index] = original
        }
    }

    @Test(
        "不是 0x + 40 位十六进制的不算以太坊",
        arguments: [
            "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beae",  // 39 位
            "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaedd",  // 41 位
            "0X5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED",  // 大写 X
            "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaeg",  // 非十六进制
            "5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",  // 没有 0x（同 git SHA 长度）
        ])
    func ethereumInvalid(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == nil)
    }

    // MARK: - 波场、莱特币、Solana

    @Test(
        "波场 Base58Check（版本 0x41）",
        arguments: [
            "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7",
            "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            "TA4Y62o6YC2Zsck9rZVGTvqW1AQ7X9zTnj",
        ])
    func tron(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .tron, value: text))
    }

    @Test("波场校验和错误不算")
    func tronBadChecksum() {
        #expect(SensitiveTextClassifier.classify("TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6u") == nil)
    }

    @Test(
        "莱特币 L… / M… 与 ltc1…",
        arguments: [
            "LKKHMBjCU89fyFNgSRprDoD8Jb25N8uWvd",
            "M7zVKQKmtV5Rc7erVGVVC3khZbXxsS5HEX",
            "ltc1qqypqxpq9qcrsszg2pvxq6rs0zqg3yyc5dyg36p",
            "LTC1QQYPQXPQ9QCRSSZG2PVXQ6RS0ZQG3YYC5DYG36P",
            "ltc1qqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydpk8qarc0sp89z3m",
            "ltc1pqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydpk8qarc0sts9tf8",
        ])
    func litecoin(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .litecoin, value: text))
    }

    @Test("莱特币 v1 用 Bech32 校验和不算")
    func litecoinWrongChecksumVariant() {
        #expect(
            SensitiveTextClassifier.classify("ltc1pqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydpk8qarc0s7v48v9") == nil)
    }

    @Test(
        "Solana：Base58 解码为 32 字节",
        arguments: [
            "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T",
            "11111111111111111111111111111111",
            "So11111111111111111111111111111111111111112",
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        ])
    func solana(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .solana, value: text))
    }

    @Test(
        "Solana：解码不是 32 字节或长度不在 32–44 时不算",
        arguments: [
            "8zUFfLHADcabAoM9YFZYEosLosi2GDmsDuzfcSEkxG",  // 31 字节
            "3gg7zkoxVU7JxPZJKyGXwMsAZSsgimSpEP8aqGiFJNa7r",  // 33 字节
            "1111111111111111111111111111111",  // 31 个 1
            "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB40",  // 含 0
        ])
    func solanaInvalid(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == nil)
    }

    // MARK: - 通用规则

    @Test("去掉首尾空白与换行；值为去空白后的文本")
    func trimsWhitespace() {
        let text = "  \n0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed\t\n"
        #expect(
            SensitiveTextClassifier.classify(text)
                == SensitiveValue(kind: .ethereum, value: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"))
    }

    @Test("只看整段文本，不在长文里搜")
    func wholeTextOnly() {
        #expect(kind("send to 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed please") == nil)
        #expect(kind("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa\n1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa") == nil)
    }

    @Test("很长的文本直接跳过（包括长串 Base58 字符与数字）")
    func longText() {
        #expect(kind(String(repeating: "1", count: 10_000)) == nil)
        #expect(kind(String(repeating: "4111111111111111 ", count: 1_000)) == nil)
    }

    @Test("类型不在 kinds 里时不识别")
    func respectsKinds() {
        let eth = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        #expect(SensitiveTextClassifier.classify(eth, kinds: [.bitcoin]) == nil)
        #expect(SensitiveTextClassifier.classify(eth, kinds: [.ethereum])?.kind == .ethereum)
        #expect(SensitiveTextClassifier.classify("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", kinds: []) == nil)
        // 关掉比特币时比特币地址也不会被当成 Solana
        #expect(SensitiveTextClassifier.classify("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", kinds: [.solana]) == nil)
        #expect(
            SensitiveTextClassifier.classify("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", kinds: [.litecoin]) == nil)
        #expect(SensitiveTextClassifier.classify("TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7", kinds: [.bitcoin]) == nil)
        #expect(SensitiveTextClassifier.classify("11111111111111111111111111111111", kinds: [.bitcoin]) == nil)
    }

    @Test(
        "普通文本、链接、电话、其他长度的哈希与 git SHA 不识别",
        arguments: [
            "",
            "   ",
            "hello world",
            "Hello",
            "https://example.com/1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
            "+86 138 0013 8000",
            "13800138000",
            "(555) 123-4567",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",  // SHA-256
            "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",  // 0x + 64 位
            "d41d8cd98f00b204e9800998ecf8427e",  // MD5
            "160f4c5",  // 短 SHA
            "160f4c5a1b2c3d4e5f60718293a4b5c6d7e8f901",  // 完整 git SHA
            "ThisIsALongPascalCaseIdentifierName",
            "2026-10-12",
            "\u{1F600}\u{1F600}\u{1F600}",
        ])
    func ordinaryText(text: String) {
        #expect(SensitiveTextClassifier.classify(text) == nil)
    }
}
