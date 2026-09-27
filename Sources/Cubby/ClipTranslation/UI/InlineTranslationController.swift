import AppKit
import CubbyCore
import Observation

/// ⌥↩ 翻译后粘贴（不开卡片）：卡片行内显示进度，完成后粘贴；失败只在行内给出原因与操作，
/// **绝不退回粘贴原文**，部分完成不粘贴（docs/CLIP-TRANSLATION-DESIGN.md §4）
@MainActor
@Observable
final class InlineTranslationController {
    private(set) var job: InlineTranslation?

    @ObservationIgnored let environment: ClipTranslationEnvironment
    @ObservationIgnored var onPaste: ((TranslationPasteRequest) -> Void)?
    @ObservationIgnored var onResolve: ((TranslationFailure) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var token = 0
    /// 这一次 ⌥↩ 还能因计划过期自动重新 plan 几次
    @ObservationIgnored private var replansLeft = maxTranslationReplans

    init(environment: ClipTranslationEnvironment) {
        self.environment = environment
    }

    /// 开始（对另一条再按 ⌥↩ 会取消旧任务）；不支持的类型返回原因，不开始
    /// confirmedPlan：点「仍然翻译」时看到的计划（只对同一次发送有效）
    func start(_ item: ClipItem, confirmedPlan: ClipTranslationPlan? = nil) -> ClipTranslationUnsupportedReason? {
        replansLeft = maxTranslationReplans
        return plan(item, confirmedPlan: confirmedPlan)
    }

    private func plan(_ item: ClipItem, confirmedPlan: ClipTranslationPlan?) -> ClipTranslationUnsupportedReason? {
        cancelTasks()
        let outcome = TranslationPlanning.outcome(
            for: item, target: nil, confirmedPlan: confirmedPlan, environment: environment)
        switch outcome {
        case .unsupported(let reason):
            job = nil
            return reason
        case .failed(let failure):
            job = failedJob(item, plan: nil, issue: .failure(failure), confirmedPlan: confirmedPlan)
        case .alreadyTarget(let plan):
            job = failedJob(
                item, plan: plan, issue: .alreadyTarget(plan.languages.target), confirmedPlan: confirmedPlan)
        case .needsSecretConfirmation(let plan):
            job = failedJob(
                item, plan: plan, issue: .needsSecretConfirmation(TranslationCopy.shortEngineName(plan.engineName)),
                confirmedPlan: confirmedPlan)
        case .ready(let plan):
            run(item, plan: plan, confirmedPlan: confirmedPlan)
        }
        return nil
    }

    /// esc / 面板关闭 / 选中项变化：取消进行中的任务；返回是否确实取消了进行中的任务
    @discardableResult
    func cancel() -> Bool {
        let wasRunning = job?.isRunning ?? false
        cancelTasks()
        job = nil
        return wasRunning
    }

    /// 行内问题上的按钮：重试 / 仍然翻译 / 去设置 / 下载语言
    func performAction() {
        guard let current = job, case .failed(let issue) = current.phase,
            let item = environment.item(current.itemID)
        else { return }
        switch issue {
        case .needsSecretConfirmation:
            _ = start(item, confirmedPlan: current.plan)
        case .failure(let failure) where environment.translator.canResolve(failure):
            job = nil
            onResolve?(failure)
        case .failure, .timedOut, .pasteFailed:
            _ = start(item, confirmedPlan: current.confirmedPlan)
        case .alreadyTarget, .nothingToTranslate:
            break
        }
    }

    /// 行内问题的操作类型（视图据此显示按钮文案）
    func action(for issue: InlineTranslationIssue) -> InlineTranslationAction? {
        switch issue {
        case .needsSecretConfirmation: .translateAnyway
        case .failure(let failure):
            environment.translator.canResolve(failure) ? .resolve(failure) : .retry
        case .timedOut, .pasteFailed: .retry
        case .alreadyTarget, .nothingToTranslate: nil
        }
    }

    // MARK: - 流程

    private func run(_ item: ClipItem, plan: ClipTranslationPlan, confirmedPlan: ClipTranslationPlan?) {
        job = InlineTranslation(
            itemID: item.id, plan: plan, phase: .running, content: .empty, confirmedPlan: confirmedPlan)
        token += 1
        let current = token
        let stream = environment.translator.translate(
            item, plan: plan, confirmedSecret: plan.isConfirmed(by: confirmedPlan))
        task = Task { [weak self] in
            let end = await TranslationStream.consume(stream) { event in
                self?.apply(event, token: current)
            }
            self?.finish(end, token: current)
        }
        let cap = environment.timings.inlineCap
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: cap)
            guard let self, !Task.isCancelled, self.token == current else { return }
            self.fail(.timedOut)
        }
    }

    private func apply(_ event: ClipTranslationEvent, token current: Int) {
        guard current == token, var running = job else { return }
        running.content = running.content.applying(event)
        job = running
    }

    private func finish(_ end: TranslationStreamEnd, token current: Int) {
        guard current == token, let running = job else { return }
        switch end {
        case .cancelled:
            return
        case .failed(let failure):
            fail(.failure(failure))
        case .refused(let refusal):
            handle(refusal, job: running)
        case .finished:
            guard let result = running.content.result, let item = environment.item(running.itemID) else {
                fail(.failure(.invalidResponse))
                return
            }
            guard !result.isEmpty else {
                fail(.nothingToTranslate)
                return
            }
            watchdog?.cancel()
            job = nil
            onPaste?(TranslationPasteRequest(item: item, result: result, style: .standard, origin: .inline))
        }
    }

    /// 服务拒绝发送（什么都没发出）：计划过期 → 重新 plan 再翻译；疑似密钥未确认 → 行内「仍然翻译」
    private func handle(_ refusal: ClipTranslationRefusal, job running: InlineTranslation) {
        switch refusal {
        case .planOutdated where replansLeft > 0:
            guard let item = environment.item(running.itemID) else { return }
            replansLeft -= 1
            _ = plan(item, confirmedPlan: running.confirmedPlan)
        case .planOutdated:
            fail(.failure(.invalidResponse))
        case .secretNotConfirmed:
            fail(.needsSecretConfirmation(TranslationCopy.shortEngineName(running.plan?.engineName ?? "")))
        }
    }

    /// 写剪贴板失败（由面板控制器回报）
    func reportPasteFailure(for item: ClipItem) {
        job = failedJob(item, plan: nil, issue: .pasteFailed, confirmedPlan: nil)
    }

    private func fail(_ issue: InlineTranslationIssue) {
        guard var failed = job else { return }
        cancelTasks()
        failed.phase = .failed(issue)
        failed.content = .empty
        job = failed
    }

    private func failedJob(
        _ item: ClipItem, plan: ClipTranslationPlan?, issue: InlineTranslationIssue,
        confirmedPlan: ClipTranslationPlan?
    ) -> InlineTranslation {
        InlineTranslation(
            itemID: item.id, plan: plan, phase: .failed(issue), content: .empty, confirmedPlan: confirmedPlan)
    }

    private func cancelTasks() {
        token += 1
        task?.cancel()
        watchdog?.cancel()
        task = nil
        watchdog = nil
    }
}

/// 行内问题上的按钮
enum InlineTranslationAction: Equatable {
    case retry
    case translateAnyway
    /// 去设置 / 下载语言
    case resolve(TranslationFailure)
}
