import AppKit
import CubbyCore

// 地址守护的接线（docs/UI-UPGRADE-PLAN.md §6）：剪贴板监听 → AddressGuardController → 警示卡、菜单栏胶囊、面板标记。
// 外部的剪贴板变化在入历史的过滤之前交给守护；Cubby 自己的写入由面板在写入时直接告知，监听器看到带写入标记的变化时再补一次
extension AppDelegate {
    func makeAddressGuard() -> AddressGuardController {
        let controller = AddressGuardController(settings: settings)
        controller.writeToPasteboard = { text in
            guard (try? PasteboardWriter.write(text: text, to: .general)) != nil else { return false }
            OwnPasteboardWrites.record(.general)
            return true
        }
        controller.readPasteboard = { NSPasteboard.general.string(forType: .string) }
        controller.refreshInputMonitoring = { [weak self] in self?.syncAddressGuard() }
        controller.onTamper = { [weak self] incident in self?.tamperAlert?.show(incident) }
        return controller
    }

    /// Vault 就绪后接上加密的安全记录。调试走查只用内存，带演示历史时读写 CUBBY_DATA_DIR 里的演示记录
    func attachSecurityLog(keys: HistoryKeys) {
        #if DEBUG
        if CommandLine.arguments.contains("--scenario"), !DesignDemoHistory.isRequested { return }
        #endif
        addressGuard?.attach(SecurityLogStore(dataDirectory: AppPaths.root, vault: AppPaths.vault, keys: keys))
    }

    func makeTamperAlert(settingsWindow: SettingsWindowController) -> TamperAlertController {
        TamperAlertController(
            actions: .init(
                restore: { [weak self] incident in self?.addressGuard?.restore(incident) ?? .failed },
                changedMyself: { [weak self] incident in self?.addressGuard?.acceptReplacement(incident) },
                viewLog: { settingsWindow.show(pane: .security) }
            ))
    }

    /// 面板：标记、禁止粘贴被替换进来的条目、粘贴核对；「详情」重新打开警示卡（原值已不在内存里时打开安全记录）
    func connectAddressGuard(to panel: PanelController, settingsWindow: SettingsWindowController) {
        panel.addressGuard = addressGuard
        panel.showTamperDetails = { [weak self, weak panel] itemID in
            panel?.hide(animated: false)
            if let incident = self?.addressGuard?.incident(forItem: itemID) {
                self?.tamperAlert?.show(incident)
            } else {
                settingsWindow.show(pane: .security)
            }
        }
    }

    /// 开始守护（与剪贴板监听同时开始；调试走查不启动）
    func startAddressGuard() {
        isGuardingClipboard = true
        syncAddressGuard()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAddressGuard() }
        }
    }

    /// 总开关、守护的类型或输入监控授权变化后：装上 / 拆下剪贴板观察与按键监听，同步状态机配置
    func syncAddressGuard() {
        guard let addressGuard else { return }
        let enabled = settings.addressGuardEnabled && isGuardingClipboard
        if !enabled { tamperAwaitingRecord = nil }
        if !settings.addressGuardEnabled { panel?.viewModel.sensitiveValues.prune(keeping: nil) }
        monitor?.onChange = enabled ? { [weak self] change in self?.observePasteboard(change) } : nil
        let monitorsKeystrokes = inputMonitor.update(enabled: enabled)
        addressGuard.syncConfiguration(monitorsKeystrokes: monitorsKeystrokes)
    }

    func observeAddressGuard() {
        inputMonitor.onCopyKeystroke = { [weak self] in
            self?.addressGuard?.copyKeystroke()
            // 马上多看几次剪贴板：在后台程序换掉之前读到用户复制的值
            self?.monitor?.pollSoon()
        }
        observe({ [settings] in settings.addressGuardEnabled }) { [weak self] in self?.syncAddressGuard() }
        observe({ [settings] in settings.guardedKinds }) { [weak self] in self?.syncAddressGuard() }
        // 删除、清空历史或超出上限后：丢掉已不在历史里的条目的原值与识别结果
        observe({ [weak self] in self?.store?.revision }) { [weak self] in self?.pruneAddressGuard() }
        observe({ [weak self] in self?.addressGuard?.pending }) { [weak self] in
            guard let self else { return }
            self.statusBar?.setTamperPill(self.addressGuard?.pending != nil)
            // 处理过了（例如在设置里关掉守护后又点了按钮）：警示卡随之收起
            if self.addressGuard?.pending == nil, self.tamperAlert?.incident != nil { self.tamperAlert?.hide() }
        }
    }

    private func pruneAddressGuard() {
        guard let store else { return }
        let itemIDs = Set(store.history.items.map(\.id))
        addressGuard?.prune(keepingItems: itemIDs)
        panel?.viewModel.sensitiveValues.prune(keeping: settings.addressGuardEnabled ? itemIDs : nil)
    }

    /// 菜单栏红色胶囊：重新打开还没处理的警示卡
    func showPendingTamperAlert() {
        guard let incident = addressGuard?.pending else { return }
        tamperAlert?.show(incident)
    }

    private func observePasteboard(_ change: ClipboardMonitor.Change) {
        tamperAwaitingRecord = nil
        guard let addressGuard else { return }
        if change.isOwnWrite {
            if let text = change.text { addressGuard.cubbyWrote(text) }
            return
        }
        tamperAwaitingRecord = addressGuard.pasteboardChanged(text: change.text, source: change.source)
            .map { ($0, change.changeCount) }
    }

    /// 被判定为替换的那次变化随后入历史（changeCount 相同才算同一次）：来源记为未知，入库后把安全记录关联到这一条
    func takeTamperAwaitingRecord(changeCount: Int) -> TamperIncident? {
        defer { tamperAwaitingRecord = nil }
        guard let pending = tamperAwaitingRecord, pending.changeCount == changeCount else { return nil }
        return pending.incident
    }

    func linkTamper(_ incident: TamperIncident, to recording: Task<ClipItem?, Never>) {
        Task { @MainActor [weak self] in
            guard let item = await recording.value else { return }
            self?.addressGuard?.link(incident, toItem: item.id)
        }
    }
}
