import CoreGraphics

/// 截图翻译流水线的回报：只接受进行中那次运行、且阶段对得上的回报，其余（被取消的旧任务迟到的回报等）一律忽略。
/// 译文内容原地更新到会话的 `translationRuns`，文档不变（流式到达的块不占撤销步）
extension ScreenshotReducer {
    static func reducingReport(_ session: ScreenshotSession, _ event: TranslationEvent) -> ScreenshotSession {
        guard let active = session.activeTranslation, let run = session.translationRuns[active],
            let updated = reported(run, event)
        else { return session }
        return session.storing(updated).updating {
            $0.activeTranslation = updated.status.isBusy ? active : nil
        }
    }

    /// 回报作用于 run 后的新值；不属于它或阶段不符时为 nil
    private static func reported(_ run: TranslationRun, _ event: TranslationEvent) -> TranslationRun? {
        switch event {
        case .recognized(let id, let blocks) where id == run.id && run.status == .recognizing:
            return blocks.isEmpty
                ? ending(run, .noText)
                : run.updating { draft in
                    draft.blocks = blocks
                    draft.status = .translating(done: 0, total: 0)
                }
        case .started(let id, let plan) where id == run.id && run.isTranslatingPhase:
            return starting(run, plan)
        case .arrived(let id, let block) where id == run.id && run.isTranslatingPhase:
            return arriving(run, block)
        case .finished(let id) where id == run.id && run.isTranslatingPhase:
            return finishing(run, failure: nil)
        case .failed(let id, let failure) where id == run.id && run.status.isBusy:
            return finishing(run, failure: failure)
        case .nothingToTranslate(let id) where id == run.id && run.status.isBusy:
            return ending(run, .noText)
        case .needsTargetLanguage(let id) where id == run.id && run.status.isBusy:
            return ending(run, .needsTargetLanguage)
        default:
            return nil
        }
    }

    /// 引擎已创建：送去翻译的块并入候选（重试时只是其中缺失的那些），记下语言与引擎
    private static func starting(_ run: TranslationRun, _ plan: TranslationPlan) -> TranslationRun {
        let known = Set(run.blocks.map(\.id))
        let candidates = Set(run.candidateIDs).union(plan.blockIDs).intersection(known).sorted()
        guard !candidates.isEmpty else { return ending(run, .noText) }
        let done = run.arrivedIDs.intersection(candidates).count
        return run.updating {
            $0.candidateIDs = candidates
            $0.languages = plan.languages
            $0.engine = plan.engine
            $0.status = .translating(done: done, total: candidates.count)
        }
    }

    /// 一块译文到达：替换（或新增）这块的版面；只接受候选块
    private static func arriving(_ run: TranslationRun, _ block: TranslatedBlock) -> TranslationRun? {
        guard run.candidateIDs.contains(block.blockID) else { return nil }
        let arrived = run.arrivedIDs.union([block.blockID])
        return run.updating {
            $0.placed = run.placed.merging([block.blockID: block]) { $1 }
            $0.arrivedIDs = arrived
            $0.status = .translating(done: arrived.intersection(run.candidateIDs).count, total: run.candidateIDs.count)
        }
    }

    /// 结束：全部到达 → 完成；部分到达 → 部分完成（未到达的块回到原文）；一块没有 → 失败。
    /// 换语言时继承、没被新译文替换的旧块一并丢掉（不能把上一种语言当成这次的结果）
    static func finishing(_ run: TranslationRun, failure: TranslationFailure?) -> TranslationRun {
        let arrived = run.arrivedIDs.intersection(run.candidateIDs)
        let missing = run.candidateIDs.count - arrived.count
        let status: TranslationStatus
        if arrived.isEmpty {
            status = .failed(failure ?? .invalidResponse)
        } else if missing == 0 {
            status = .ready
        } else {
            status = .partial(missing: missing, failure: failure)
        }
        return ending(run, status)
    }

    /// 以 status 结束：只保留本次运行到达的译文
    private static func ending(_ run: TranslationRun, _ status: TranslationStatus) -> TranslationRun {
        run.updating {
            $0.status = status
            $0.placed = run.placed.filter { run.arrivedIDs.contains($0.key) }
            $0.isRetrying = false
        }
    }
}

extension TranslationRun {
    /// 识别完成后的翻译阶段（等引擎、等译文）
    fileprivate var isTranslatingPhase: Bool {
        if case .translating = status { return true }
        return false
    }
}
