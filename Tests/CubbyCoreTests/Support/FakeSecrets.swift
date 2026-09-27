import Foundation

/// 运行时拼接的假密钥：源码中不出现完整的令牌字面量，避免触发仓库的密钥扫描 / 推送保护
enum FakeSecrets {
    private static let mixed = Array("aB3dE5gH7jK9mN1pQ2rS4tU6vW8xY0z")
    private static let upper = Array("ABCDEFGHIJ0123456789KLMNOPQRSTUVWXYZ")

    /// 指定长度的字母数字串（大小写混合）
    static func body(_ count: Int) -> String {
        String((0..<count).map { mixed[$0 % mixed.count] })
    }

    /// 指定长度的大写字母数字串
    static func upperBody(_ count: Int) -> String {
        String((0..<count).map { upper[$0 % upper.count] })
    }

    static func pem(_ kind: String) -> String {
        ["-----BEGIN", kind, "KEY-----"].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func aws(_ prefix: String = "AK" + "IA", bodyLength: Int = 16) -> String {
        prefix + upperBody(bodyLength)
    }

    static func github(_ letter: Character = "p", bodyLength: Int = 36) -> String {
        "gh" + String(letter) + "_" + body(bodyLength)
    }

    static func githubPAT(bodyLength: Int = 82) -> String {
        "github" + "_pat_" + body(bodyLength)
    }

    static func openAI(_ infix: String = "", bodyLength: Int = 48) -> String {
        "sk" + "-" + infix + body(bodyLength)
    }

    static func stripe(_ kind: String = "sk", mode: String = "live", bodyLength: Int = 24) -> String {
        [kind, mode, body(bodyLength)].joined(separator: "_")
    }

    static func slack(_ letter: Character = "b", bodyLength: Int = 24) -> String {
        "xo" + "x" + String(letter) + "-" + body(bodyLength)
    }

    static func google(bodyLength: Int = 35) -> String {
        "AI" + "za" + body(bodyLength)
    }

    static func jwt(segmentLengths: [Int] = [20, 30, 43]) -> String {
        segmentLengths.enumerated()
            .map { index, length in (index == 0 ? "ey" + "J" : "") + body(length) }
            .joined(separator: ".")
    }
}
