import Foundation

/// 更新提醒的设置操作（存储属性见 AppSettings，docs/UPDATE-REMINDER-DESIGN.md U3–U7）
extension AppSettings {
    /// 当前设置下的蓝点与横幅
    public func updateReminder(currentVersion: String) -> UpdateReminder {
        UpdateReminder(
            UpdateReminder.Inputs(
                checksAutomatically: checksForUpdatesAutomatically,
                hasAnsweredPrompt: hasAnsweredUpdatePrompt,
                hasCompletedOnboarding: hasCompletedOnboarding,
                knownRelease: knownRelease,
                dismissedVersion: dismissedUpdateVersion
            ),
            currentVersion: currentVersion
        )
    }

    /// 记住查到的新版本（U7）
    public func rememberAvailableRelease(_ release: KnownRelease) {
        guard knownRelease != release else { return }
        knownRelease = release
    }

    /// 检查结果为已是最新：不再有已知的新版本
    public func forgetKnownRelease() {
        guard knownRelease != nil else { return }
        knownRelease = nil
    }

    /// 用户升级后（当前版本不低于已知版本）清除已知版本；不高于当前版本的「稍后」一并清除。返回是否有改动
    @discardableResult
    public func clearInstalledRelease(currentVersion: String) -> Bool {
        guard let current = SemanticVersion(currentVersion) else { return false }
        var changed = false
        if let knownRelease, UpdateReminder.isInstalled(knownRelease, currentVersion: currentVersion) {
            self.knownRelease = nil
            changed = true
        }
        if let dismissedUpdateVersion, dismissedUpdateVersion <= current {
            self.dismissedUpdateVersion = nil
            changed = true
        }
        return changed
    }

    /// 新版本横幅的「稍后」：只隐藏这个版本，出现更新的版本时再提醒（U6）
    public func dismissUpdateBanner(for release: KnownRelease) {
        dismissedUpdateVersion = release.version
    }

    /// 询问横幅：「提醒我」打开自动检查，「不用了」保持关闭；无论选哪个都不再问（U4）
    public func answerUpdatePrompt(remindMe: Bool) {
        checksForUpdatesAutomatically = remindMe
        hasAnsweredUpdatePrompt = true
    }

    /// 新用户第一次显示欢迎页时默认打开自动检查（U3）。只对没完成过欢迎页、也没回答过的用户生效：
    /// 从菜单重开欢迎页的老用户、或取消勾选后没点「开始使用」就退出的新用户都不会被改动。返回是否打开了
    @discardableResult
    public func applyFirstRunUpdateDefault() -> Bool {
        guard !hasCompletedOnboarding, !hasAnsweredUpdatePrompt else { return false }
        checksForUpdatesAutomatically = true
        hasAnsweredUpdatePrompt = true
        return true
    }

    /// 读回已知版本：版本号无法解析时丢弃；地址按白名单校验，不合格（或类型不对）时换成固定的发布页
    static func storedKnownRelease(version versionKey: String, releaseURL urlKey: String, in defaults: UserDefaults)
        -> KnownRelease?
    {
        guard let version = defaults.string(forKey: versionKey) else { return nil }
        let url = defaults.string(forKey: urlKey).flatMap { URL(string: $0) }
        return KnownRelease(version: version, releaseURL: url)
    }
}
