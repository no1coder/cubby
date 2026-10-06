import AppKit
import CubbyCore
import Observation
import os

/// 更新提醒的唯一状态来源（docs/UPDATE-REMINDER-DESIGN.md）：手动、启动、每小时与唤醒时的检查都经过这里，
/// 结果记进设置（U7），菜单栏蓝点 / 菜单项、面板横幅与「关于」页都观察它
@MainActor
@Observable
final class UpdateCoordinator {
    /// 可注入的外部依赖：正式运行用 GitHub 与系统；面板 E2E 换成桩（不联网、不打开浏览器、用命名剪贴板）
    @MainActor
    struct Environment {
        var check: @MainActor () async -> UpdateChecker.Result = { await UpdateChecker.check() }
        var currentVersion = UpdateChecker.currentVersion
        var isHomebrewInstall = HomebrewInstall.isInstalled()
        var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
        var pasteboard = NSPasteboard.general
        /// 每小时与唤醒时重新判断是否到期（E2E 关闭）
        var schedulesChecks = true
    }

    /// 运行期间多久判断一次是否到期（U1）；允许系统合并唤醒的误差
    static let evaluationInterval: TimeInterval = 60 * 60
    static let evaluationTolerance: TimeInterval = 5 * 60
    /// 从睡眠唤醒后等网络连上再判断
    static let wakeDelay: Duration = .seconds(30)

    /// 正在联网检查（「关于」页的按钮显示「正在检查…」）
    private(set) var isChecking = false

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let environment: Environment
    @ObservationIgnored private var inFlight: Task<UpdateChecker.Result, Never>?
    /// 本次运行中最近一次失败的时间：一小时内不自动重试（UpdateCheckSchedule）
    @ObservationIgnored private var lastFailure: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeCheck: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Update")

    init(settings: AppSettings, environment: Environment = Environment()) {
        self.settings = settings
        self.environment = environment
    }

    var currentVersion: String {
        environment.currentVersion
    }

    var isHomebrewInstall: Bool {
        environment.isHomebrewInstall
    }

    /// 蓝点与横幅（读取可观察的设置，视图与 withObservationTracking 会随之更新）
    var reminder: UpdateReminder {
        settings.updateReminder(currentVersion: currentVersion)
    }

    // MARK: - 启动与定时

    /// 启动时：用户已升级则清除记住的版本（U7）；到期就查；之后每小时与唤醒时再判断（U1）
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        settings.clearInstalledRelease(currentVersion: currentVersion)
        observeSettings()
        checkIfDue()
        guard environment.schedulesChecks else { return }
        scheduleTimer()
        observeWake()
    }

    /// 开启了自动检查、完成了欢迎页且已到期才联网（欢迎页的判断在 isAutomaticUpdateCheckDue 里，见 U3）
    func checkIfDue(now: Date = Date()) {
        guard !isChecking, settings.isAutomaticUpdateCheckDue(now: now, lastFailure: lastFailure)
        else { return }
        startCheck()
    }

    private func scheduleTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.evaluationInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = Self.evaluationTolerance
        self.timer = timer
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWakeCheck() }
        }
    }

    /// 连续唤醒只保留最后一次
    private func scheduleWakeCheck() {
        wakeCheck?.cancel()
        wakeCheck = Task { [weak self] in
            try? await Task.sleep(for: Self.wakeDelay)
            guard !Task.isCancelled else { return }
            self?.checkIfDue()
        }
    }

    /// 打开开关（设置、欢迎页、询问横幅）或完成欢迎页时立即判断一次。
    /// 回调由设置持有：只弱引用协调器，避免 settings → 回调 → 协调器 → settings 的循环
    private func observeSettings() {
        withObservationTracking {
            _ = settings.checksForUpdatesAutomatically
            _ = settings.hasCompletedOnboarding
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeSettings()
                self?.checkIfDue()
            }
        }
    }

    // MARK: - 检查

    /// 联网检查并记住结果；已有检查在进行时共用它的结果
    @discardableResult
    func check() async -> UpdateChecker.Result {
        await startCheck().value
    }

    /// 同步登记检查：同一轮里多次触发（设置监听与按钮同时触发）也只联网一次；结果在任务里记下，只记一次
    @discardableResult
    private func startCheck() -> Task<UpdateChecker.Result, Never> {
        if let inFlight { return inFlight }
        isChecking = true
        let task = Task {
            let result = await environment.check()
            inFlight = nil
            isChecking = false
            remember(result)
            return result
        }
        inFlight = task
        return task
    }

    /// 查到新版本就记住，已是最新就忘掉；失败只记下时间（不推迟下一天的检查，一小时后可重试）
    private func remember(_ result: UpdateChecker.Result, now: Date = Date()) {
        switch result {
        case .available(let version, let url):
            succeeded(at: now)
            guard let release = KnownRelease(version: version, releaseURL: url) else { return }
            settings.rememberAvailableRelease(release)
        case .upToDate:
            succeeded(at: now)
            settings.forgetKnownRelease()
        case .failed:
            lastFailure = now
        }
    }

    private func succeeded(at date: Date) {
        settings.lastUpdateCheck = date
        lastFailure = nil
    }

    // MARK: - 横幅、菜单与「关于」页的操作

    /// 打开发布页（地址已按白名单校验）
    func openRelease(_ release: KnownRelease) {
        environment.openURL(release.releaseURL)
    }

    /// 复制 Homebrew 升级命令（带本应用写入标记，不进历史，U8）；返回是否写入
    func copyUpgradeCommand() -> Bool {
        do {
            try PasteboardWriter.write(text: HomebrewInstall.upgradeCommand, to: environment.pasteboard)
            return true
        } catch {
            logger.error("Couldn't copy the upgrade command: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// 新版本横幅的「稍后」：只隐藏这个版本（U6）
    func dismissBanner(for release: KnownRelease) {
        settings.dismissUpdateBanner(for: release)
    }

    /// 询问横幅的「提醒我」：打开自动检查并立即查一次（U4）
    func enableReminders() {
        settings.answerUpdatePrompt(remindMe: true)
        startCheck()
    }

    /// 询问横幅的「不用了」：保持关闭，不再问
    func declineReminders() {
        settings.answerUpdatePrompt(remindMe: false)
    }
}
