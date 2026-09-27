import CoreGraphics

/// 截图翻译的用户操作（docs/TRANSLATION-DESIGN.md §2）：开始 / 切换、重试、换语言、选区变化后重译、
/// 「原文 | 译文」开关、卷帘；以及翻译进行中的 Esc。流水线回报见 +TranslationReports
extension ScreenshotReducer {
    static func reduceTranslation(
        _ session: ScreenshotSession,
        _ event: TranslationEvent,
        topology: ScreenTopology
    ) -> Result {
        guard session.isTranslationAvailable else { return (session, []) }
        switch event {
        case .start: return startingTranslation(session, topology: topology)
        case .retry: return retryingTranslation(session)
        case .retranslateSelection: return retranslatingSelection(session, topology: topology)
        case .changeTarget(let target): return changingTarget(session, to: target)
        case .showTranslation(let shows): return (showingTranslation(session, shows), [])
        case .setWipe(let enabled): return (settingWipe(session, enabled), [])
        case .moveWipe(let x): return (movingWipe(session, to: x), [])
        case .recognized, .started, .arrived, .finished, .failed, .nothingToTranslate, .needsTargetLanguage:
            return (reducingReport(session, event), [])
        }
    }

    // MARK: - 开始 / 切换 / 重试

    /// ⇧⌘T：没有译文 → 开始（一步撤销）；进行中 → 忽略；已有结果 → 切换原文 / 译文；失败等 → 原地重试
    private static func startingTranslation(_ session: ScreenshotSession, topology: ScreenTopology) -> Result {
        guard session.canEditSelection, let selection = session.selection,
            let screenID = selectionScreenID(session, topology: topology)
        else { return (session, []) }
        guard let run = session.translation else {
            return beginningRun(session, parent: nil, area: selection, screenID: screenID)
        }
        if run.status.isBusy {
            return (session, [])
        }
        if run.hasResult {
            return (session.updating { $0.showsTranslation = !session.showsTranslation }, [])
        }
        return restarting(session, run, languages: run.languages)
    }

    /// 翻译条「重试」：部分失败只重发缺失的块（沿用语言、不重新识别）；失败 / 无文字 / 待选语言整体重来
    private static func retryingTranslation(_ session: ScreenshotSession) -> Result {
        guard let run = session.translation, !run.status.isBusy else { return (session, []) }
        guard case .partial = run.status else {
            return run.isDismissible ? restarting(session, run, languages: run.languages) : (session, [])
        }
        guard let languages = run.languages else { return (session, []) }
        return retryingMissing(session, run, languages: languages)
    }

    /// 重发缺失的块。之后才被马赛克遮住的块不再发送（设计文档 D6），也不再算作缺失；都被遮住时直接结束
    private static func retryingMissing(
        _ session: ScreenshotSession,
        _ run: TranslationRun,
        languages: TranslationLanguages
    ) -> Result {
        let hidden = session.translationHiddenRegions
        let missingIDs = Set(run.candidateIDs).subtracting(run.arrivedIDs)
        let covered = Set(
            run.blocks.filter { missingIDs.contains($0.id) && TranslationCandidates.isHidden($0.frame, by: hidden) }
                .map(\.id))
        let candidates = run.candidateIDs.filter { !covered.contains($0) }
        let missing = run.blocks.filter { missingIDs.contains($0.id) && !covered.contains($0.id) }
        guard !missing.isEmpty else {
            return (session.storing(finishing(run.updating { $0.candidateIDs = candidates }, failure: nil)), [])
        }
        let retried = run.updating {
            $0.candidateIDs = candidates
            $0.status = .translating(done: run.arrivedIDs.intersection(candidates).count, total: candidates.count)
            $0.isRetrying = true
        }
        let effect = TranslationEffect.retry(
            run.id, blocks: missing, screenID: run.screenID, languages: languages, hidden: hidden)
        return (session.storing(retried).updating { $0.activeTranslation = run.id }, [.translation(effect)])
    }

    /// 「选区已变化 · 重新翻译」：按当前选区重新识别，新的一次运行（一步撤销，Esc 回到之前的译文）
    private static func retranslatingSelection(_ session: ScreenshotSession, topology: ScreenTopology) -> Result {
        guard session.isTranslationStale, session.canEditSelection, let run = session.translation,
            let selection = session.selection, let screenID = selectionScreenID(session, topology: topology)
        else { return (session, []) }
        return beginningRun(session, parent: run.id, area: selection, screenID: screenID)
    }

    /// 语言选单：已有结果 → 新的一次运行沿用已识别的块重译（旧译文先留着，逐块替换；一步撤销）；
    /// 进行中 / 失败 / 待选语言 → 同一次运行原地重来
    private static func changingTarget(_ session: ScreenshotSession, to target: String) -> Result {
        guard let run = session.translation, !session.isPointerBusy else { return (session, []) }
        let settled = run.hasResult || run.status.isBusy
        if settled && run.languages?.target == target {
            return (session, [])
        }
        let languages = TranslationLanguages(source: run.languages?.source, target: target)
        guard run.hasResult else {
            return restarting(session, run, languages: languages)
        }
        let id = TranslationRunID(rawValue: session.translationSerial)
        let child = TranslationRun(
            id: id, parent: run.id, area: run.area, screenID: run.screenID,
            status: .translating(done: 0, total: 0), languages: languages, engine: run.engine, blocks: run.blocks,
            candidateIDs: [], placed: run.placed, arrivedIDs: [], isRetrying: false)
        let updated = session.storing(child).updating {
            $0.translationSerial = session.translationSerial + 1
            $0.document = session.document.applyingTranslation(id)
            $0.activeTranslation = id
            $0.showsTranslation = true
        }
        let effect = TranslationEffect.translate(
            id, blocks: run.blocks, screenID: run.screenID, hidden: session.translationHiddenRegions)
        return (updated, [.translation(effect)])
    }

    /// 新的一次运行：从识别开始，文档应用它（一步撤销）
    private static func beginningRun(
        _ session: ScreenshotSession,
        parent: TranslationRunID?,
        area: CGRect,
        screenID: UInt32
    ) -> Result {
        let id = TranslationRunID(rawValue: session.translationSerial)
        let run = TranslationRun.recognizing(id: id, parent: parent, area: area, screenID: screenID, languages: nil)
        let updated = session.storing(run).updating {
            $0.translationSerial = session.translationSerial + 1
            $0.document = session.document.applyingTranslation(id)
            $0.activeTranslation = id
            $0.showsTranslation = true
        }
        let effect = TranslationEffect.recognize(
            id, selection: area, screenID: screenID, hidden: session.translationHiddenRegions)
        return (updated, [.translation(effect)])
    }

    /// 同一次运行原地重来（不新增撤销步）：已识别过块就重新过滤、判断语言后翻译，否则按当前选区重新识别。
    /// 进行中的旧任务由流水线在开始新任务时取消；已显示的旧译文留到被新译文替换
    private static func restarting(
        _ session: ScreenshotSession,
        _ run: TranslationRun,
        languages: TranslationLanguages?
    ) -> Result {
        let hidden = session.translationHiddenRegions
        let restarted: TranslationRun
        let effect: TranslationEffect
        if run.blocks.isEmpty {
            let area = session.selection ?? run.area
            let screenID = session.screenID ?? run.screenID
            restarted = run.updating {
                $0.status = .recognizing
                $0.area = area
                $0.screenID = screenID
                $0.languages = languages
            }
            effect = .recognize(run.id, selection: area, screenID: screenID, hidden: hidden)
        } else {
            restarted = run.updating {
                $0.status = .translating(done: 0, total: 0)
                $0.languages = languages
                $0.candidateIDs = []
                $0.arrivedIDs = []
            }
            effect = .translate(run.id, blocks: run.blocks, screenID: run.screenID, hidden: hidden)
        }
        let updated = session.storing(restarted).updating {
            $0.activeTranslation = run.id
            $0.showsTranslation = true
        }
        return (updated, [.translation(effect)])
    }

    // MARK: - 查看

    private static func showingTranslation(_ session: ScreenshotSession, _ shows: Bool) -> ScreenshotSession {
        guard session.translation?.hasResult == true, shows != session.showsTranslation else { return session }
        return session.updating { $0.showsTranslation = shows }
    }

    /// 卷帘开关：打开时分隔线在选区中点，焦点不在分隔线上
    private static func settingWipe(_ session: ScreenshotSession, _ enabled: Bool) -> ScreenshotSession {
        guard session.translation?.hasResult == true, enabled != session.isWipeEnabled else { return session }
        return session.updating {
            $0.isWipeEnabled = enabled
            $0.wipePosition = nil
            $0.isWipeFocused = false
        }
    }

    /// 拖动分隔线：夹在选区内，分隔线获得键盘焦点
    private static func movingWipe(_ session: ScreenshotSession, to x: CGFloat) -> ScreenshotSession {
        guard session.wipeLineX != nil, let selection = session.selection else { return session }
        return session.updating {
            $0.wipePosition = ScreenshotSession.clampedWipe(x, in: selection)
            $0.isWipeFocused = true
        }
    }

    /// 分隔线有焦点时 ← / → 微调它（⇧ 大步）；其他方向键与没有焦点时返回 nil（照常移动选区 / 标注）
    static func nudgingWipe(_ session: ScreenshotSession, _ direction: NudgeDirection, large: Bool)
        -> ScreenshotSession?
    {
        guard session.isWipeFocused, let x = session.wipeLineX, let selection = session.selection,
            direction == .left || direction == .right
        else { return nil }
        let fraction = large ? ScreenshotSession.wipeLargeStep : ScreenshotSession.wipeSmallStep
        let step = selection.width * fraction * (direction == .left ? -1 : 1)
        return movingWipe(session, to: x + step)
    }

    // MARK: - Esc

    /// 翻译进行中按 Esc：只取消翻译（抹掉那一步撤销，回到翻译前）；重试部分失败时只停掉重试（回到部分完成）；
    /// 失败 / 无文字 / 待选语言：关闭翻译条。其余情况返回 nil，照常处理 Esc
    static func escapingTranslation(_ session: ScreenshotSession) -> Result? {
        guard let run = session.translation else { return nil }
        if run.status.isBusy && run.isRetrying {
            let stopped = session.storing(finishing(run, failure: nil)).updating {
                $0.activeTranslation = nil
                $0.isDiscardArmed = false
            }
            return (stopped, [.translation(.cancel), .showHint(.translationCancelled)])
        }
        if run.status.isBusy {
            let purged = purging(session, run)
            let hint: ScreenshotHint =
                purged.hasDiscardableContent ? .translationCancelled : .translationCancelledPressEscapeAgain
            return (purged, [.translation(.cancel), .showHint(hint)])
        }
        guard run.isDismissible else { return nil }
        return (purging(session, run), [.showHint(.translationClosed)])
    }

    /// 抹掉这次运行（按下鼠标时的文档快照一并处理）；这一下 Esc 用在了翻译上，之前的「待确认放弃」随之解除
    private static func purging(_ session: ScreenshotSession, _ run: TranslationRun) -> ScreenshotSession {
        let purge = { (document: AnnotationDocument) in document.purgingTranslation(run.id, restoring: run.parent) }
        return session.updating {
            $0.press = session.press.map { $0.with(document: purge($0.document)) }
            $0.document = purge(session.document)
            $0.translationRuns = session.translationRuns.filter { $0.key != run.id }
            $0.activeTranslation = nil
            $0.isDiscardArmed = false
        }
    }

    // MARK: - 查看状态的复位

    /// 选区或译文层变化时分隔线复位到中点、失去焦点；译文被撤销 / 取消后卷帘关闭（设计文档 §2）
    static func settlingTranslationView(_ updated: ScreenshotSession, previous: ScreenshotSession)
        -> ScreenshotSession
    {
        let changed =
            updated.selection != previous.selection || updated.document.translation != previous.document.translation
        let removed = updated.document.translation == nil && updated.isWipeEnabled
        guard changed || removed, updated.wipePosition != nil || updated.isWipeFocused || removed else {
            return updated
        }
        return updated.updating {
            $0.wipePosition = nil
            $0.isWipeFocused = false
            $0.isWipeEnabled = updated.isWipeEnabled && !removed
        }
    }

    /// 按下鼠标：分隔线失去键盘焦点（拖分隔线本身不经过这里，它发 `.moveWipe`）
    static func releasingWipeFocus(_ session: ScreenshotSession, for event: ScreenshotEvent) -> ScreenshotSession {
        guard session.isWipeFocused else { return session }
        switch event {
        case .mouseDown, .rightMouseDown: return session.updating { $0.isWipeFocused = false }
        default: return session
        }
    }

    /// 选区所在屏：会话记录的，或按选区中心查拓扑
    private static func selectionScreenID(_ session: ScreenshotSession, topology: ScreenTopology) -> UInt32? {
        guard let selection = session.selection else { return nil }
        return session.screenID ?? topology.screen(containing: CGPoint(x: selection.midX, y: selection.midY))?.id
    }
}
