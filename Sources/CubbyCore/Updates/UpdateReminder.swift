import Foundation

/// 更新提醒的纯判断（docs/UPDATE-REMINDER-DESIGN.md U4–U7）：给定设置与当前版本，
/// 决定菜单栏是否显示蓝点、面板顶部显示哪种横幅
public struct UpdateReminder: Equatable, Sendable {
    public enum Banner: Hashable, Sendable {
        /// 新版本可用（每个版本提醒一次，U6）
        case available(KnownRelease)
        /// 询问老用户是否开启自动检查（只问一次，U4）
        case askPermission
    }

    /// 判断所需的设置
    public struct Inputs: Equatable, Sendable {
        public var checksAutomatically: Bool
        public var hasAnsweredPrompt: Bool
        public var hasCompletedOnboarding: Bool
        public var knownRelease: KnownRelease?
        public var dismissedVersion: SemanticVersion?

        public init(
            checksAutomatically: Bool,
            hasAnsweredPrompt: Bool,
            hasCompletedOnboarding: Bool,
            knownRelease: KnownRelease?,
            dismissedVersion: SemanticVersion?
        ) {
            self.checksAutomatically = checksAutomatically
            self.hasAnsweredPrompt = hasAnsweredPrompt
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.knownRelease = knownRelease
            self.dismissedVersion = dismissedVersion
        }
    }

    /// 比当前版本新的已知版本：蓝点、菜单项与「关于」页都看它（「稍后」不影响）
    public let availableRelease: KnownRelease?
    public let banner: Banner?

    public static let none = UpdateReminder(availableRelease: nil, banner: nil)

    public var showsDot: Bool {
        availableRelease != nil
    }

    private init(availableRelease: KnownRelease?, banner: Banner?) {
        self.availableRelease = availableRelease
        self.banner = banner
    }

    /// 新版本横幅优先；它被「稍后」收起或没有新版本时，才轮到询问
    public init(_ inputs: Inputs, currentVersion: String) {
        let available = inputs.knownRelease.flatMap {
            Self.isNewer($0, than: currentVersion) ? $0 : nil
        }
        if let available, !Self.isDismissed(available, dismissedVersion: inputs.dismissedVersion) {
            self.init(availableRelease: available, banner: .available(available))
        } else {
            self.init(availableRelease: available, banner: Self.asks(inputs) ? .askPermission : nil)
        }
    }

    /// 当前版本已不低于已知版本（用户升级了）；当前版本无法解析时不算
    public static func isInstalled(_ release: KnownRelease, currentVersion: String) -> Bool {
        guard let current = SemanticVersion(currentVersion) else { return false }
        return current >= release.version
    }

    private static func isNewer(_ release: KnownRelease, than currentVersion: String) -> Bool {
        guard let current = SemanticVersion(currentVersion) else { return false }
        return current < release.version
    }

    /// 对这个版本（或更新的版本）点过「稍后」
    private static func isDismissed(_ release: KnownRelease, dismissedVersion: SemanticVersion?) -> Bool {
        guard let dismissedVersion else { return false }
        return dismissedVersion >= release.version
    }

    /// 完成过欢迎页、自动检查关着、从没回答过
    private static func asks(_ inputs: Inputs) -> Bool {
        inputs.hasCompletedOnboarding && !inputs.checksAutomatically && !inputs.hasAnsweredPrompt
    }
}
