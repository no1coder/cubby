import AppKit
import CubbyCore
import Observation

/// 列表中按住 ⌥ 预览译文（A4）：按住约 300 ms 且期间没有按其他键，选中卡片淡入为流式译文，松开恢复；
/// 预览中按 ↩（即 ⌥↩）粘贴正在显示的内容，未完成时完成后粘贴；按下其他键或点按立即取消。
/// 云端引擎：预览立即显示，但要停留满 0.6 s（按住的 300 ms 计入）才发送（⌥ 也是 ⌥↑、⌥↓、⌥ 点按的修饰键）
@MainActor
@Observable
final class TranslationPeekController {
    private(set) var peek: TranslationPeek?
    /// ⌥ 是否正按着（预览的尾注与失败说明的去向据此决定）
    private(set) var isOptionHeld = false

    @ObservationIgnored let environment: ClipTranslationEnvironment
    @ObservationIgnored var onPaste: ((TranslationPasteRequest) -> Void)?
    /// ⌥ 已松开时的失败说明（底栏定时提示；卡片同时恢复原样）
    @ObservationIgnored var onNotice: ((String) -> Void)?
    @ObservationIgnored private var holdTimer: Task<Void, Never>?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 预览中按了 ↩（完成后粘贴）时的总时限，与 ⌥↩ 相同
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var token = 0
    /// 这次预览还能因计划过期自动重新 plan 几次
    @ObservationIgnored private var replansLeft = maxTranslationReplans
    /// 云端引擎停留期间待发送的翻译
    @ObservationIgnored private var held: (item: ClipItem, plan: ClipTranslationPlan, token: Int)?

    init(environment: ClipTranslationEnvironment) {
        self.environment = environment
    }

    /// 单独按下 ⌥：开始计时；到时后对 item()（当时的选中项）开始预览
    func optionPressed(item: @escaping @MainActor () -> ClipItem?) {
        isOptionHeld = true
        guard peek == nil else { return }
        holdTimer?.cancel()
        let hold = environment.timings.optionHold
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard let self, !Task.isCancelled else { return }
            self.holdTimer = nil
            if let target = item() {
                self.replansLeft = maxTranslationReplans
                self.start(target)
            }
        }
    }

    /// 松开 ⌥：取消计时；预览中且没有等待粘贴时结束预览
    func optionReleased() {
        isOptionHeld = false
        cancelHold()
        guard let current = peek, !current.pasteOnDone else { return }
        end()
    }

    /// 按下了其他键（⌥↩ 除外）：取消计时与预览。已按 ↩ 等待粘贴时 esc 交给 cancelPendingPaste（同 ⌥↩ 的 esc 取消）
    func otherKeyPressed(isEscape: Bool) {
        cancelHold()
        guard let current = peek, !(isEscape && current.pasteOnDone) else { return }
        end()
    }

    /// esc：取消「完成后粘贴」的预览；没有时返回 false
    func cancelPendingPaste() -> Bool {
        guard peek?.pasteOnDone == true else { return false }
        end()
        return true
    }

    /// 预览中按 ↩：已完成则粘贴显示的内容，否则完成后粘贴；没有预览时返回 false
    func pasteShown() -> Bool {
        guard var current = peek else { return false }
        switch current.phase {
        case .done:
            guard let result = current.content.result, let item = environment.item(current.itemID) else { return true }
            end()
            onPaste?(TranslationPasteRequest(item: item, result: result, style: .standard, origin: .peek))
        case .holding, .waiting, .streaming:
            current.pasteOnDone = true
            peek = current
            // 停留期间按 ↩ 是明确要这条的译文：不再等，立即发送
            if current.phase == .holding { sendHeld(token: token) }
            startWatchdog()
        case .note:
            NSSound.beep()
        }
        return true
    }

    /// 面板隐藏、选中项变化：丢弃一切
    func cancel() {
        isOptionHeld = false
        cancelHold()
        cancelTask()
        peek = nil
    }

    // MARK: - 流程

    private func start(_ item: ClipItem) {
        cancelTask()
        let outcome = TranslationPlanning.outcome(
            for: item, target: nil, confirmedPlan: nil, environment: environment)
        switch outcome {
        case .unsupported(let reason):
            peek = note(item, plan: nil, TranslationCopy.unsupportedTitle(reason))
        case .failed(let failure):
            peek = note(item, plan: nil, TranslationCopy.inlineIssue(.failure(failure), plan: nil))
        case .alreadyTarget(let plan):
            let text = TranslationCopy.inlineIssue(.alreadyTarget(plan.languages.target), plan: plan)
            peek = note(item, plan: plan, text)
        case .needsSecretConfirmation(let plan):
            peek = note(item, plan: plan, TranslationCopy.peekSecretNote)
        case .ready(let plan):
            run(item, plan: plan)
        }
    }

    /// 云端引擎先停留（预览已显示为等待中），本机引擎与缓存命中立即开始
    private func run(_ item: ClipItem, plan: ClipTranslationPlan) {
        let timings = environment.timings
        let dwell = TranslationSendDwell.remaining(
            sendsTextOffDevice: plan.sendsTextOffDevice, isCached: plan.isCached, elapsed: timings.optionHold,
            total: timings.cloudDwell)
        guard dwell > .zero else {
            send(item, plan: plan, pasteOnDone: false)
            return
        }
        peek = TranslationPeek(itemID: item.id, plan: plan, phase: .holding, content: .empty)
        let current = token
        held = (item, plan, current)
        task = Task { [weak self] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            self?.sendHeld(token: current)
        }
    }

    /// 停留结束（或停留中按了 ↩）：按预览的最新状态发送
    private func sendHeld(token current: Int) {
        guard let held, held.token == current, token == current, let latest = peek, latest.itemID == held.item.id
        else { return }
        self.held = nil
        task?.cancel()
        send(held.item, plan: held.plan, pasteOnDone: latest.pasteOnDone)
    }

    private func send(_ item: ClipItem, plan: ClipTranslationPlan, pasteOnDone: Bool) {
        peek = TranslationPeek(
            itemID: item.id, plan: plan, phase: .waiting, content: .empty, pasteOnDone: pasteOnDone)
        let current = token
        let stream = environment.translator.translate(item, plan: plan, confirmedSecret: false)
        task = Task { [weak self] in
            let end = await TranslationStream.consume(stream) { event in
                self?.apply(event, token: current)
            }
            self?.finish(end, token: current)
        }
    }

    private func apply(_ event: ClipTranslationEvent, token current: Int) {
        guard current == token, var running = peek else { return }
        running.content = running.content.applying(event)
        switch event {
        case .started: break
        case .segment, .imageBlock: running.phase = .streaming
        case .finished: running.phase = .done
        }
        peek = running
    }

    private func finish(_ end: TranslationStreamEnd, token current: Int) {
        guard current == token, let ended = peek else { return }
        switch end {
        case .cancelled:
            return
        case .failed(let failure):
            showNote(TranslationCopy.inlineIssue(.failure(failure), plan: ended.plan))
        case .refused(let refusal):
            handle(refusal, peek: ended)
        case .finished:
            guard let result = ended.content.result, !result.isEmpty else {
                showNote(TranslationCopy.unsupportedTitle(.noText))
                return
            }
            guard ended.pasteOnDone, let item = environment.item(ended.itemID) else { return }
            self.end()
            onPaste?(TranslationPasteRequest(item: item, result: result, style: .standard, origin: .peek))
        }
    }

    /// 服务拒绝发送（什么都没发出）：计划过期 → 重新 plan（保留「完成后粘贴」）；疑似密钥未确认 → 说明
    private func handle(_ refusal: ClipTranslationRefusal, peek ended: TranslationPeek) {
        switch refusal {
        case .planOutdated where replansLeft > 0:
            guard let item = environment.item(ended.itemID) else { return }
            replansLeft -= 1
            start(item)
            guard ended.pasteOnDone, var restarted = peek, restarted.isStreaming else { return }
            restarted.pasteOnDone = true
            peek = restarted
            startWatchdog()
        case .planOutdated:
            showNote(TranslationCopy.inlineIssue(.failure(.invalidResponse), plan: ended.plan))
        case .secretNotConfirmed:
            showNote(TranslationCopy.peekSecretNote)
        }
    }

    /// 预览改为一行说明（失败、超时、没有可翻译的文字）；不再等待粘贴
    /// ⌥ 还按着时卡片上显示说明，松开后按提示恢复；⌥ 已松开（按过 ↩ 在等粘贴）时改为底栏定时提示并恢复卡片，
    /// 下一次按 ⌥ 不受影响
    private func showNote(_ text: String) {
        guard var current = peek else { return }
        guard isOptionHeld else {
            end()
            onNotice?(text)
            return
        }
        cancelTask()
        current.phase = .note(text)
        current.pasteOnDone = false
        current.content = .empty
        peek = current
    }

    /// 「完成后粘贴」的总时限：到时仍未完成就停下并说明，绝不粘贴部分结果
    private func startWatchdog() {
        watchdog?.cancel()
        let cap = environment.timings.inlineCap
        let current = token
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: cap)
            guard let self, !Task.isCancelled, self.token == current, self.peek?.pasteOnDone == true else { return }
            self.showNote(TranslationCopy.inlineIssue(.timedOut, plan: self.peek?.plan))
        }
    }

    private func note(_ item: ClipItem, plan: ClipTranslationPlan?, _ text: String) -> TranslationPeek {
        TranslationPeek(itemID: item.id, plan: plan, phase: .note(text), content: .empty)
    }

    /// 松开或按其他键：未完成的预览丢弃，卡片内容淡回原文
    private func end() {
        cancelTask()
        peek = nil
    }

    private func cancelHold() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func cancelTask() {
        token += 1
        held = nil
        task?.cancel()
        watchdog?.cancel()
        task = nil
        watchdog = nil
    }
}
