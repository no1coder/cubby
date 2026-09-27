import AppKit
import CubbyCore
import Observation

/// 翻译卡（⌘T）：打开 / 关闭、跟随选中项、流式翻译、对调与语言选择（docs/CLIP-TRANSLATION-DESIGN.md §1.3、A3、A5）。
/// 粘贴、复制、存为新条目等结果操作见 TranslationCardController+Actions.swift
@MainActor
@Observable
final class TranslationCardController {
    private(set) var card: TranslationCard?
    /// 底栏短暂提示
    private(set) var flash: TranslationFlash?

    @ObservationIgnored let environment: ClipTranslationEnvironment
    /// 粘贴 / 复制请求（面板控制器写剪贴板）；复制返回是否成功
    @ObservationIgnored var onPaste: ((TranslationPasteRequest) -> Void)?
    @ObservationIgnored var onCopy: ((TranslationPasteRequest) -> Bool)?
    /// 「去设置 / 下载语言」：面板先隐藏再交给翻译服务处理
    @ObservationIgnored var onResolve: ((TranslationFailure) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    /// 丢弃过期任务的事件
    @ObservationIgnored private var token = 0
    /// 大模型停留期间待发送的翻译（停留结束或用户按 ↩ 时开始）
    @ObservationIgnored private var held: (item: ClipItem, plan: ClipTranslationPlan, token: Int)?
    /// 这一轮还能因计划过期自动重新 plan 几次
    @ObservationIgnored private var replansLeft = maxTranslationReplans

    init(environment: ClipTranslationEnvironment) {
        self.environment = environment
    }

    var isOpen: Bool {
        card != nil
    }

    // MARK: - 打开 / 关闭 / 跟随

    /// 打开翻译卡并开始翻译；不支持的类型不打开，返回原因（调用方提示音 + 底栏提示）
    func open(_ item: ClipItem, fromPreview: Bool) -> ClipTranslationUnsupportedReason? {
        if case .unsupported(let reason) = environment.translator.eligibility(of: item) {
            return reason
        }
        let base = TranslationCard(
            itemID: item.id, isImage: item.kind == .image, mode: .translation, openedFromPreview: fromPreview,
            chosenTarget: nil)
        begin(item, from: base, dwells: false)
        return nil
    }

    func close() {
        cancelTask()
        card = nil
        flash = nil
    }

    /// 选中项变化：翻译新条目（缓存即时显示；本机引擎立即开始；云端引擎停留片刻再发送）
    func follow(_ item: ClipItem?) {
        guard let current = card else { return }
        guard let item else {
            close()
            return
        }
        guard item.id != current.itemID else { return }
        let base = TranslationCard(
            itemID: item.id, isImage: item.kind == .image, mode: current.mode,
            openedFromPreview: current.openedFromPreview, chosenTarget: current.chosenTarget)
        flash = nil
        begin(item, from: base, dwells: true)
    }

    /// esc：取消进行中的翻译（已到达的部分丢弃）；没有进行中的翻译时返回 false
    func cancelWork() -> Bool {
        guard var current = card, current.phase.isWorking else { return false }
        cancelTask()
        current.phase = .cancelled
        current.content = .empty
        current.pendingPaste = nil
        card = current
        return true
    }

    /// 面板隐藏：取消一切并关闭
    func tearDown() {
        close()
        flashTask?.cancel()
    }

    // MARK: - 视图

    func setMode(_ mode: TranslationViewMode) {
        guard var current = card, current.mode != mode else { return }
        current.mode = mode
        current.isDividerFocused = false
        card = current
    }

    /// ← / →：卷帘获得焦点时微调分隔线（每步 wipeStep），否则按方向切换视图
    func step(_ delta: Int) {
        guard let current = card, !Self.isInformational(current.phase) else { return }
        if current.isImage, current.mode == .sideBySide, current.isDividerFocused {
            setWipe(current.wipe + Double(delta) * Self.wipeStep, focusDivider: true)
            return
        }
        let modes = TranslationViewMode.allCases
        let next = min(max(current.mode.rawValue + delta.signum(), 0), modes.count - 1)
        setMode(modes[next])
    }

    /// 卷帘：拖动或微调分隔线；0…1
    func setWipe(_ value: Double, focusDivider: Bool) {
        guard var current = card else { return }
        current.wipe = min(max(value, 0), 1)
        current.isDividerFocused = focusDivider || current.isDividerFocused
        card = current
    }

    /// 按住 ⌥ 看原文（完成且不在「原文」视图时）
    func setPeeking(_ peeking: Bool) {
        guard var current = card else { return }
        let allowed = peeking && current.phase == .done && current.mode != .original
        guard current.isPeeking != allowed else { return }
        current.isPeeking = allowed
        card = current
    }

    // MARK: - 语言

    /// 语言选单选定目标语言：取消对调，按新语言重新翻译
    func choose(target: String) {
        guard let current = card, let item = environment.item(current.itemID) else { return }
        environment.translator.setTarget(target, rememberFor: nil)
        var base = current
        base.chosenTarget = target
        base.isReversed = false
        // 换了目标语言就是另一次发送：疑似密钥要重新确认
        base.confirmedPlan = nil
        begin(item, from: base, dwells: false)
    }

    /// 「粘贴到 <App> 时总是译为此语言」：已记住当前语言时取消记住（回到自动）
    func toggleRememberTarget() {
        guard let current = card, !current.isReversed, let target = current.plan?.languages.target,
            let bundleID = environment.pasteTarget()?.bundleID
        else { return }
        let remembered = environment.translator.rememberedTarget(for: bundleID)
        let isRemembered = remembered.map { environment.isSameLanguage($0, target) } ?? false
        environment.translator.setTarget(isRemembered ? nil : target, rememberFor: bundleID)
        showFlash(TranslationCopy.rememberFlash(target: isRemembered ? nil : target, app: environment.pasteTarget()))
    }

    /// ⇄ 对调：把当前译文译回源语言（不写缓存）；再按一次回到正向（命中缓存）
    func swap() {
        guard let current = card, current.canSwap, let item = environment.item(current.itemID) else { return }
        var base = current
        base.isReversed.toggle()
        if base.isReversed, let plan = current.plan, let source = plan.detectedSource,
            let forward = current.content.result
        {
            let languages = TranslationLanguages(source: plan.languages.target, target: source)
            run(stream: environment.translator.translate(text: forward.plainText, languages: languages), card: base)
            return
        }
        begin(item, from: base, dwells: false)
    }

    // MARK: - 粘贴

    /// 粘贴译文：已完成立即粘贴；进行中记下，完成后粘贴；其他状态提示原因
    func paste(_ style: TranslationPasteStyle) {
        guard var current = card else { return }
        if let result = current.result, let item = environment.item(current.itemID) {
            onPaste?(TranslationPasteRequest(item: item, result: result, style: style, origin: .card))
            return
        }
        if current.phase.isWorking {
            current.pendingPaste = style
            card = current
            // 停留期间按 ↩ 是明确要这条的译文：不再等，立即发送
            if current.phase == .holding { startHeld(token: token) }
            return
        }
        NSSound.beep()
        showFlash(TranslationFlash(message: TranslationCopy.noTranslationYet(current.phase), isWarning: true))
    }

    // MARK: - 失败与确认

    /// 「仍然翻译」：本次、本条确认后发送
    func confirmSecret() {
        guard var base = card, let item = environment.item(base.itemID) else { return }
        base.confirmedPlan = base.plan
        begin(item, from: base, dwells: false)
    }

    func retry() {
        guard let base = card, let item = environment.item(base.itemID) else { return }
        begin(item, from: base, dwells: false)
    }

    /// 「去设置 / 下载语言」
    func resolveFailure() {
        guard case .failed(let failure) = card?.phase, environment.translator.canResolve(failure) else { return }
        onResolve?(failure)
    }

    // MARK: - 翻译流程

    /// 判断资格与计划，然后开始（云端引擎在跟随选中项时先停留）。isReplan：计划过期后的自动重试
    private func begin(_ item: ClipItem, from base: TranslationCard, dwells: Bool, isReplan: Bool = false) {
        cancelTask()
        if !isReplan { replansLeft = maxTranslationReplans }
        var next = base
        next.content = .empty
        next.pendingPaste = nil
        next.isPeeking = false
        next.elapsed = nil
        let outcome = TranslationPlanning.outcome(
            for: item, target: base.chosenTarget, confirmedPlan: base.confirmedPlan, environment: environment)
        switch outcome {
        case .unsupported(let reason):
            next.plan = nil
            next.phase = .unsupported(reason)
        case .failed(let failure):
            next.plan = nil
            next.phase = .failed(failure)
        case .alreadyTarget(let plan):
            next.plan = plan
            next.phase = .alreadyTarget(plan.languages.target)
        case .needsSecretConfirmation(let plan):
            next.plan = plan
            next.phase = .needsSecretConfirmation
        case .ready(let plan):
            next.plan = plan
            // 确认只对同一次发送有效：计划变了（重试时引擎或主机已变）就作废
            if !plan.isConfirmed(by: next.confirmedPlan) { next.confirmedPlan = nil }
            let dwell = TranslationSendDwell.remaining(
                sendsTextOffDevice: plan.sendsTextOffDevice, isCached: plan.isCached, elapsed: .zero,
                total: environment.timings.cloudDwell)
            start(item, plan: plan, card: next, dwells: dwells && dwell > .zero)
            return
        }
        card = next
    }

    private func start(_ item: ClipItem, plan: ClipTranslationPlan, card base: TranslationCard, dwells: Bool) {
        let stream = { [environment] in
            environment.translator.translate(
                item, plan: plan, confirmedSecret: plan.isConfirmed(by: base.confirmedPlan))
        }
        guard dwells else {
            run(stream: stream(), card: base)
            return
        }
        var holding = base
        holding.phase = .holding
        card = holding
        token += 1
        let current = token
        held = (item, plan, current)
        let dwell = environment.timings.cloudDwell
        task = Task { [weak self] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            self?.startHeld(token: current)
        }
    }

    /// 停留结束：按卡片的最新状态开始（停留期间切换的视图、记下的 ↩ 都保留）
    private func startHeld(token current: Int) {
        guard let held, held.token == current, token == current, let latest = card, latest.itemID == held.item.id
        else { return }
        self.held = nil
        let stream = environment.translator.translate(
            held.item, plan: held.plan, confirmedSecret: held.plan.isConfirmed(by: latest.confirmedPlan))
        run(stream: stream, card: latest)
    }

    private func run(stream: AsyncThrowingStream<ClipTranslationEvent, any Error>, card base: TranslationCard) {
        cancelTask()
        var running = base
        running.phase = .waiting
        running.content = .empty
        running.startedAt = .now
        running.runID += 1
        card = running
        let current = token
        task = Task { [weak self] in
            let end = await TranslationStream.consume(stream) { event in
                self?.apply(event, token: current)
            }
            self?.finish(end, token: current)
        }
    }

    private func apply(_ event: ClipTranslationEvent, token current: Int) {
        guard current == token, var running = card else { return }
        running.content = running.content.applying(event)
        switch event {
        case .started: break
        case .segment, .imageBlock: running.phase = .streaming
        case .finished(let result) where result.isEmpty:
            // 图片里没有可翻译的文字（设计文档与 C3 的约定：空结果、不缓存）
            running.phase = .unsupported(.noText)
            running.content = .empty
            running.pendingPaste = nil
        case .finished:
            running.phase = .done
            running.elapsed = running.startedAt.map { ContinuousClock.now - $0 }
        }
        card = running
    }

    private func finish(_ end: TranslationStreamEnd, token current: Int) {
        guard current == token, var ended = card else { return }
        switch end {
        case .cancelled:
            return
        case .failed(let failure):
            ended.phase = .failed(failure)
            ended.content = .empty
            ended.pendingPaste = nil
            card = ended
        case .refused(let refusal):
            handle(refusal, card: ended)
        case .finished where ended.phase == .unsupported(.noText):
            return
        case .finished:
            guard ended.phase == .done else {
                // 流结束却没有 finished 事件：视为返回内容无法解析，不粘贴、不显示部分结果
                ended.phase = .failed(.invalidResponse)
                ended.content = .empty
                ended.pendingPaste = nil
                card = ended
                return
            }
            if let style = ended.pendingPaste {
                ended.pendingPaste = nil
                card = ended
                paste(style)
            }
        }
    }

    /// 服务拒绝发送（什么都没发出）：计划过期 → 重新 plan 并重试（新计划需要确认疑似密钥时显示确认页）；
    /// 疑似密钥未确认 → 显示确认页；⇄ 对调无法确认 → 提示后回到正向译文
    private func handle(_ refusal: ClipTranslationRefusal, card ended: TranslationCard) {
        guard let item = environment.item(ended.itemID) else { return }
        var base = ended
        base.content = .empty
        switch refusal {
        case .secretNotConfirmed where ended.isReversed:
            base.isReversed = false
            showFlash(TranslationFlash(message: TranslationCopy.swapRefusedForSecret, isWarning: true))
            begin(item, from: base, dwells: false)
        case .secretNotConfirmed:
            base.phase = .needsSecretConfirmation
            base.pendingPaste = nil
            card = base
        case .planOutdated where replansLeft > 0:
            replansLeft -= 1
            base.isReversed = false
            begin(item, from: base, dwells: false, isReplan: true)
        case .planOutdated:
            base.phase = .failed(.invalidResponse)
            base.pendingPaste = nil
            card = base
        }
    }

    private func cancelTask() {
        token += 1
        held = nil
        task?.cancel()
        task = nil
    }

    // MARK: - 提示

    func showFlash(_ newFlash: TranslationFlash) {
        flash = newFlash
        flashTask?.cancel()
        let duration = environment.timings.flash
        flashTask = Task { [weak self, id = newFlash.id] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, self.flash?.id == id else { return }
            self.flash = nil
        }
    }

    /// 卷帘微调一步（⇧ 为 PanelCommand.largeTranslationStep 步）
    static let wipeStep = 0.02

    /// 不显示内容的阶段（← / → 不切换视图）
    static func isInformational(_ phase: TranslationCardPhase) -> Bool {
        if case .unsupported = phase { return true }
        return false
    }
}
