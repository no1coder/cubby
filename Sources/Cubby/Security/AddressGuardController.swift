import AppKit
import Observation
import os
import CubbyCore

/// 一次被替换：安全记录里的条目 + 状态机给出的详情。原值只留在内存里（记录只存缩写），重启后无法重建警示卡
struct TamperIncident: Equatable, Identifiable {
    let entryID: UUID
    let tamper: AddressGuard.Tamper
    /// 当时的前台应用名称
    let appName: String?

    var id: UUID { entryID }
}

/// 地址守护（docs/UI-UPGRADE-PLAN.md §6）：持有 AddressGuard 状态机与安全记录，App 层把剪贴板变化、Cubby 自己的写入
/// 与 ⌘C / ⌘X 喂进来，按结果写记录、弹警示卡。不清除剪贴板、不拦截 ⌘V，没发现替换时用户感知不到
@MainActor
@Observable
final class AddressGuardController {
    private(set) var state: AddressGuard
    private(set) var log: SecurityLog {
        didSet { blockedItemIDs = Self.blockedItems(in: log) }
    }
    /// 面板里禁止粘贴与复制的条目：被替换进来、且用户没有点「是我自己换的」（随记录更新，卡片渲染时直接读）
    private(set) var blockedItemIDs: Set<UUID> = []
    /// 还没处理的替换：菜单栏图标变成红色「地址被替换」，直到用户选择「恢复」或「是我自己换的」
    private(set) var pending: TamperIncident?
    /// 输入监控在运行（能看到 ⌘C / ⌘X）
    private(set) var monitorsKeystrokes = false

    /// 发现替换：弹出警示卡
    @ObservationIgnored var onTamper: ((TamperIncident) -> Void)?
    /// 重新检查输入监控授权并同步（设置页出现、轮询时调用）
    @ObservationIgnored var refreshInputMonitoring: (() -> Void)?
    /// 读剪贴板当前的纯文本（「恢复」前确认里面还是替换进来的值）
    @ObservationIgnored var readPasteboard: (() -> String?)?
    /// 把值写回剪贴板（带本应用的写入标记）；返回是否写入
    @ObservationIgnored var writeToPasteboard: ((String) -> Bool)?
    /// 本次运行中发现的替换（按记录 ID），面板「详情」据此重新打开警示卡
    @ObservationIgnored private var incidents: [UUID: TamperIncident] = [:]

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private let store: SecurityLogStore?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Security")

    /// - Parameter store: nil 时只在内存里记录（调试走查）
    init(settings: AppSettings, store: SecurityLogStore?, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.store = store
        self.now = now
        let log = store?.load() ?? SecurityLog()
        self.log = log
        self.blockedItemIDs = Self.blockedItems(in: log)
        self.state = AddressGuard(configuration: Self.configuration(settings: settings, monitorsKeystrokes: false))
    }

    // MARK: - 配置

    var isEnabled: Bool { settings.addressGuardEnabled }

    /// 设置（守护的类型、总开关）或输入监控状态变化后调用；关闭时忘掉守护中的值
    func syncConfiguration(monitorsKeystrokes: Bool) {
        self.monitorsKeystrokes = monitorsKeystrokes
        let configuration = Self.configuration(settings: settings, monitorsKeystrokes: monitorsKeystrokes)
        if isEnabled {
            state = state.configured(configuration)
        } else {
            // 关闭守护：忘掉守护中的值、内存里的原值与待处理的替换
            state = AddressGuard(configuration: configuration)
            incidents.removeAll()
            pending = nil
        }
    }

    /// 时间窗：有输入监控 10 秒，没有时 1.5 秒（看不到 ⌘C 时放宽会把用户自己连续复制的地址误判为替换）
    private static func configuration(settings: AppSettings, monitorsKeystrokes: Bool) -> AddressGuard.Configuration {
        .recommended(kinds: settings.guardedKinds, monitorsKeystrokes: monitorsKeystrokes)
    }

    /// 当前守护的值（面板里显示「守护中」的那一条）
    var guardedValue: SensitiveValue? {
        isEnabled ? state.guarded?.value : nil
    }

    // MARK: - 事件

    /// 剪贴板变了（不是 Cubby 自己写的）：在入历史的各项过滤之前调用。判定为被替换时返回这次替换
    @discardableResult
    func pasteboardChanged(text: String?, source: SourceApp?) -> TamperIncident? {
        guard isEnabled else { return nil }
        let event = AddressGuard.Event.pasteboardChanged(
            text: text, date: now(), frontmostBundleID: source?.bundleID, source: source)
        guard case .tampered(let tamper) = apply(event) else { return nil }
        return report(tamper, appName: source?.name)
    }

    /// Cubby 自己把文本写进了剪贴板（面板粘贴 / 复制、拆词、译文、警示卡的「恢复」）
    func cubbyWrote(_ text: String) {
        guard isEnabled else { return }
        apply(.cubbyWrote(text: text, date: now(), frontmostBundleID: Self.frontmostBundleID))
    }

    /// 输入监控看到 ⌘C 或 ⌘X
    func copyKeystroke() {
        guard isEnabled else { return }
        apply(.copyKeystroke(date: now()))
    }

    @discardableResult
    private func apply(_ event: AddressGuard.Event) -> AddressGuard.Outcome {
        let (next, outcome) = state.handling(event)
        state = next
        return outcome
    }

    private func report(_ tamper: AddressGuard.Tamper, appName: String?) -> TamperIncident {
        let name = appName ?? tamper.frontmostBundleID.flatMap(AppNames.name(forBundleID:))
        let entry = SecurityLogEntry(
            date: tamper.date, event: .tampered, kind: tamper.replacement.kind,
            summary: AddressComparison.abbreviated(tamper.replacement.value), appName: name)
        let incident = TamperIncident(entryID: entry.id, tamper: tamper, appName: name)
        incidents[entry.id] = incident
        pending = incident
        append(entry)
        logger.notice("Detected a replaced \(tamper.replacement.kind.rawValue, privacy: .public) value")
        onTamper?(incident)
        return incident
    }

    // MARK: - 记录

    /// 被替换进来的内容入历史后，把记录关联到那一条（面板里显示为红色记录、禁止粘贴与复制）
    func link(_ incident: TamperIncident, toItem itemID: UUID) {
        log = log.linking(entryID: incident.entryID, toItem: itemID)
        persist()
    }

    /// 与 SecurityLog.tamperedItemIDs 相同（被替换进来的减去「是我自己换的」）；在 App 层再算一次，不依赖它的实现细节
    private static func blockedItems(in log: SecurityLog) -> Set<UUID> {
        let tampered = log.entries.filter { $0.event == .tampered }.compactMap(\.tamperedItemID)
        let dismissed = log.entries.filter { $0.event == .dismissed }.compactMap(\.tamperedItemID)
        return Set(tampered).subtracting(dismissed)
    }

    /// 某个被替换进来的条目对应的替换；重启后原值已不在内存里时为 nil
    func incident(forItem itemID: UUID) -> TamperIncident? {
        log.entries.first { $0.event == .tampered && $0.tamperedItemID == itemID }.flatMap { incidents[$0.id] }
    }

    /// 从 Cubby 粘贴 / 复制敏感值后核对一致
    func recordVerifiedPaste(_ value: SensitiveValue, appName: String?) {
        append(
            SecurityLogEntry(
                date: now(), event: .pasteVerified, kind: value.kind,
                summary: AddressComparison.abbreviated(value.value), appName: appName))
    }

    var summary: SecurityLog.Summary {
        log.summary(days: 30, now: now())
    }

    private func append(_ entry: SecurityLogEntry) {
        log = log.appending(entry, now: now())
        persist()
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(log)
        } catch {
            logger.error("Failed to save the security log: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 警示卡的按钮

    enum RestoreResult {
        case restored
        /// 写剪贴板失败
        case failed
        /// 剪贴板里已经不是替换进来的值（用户又复制了别的、或已经换回）：不覆盖
        case alreadyChanged
    }

    /// 「恢复我复制的地址」：剪贴板里还是替换进来的值时，把原文按复制时的样子写回（本应用的写入），之后继续守护它
    @discardableResult
    func restore(_ incident: TamperIncident) -> RestoreResult {
        let tamper = incident.tamper
        let current = readPasteboard?().flatMap { SensitiveTextClassifier.classify($0) }
        guard current?.isSame(as: tamper.replacement) == true else {
            resolve(incident)
            return .alreadyChanged
        }
        let text = tamper.original.restorableText
        guard writeToPasteboard?(text) == true else { return .failed }
        cubbyWrote(text)
        let original = tamper.original.value
        append(
            SecurityLogEntry(
                date: now(), event: .restored, kind: original.kind,
                summary: AddressComparison.abbreviated(original.value), appName: incident.appName,
                relatedEntryID: incident.entryID))
        resolve(incident)
        return .restored
    }

    /// 「是我自己换的」：把替换后的值当作用户复制的，面板里的那一条恢复正常
    func acceptReplacement(_ incident: TamperIncident) {
        apply(.acceptedReplacement(incident.tamper))
        let itemID = log.entries.first { $0.id == incident.entryID }?.tamperedItemID
        let replacement = incident.tamper.replacement
        append(
            SecurityLogEntry(
                date: now(), event: .dismissed, kind: replacement.kind,
                summary: AddressComparison.abbreviated(replacement.value), appName: incident.appName,
                tamperedItemID: itemID, relatedEntryID: incident.entryID))
        resolve(incident)
    }

    private func resolve(_ incident: TamperIncident) {
        if pending?.entryID == incident.entryID { pending = nil }
    }

    /// 历史变化（删除、清空、超出上限）后：被替换进来的条目已不在历史里时，丢掉内存里的原值（待处理的除外）
    func prune(keepingItems itemIDs: Set<UUID>) {
        let linked = Dictionary(
            log.entries.lazy.filter { $0.event == .tampered }.compactMap { entry in
                entry.tamperedItemID.map { (entry.id, $0) }
            },
            uniquingKeysWith: { first, _ in first })
        incidents = incidents.filter { entryID, _ in
            guard entryID != pending?.entryID, let itemID = linked[entryID] else { return true }
            return itemIDs.contains(itemID)
        }
    }

    private static var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    #if DEBUG
    /// 调试走查：直接放入一次替换（不经过剪贴板），用于警示卡与面板「详情」
    func debugInsert(_ incident: TamperIncident, markPending: Bool) {
        incidents[incident.entryID] = incident
        if markPending { pending = incident }
    }

    /// 调试走查：把演示用的安全记录放进内存（不写盘）
    func debugReplaceLog(_ newLog: SecurityLog) {
        log = newLog
    }

    /// 调试走查：让面板把这个值显示为「守护中」
    func debugGuard(_ value: SensitiveValue) {
        let (next, _) = state.handling(.cubbyWrote(text: value.value, date: now(), frontmostBundleID: nil))
        state = next
    }
    #endif
}

/// 由 bundle ID 得到应用名称：先看正在运行的应用，再看安装位置
enum AppNames {
    @MainActor
    static func name(forBundleID bundleID: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
            let name = running.localizedName
        {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let displayName = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }
}
