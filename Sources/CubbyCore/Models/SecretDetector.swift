import Foundation

/// 识别疑似密钥 / 令牌。终端、浏览器等来源不会标记机密类型，需要按内容兜底。
public enum SecretDetector {
    /// 只检查开头部分，避免大文本拖慢采集
    private static let sampleLength = 50_000

    /// 令牌只含 ASCII：用 ASCII 边界代替 \b。ICU 中汉字属于 \w，紧邻中文时 \b 不成立会漏检
    private static let start = #"(?<![A-Za-z0-9_])"#
    private static let end = #"(?![A-Za-z0-9_])"#

    private static let patterns: [NSRegularExpression] = [
        // PEM 私钥
        #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"#,
        // AWS Access Key
        start + #"(?:AKIA|ASIA)[0-9A-Z]{16}"# + end,
        // GitHub Token
        start + #"gh[pousr]_[A-Za-z0-9]{36,}"# + end,
        // GitHub 细粒度 Token
        start + #"github_pat_[A-Za-z0-9_]{50,}"# + end,
        // OpenAI / Anthropic：要求含数字，排除 sk-learn-xxx 这类 kebab-case 普通文本
        start + #"sk-(?:ant-|proj-)?(?=[A-Za-z_\-]*[0-9])[A-Za-z0-9_\-]{20,}"#,
        // Stripe
        start + #"(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{16,}"# + end,
        // Slack
        start + #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,
        // Google API Key
        start + #"AIza[0-9A-Za-z_\-]{35}"# + end,
        // JWT
        start + #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func containsSecret(_ text: String) -> Bool {
        let sample = String(text.prefix(sampleLength))
        let range = NSRange(sample.startIndex..., in: sample)
        return patterns.contains { $0.firstMatch(in: sample, range: range) != nil }
    }
}
