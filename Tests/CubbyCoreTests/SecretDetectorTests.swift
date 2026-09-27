import Foundation
import Testing
@testable import CubbyCore

@Suite("SecretDetector 疑似密钥识别")
struct SecretDetectorTests {
    // MARK: - 正例

    @Test(
        "识别各类密钥 / 令牌",
        arguments: [
            TextSample("PEM 私钥", FakeSecrets.pem("PRIVATE")),
            TextSample("PEM RSA 私钥", FakeSecrets.pem("RSA PRIVATE") + "\nMIIEowIBAAKCAQEA"),
            TextSample("PEM EC 私钥", FakeSecrets.pem("EC PRIVATE")),
            TextSample("PEM OpenSSH 私钥", FakeSecrets.pem("OPENSSH PRIVATE")),
            TextSample("PEM 加密私钥", FakeSecrets.pem("ENCRYPTED PRIVATE")),
            TextSample("AWS AKIA", FakeSecrets.aws()),
            TextSample("AWS ASIA（临时凭证）", FakeSecrets.aws("AS" + "IA")),
            TextSample("GitHub ghp_", FakeSecrets.github("p")),
            TextSample("GitHub gho_", FakeSecrets.github("o")),
            TextSample("GitHub ghu_", FakeSecrets.github("u")),
            TextSample("GitHub ghs_", FakeSecrets.github("s")),
            TextSample("GitHub ghr_", FakeSecrets.github("r")),
            TextSample("GitHub ghp_ 超过 36 位", FakeSecrets.github("p", bodyLength: 40)),
            TextSample("GitHub 细粒度 PAT", FakeSecrets.githubPAT()),
            TextSample("GitHub 细粒度 PAT 恰好 50 位", FakeSecrets.githubPAT(bodyLength: 50)),
            TextSample("OpenAI sk-", FakeSecrets.openAI()),
            TextSample("OpenAI sk-proj-", FakeSecrets.openAI("proj-", bodyLength: 40)),
            TextSample("Anthropic sk-ant-", FakeSecrets.openAI("ant-api03-", bodyLength: 90)),
            TextSample("sk- 恰好 20 位", FakeSecrets.openAI(bodyLength: 20)),
            TextSample("Stripe sk_live", FakeSecrets.stripe("sk", mode: "live")),
            TextSample("Stripe sk_test", FakeSecrets.stripe("sk", mode: "test")),
            TextSample("Stripe rk_live", FakeSecrets.stripe("rk", mode: "live")),
            TextSample("Stripe rk_test", FakeSecrets.stripe("rk", mode: "test")),
            TextSample("Stripe 恰好 16 位", FakeSecrets.stripe(bodyLength: 16)),
            TextSample("Slack xoxb", FakeSecrets.slack("b")),
            TextSample("Slack xoxp", FakeSecrets.slack("p")),
            TextSample("Slack xoxa", FakeSecrets.slack("a")),
            TextSample("Slack xoxr", FakeSecrets.slack("r")),
            TextSample("Slack xoxs", FakeSecrets.slack("s")),
            TextSample("Slack 恰好 10 位", FakeSecrets.slack("b", bodyLength: 10)),
            TextSample("Google AIza", FakeSecrets.google()),
            TextSample("JWT", FakeSecrets.jwt()),
            TextSample("JWT 各段恰好 10 位", FakeSecrets.jwt(segmentLengths: [10, 10, 10])),
        ])
    func detectsSecrets(_ sample: TextSample) {
        #expect(SecretDetector.containsSecret(sample.text))
    }

    @Test(
        "密钥嵌在常见上下文中也能识别",
        arguments: [
            TextSample("环境变量", "export AWS_ACCESS_KEY_ID=" + FakeSecrets.aws()),
            TextSample("JSON", #"{"api_key": ""# + FakeSecrets.openAI() + #""}"#),
            TextSample("Bearer 头", "Authorization: Bearer " + FakeSecrets.jwt()),
            TextSample("多行文本第三行", "配置如下：\n注意保密\ntoken: " + FakeSecrets.github()),
            TextSample("前有 emoji", "🔑 " + FakeSecrets.google()),
            TextSample("中文紧邻", "密钥是" + FakeSecrets.slack()),
            TextSample("URL 参数", "https://api.example.com/v1?key=" + FakeSecrets.google()),
        ])
    func detectsInContext(_ sample: TextSample) {
        #expect(SecretDetector.containsSecret(sample.text))
    }

    @Test(
        "前后紧邻中文（中文属于 \\w）时仍能识别",
        arguments: [
            FakeSecrets.aws(), FakeSecrets.github(), FakeSecrets.githubPAT(), FakeSecrets.openAI(),
            FakeSecrets.stripe(), FakeSecrets.slack(), FakeSecrets.google(), FakeSecrets.jwt(),
        ])
    func detectsAdjacentToCJK(_ key: String) {
        #expect(SecretDetector.containsSecret("我的密钥是" + key), "前缀紧邻")
        #expect(SecretDetector.containsSecret(key + "已作废"), "后缀紧邻")
        #expect(SecretDetector.containsSecret("令牌" + key + "请勿外传"), "两侧紧邻")
    }

    @Test(
        "紧邻 ASCII 字母数字或下划线时仍不识别（避免匹配更长的标识符）",
        arguments: [
            "X" + FakeSecrets.aws(), FakeSecrets.aws() + "9", "_" + FakeSecrets.github(),
            FakeSecrets.google() + "a", FakeSecrets.stripe() + "_x",
        ])
    func rejectsAdjacentToASCIIWordCharacters(_ text: String) {
        #expect(!SecretDetector.containsSecret(text))
    }

    // MARK: - 近似但不满足条件的反例

    @Test(
        "长度或格式不满足时不识别",
        arguments: [
            TextSample("AWS 主体 15 位", FakeSecrets.aws(bodyLength: 15)),
            TextSample("AWS 主体 17 位（超出单词边界）", FakeSecrets.aws(bodyLength: 17)),
            TextSample("AWS 小写", FakeSecrets.aws().lowercased()),
            TextSample("AWS 前缀嵌在单词中", "X" + FakeSecrets.aws()),
            TextSample("GitHub 35 位", FakeSecrets.github("p", bodyLength: 35)),
            TextSample("GitHub 未知类型字母", FakeSecrets.github("x")),
            TextSample("GitHub PAT 49 位", FakeSecrets.githubPAT(bodyLength: 49)),
            TextSample("sk- 19 位", FakeSecrets.openAI(bodyLength: 19)),
            TextSample("sk- 前缀嵌在单词中", "desk-" + FakeSecrets.body(30)),
            TextSample("sk- 开头的 kebab-case 普通文本（不含数字）", "sk-learn-pipeline-tutorial-notes"),
            TextSample("Stripe 15 位", FakeSecrets.stripe(bodyLength: 15)),
            TextSample("Stripe 可公开的 pk_live", FakeSecrets.stripe("pk", mode: "live")),
            TextSample("Stripe 未知模式", FakeSecrets.stripe("sk", mode: "prod")),
            TextSample("Slack 9 位", FakeSecrets.slack("b", bodyLength: 9)),
            TextSample("Slack 未知类型字母", FakeSecrets.slack("z")),
            TextSample("Google 34 位", FakeSecrets.google(bodyLength: 34)),
            TextSample("Google 36 位（超出单词边界）", FakeSecrets.google(bodyLength: 36)),
            TextSample("JWT 第三段 9 位", FakeSecrets.jwt(segmentLengths: [20, 30, 9])),
            TextSample("JWT 只有两段", FakeSecrets.jwt(segmentLengths: [20, 30])),
            TextSample("JWT 首段不以 eyJ 开头", "abc" + FakeSecrets.jwt().dropFirst(3)),
            TextSample("PEM 公钥", FakeSecrets.pem("PUBLIC")),
            TextSample("PEM 证书", "-----BEGIN CERTIFICATE-----"),
            TextSample("PEM 小写", FakeSecrets.pem("PRIVATE").lowercased()),
        ])
    func rejectsNearMisses(_ sample: TextSample) {
        #expect(!SecretDetector.containsSecret(sample.text))
    }

    @Test(
        "普通文本与短字符串不识别",
        arguments: [
            TextSample("空串", ""),
            TextSample("仅前缀 sk-", "sk-"),
            TextSample("仅前缀 AKIA", "AK" + "IA"),
            TextSample("仅前缀 ghp_", "gh" + "p_"),
            TextSample("仅前缀 eyJ", "eyJ"),
            TextSample("仅前缀 xoxb-", "xo" + "xb-"),
            TextSample("中文散文", "今天天气很好，我们去公园散步。湖面上有几只白鹅在游泳。"),
            TextSample("英文散文", "The quick brown fox jumps over the lazy dog. Please let me know."),
            TextSample("代码", "func greet(_ name: String) -> String {\n    return \"Hello, \\(name)\"\n}"),
            TextSample("URL", "https://example.com/docs/getting-started?lang=zh-CN#install"),
            TextSample("UUID", "3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
            TextSample("SHA-256", ContentHasher.sha256(Data("hello".utf8))),
            TextSample("Git 提交号", "e83c5163316f89bfbde7d9ab23ca2e25604af290"),
            TextSample(
                "Base64 图片头", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"),
            TextSample("邮箱", "someone@example.com"),
            TextSample("颜色值", "#FF8800"),
        ])
    func rejectsOrdinaryText(_ sample: TextSample) {
        #expect(!SecretDetector.containsSecret(sample.text))
    }

    // MARK: - 只扫描开头 50_000 字符

    @Test("超过 50_000 字符后才出现的密钥不被检测")
    func ignoresSecretsBeyondSample() {
        let padding = String(repeating: "a", count: 50_000)
        #expect(!SecretDetector.containsSecret(padding + " " + FakeSecrets.aws()))
    }

    @Test("恰好在第 50_000 个字符结束的密钥可被检测")
    func detectsSecretEndingAtBoundary() {
        let key = FakeSecrets.aws()
        let padding = String(repeating: "a", count: 50_000 - key.count - 1)
        let text = padding + " " + key
        #expect(text.count == 50_000)
        #expect(SecretDetector.containsSecret(text))
        #expect(SecretDetector.containsSecret(text + "\n" + String(repeating: "b", count: 10_000)))
    }

    @Test("跨越 50_000 边界的密钥不被检测")
    func ignoresSecretStraddlingBoundary() {
        let key = FakeSecrets.aws()
        let padding = String(repeating: "a", count: 50_000 - 10)
        #expect(!SecretDetector.containsSecret(padding + " " + key))
    }

    @Test("按字符而非字节计数：多字节填充下仍在窗口内的密钥可被检测")
    func samplesByCharacters() {
        let key = FakeSecrets.github()
        let padding = String(repeating: "汉", count: 50_000 - key.count - 1)
        #expect(SecretDetector.containsSecret(padding + " " + key))
    }

    @Test("MB 级文本快速完成且结果正确")
    func hugeText() {
        let huge = FakeSecrets.jwt() + "\n" + String(repeating: "普通内容 plain text\n", count: 100_000)
        #expect(SecretDetector.containsSecret(huge))
        #expect(!SecretDetector.containsSecret(String(repeating: "普通内容 plain text\n", count: 100_000)))
    }
}
