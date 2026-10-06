import Foundation

/// 最近一次查到的新版本：版本号 + 发布页（地址已按白名单校验，docs/UPDATE-REMINDER-DESIGN.md U7）
public struct KnownRelease: Hashable, Sendable {
    public let version: SemanticVersion
    public let releaseURL: URL

    /// 发布页不在白名单内（或缺失）时换成固定的发布页
    public init(version: SemanticVersion, releaseURL: URL?) {
        self.version = version
        self.releaseURL = UpdateReleaseURL.sanitized(releaseURL)
    }

    /// 版本号无法解析时返回 nil
    public init?(version: String, releaseURL: URL?) {
        guard let parsed = SemanticVersion(version) else { return nil }
        self.init(version: parsed, releaseURL: releaseURL)
    }
}
