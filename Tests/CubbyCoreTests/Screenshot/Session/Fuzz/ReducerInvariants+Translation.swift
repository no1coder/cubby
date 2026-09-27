import CoreGraphics
@testable import CubbyCore

/// 截图翻译的不变量
extension ReducerInvariantChecks {
    static func translation(_ step: FuzzStep) -> String? {
        let session = step.session
        if let active = session.activeTranslation {
            guard session.document.translation == active else { return "active run is not the applied translation" }
            guard session.translationRuns[active]?.status.isBusy == true else { return "active run is not busy" }
        }
        if let id = session.document.translation, session.translationRuns[id] == nil {
            return "document references a missing run"
        }
        if let run = session.translation {
            if let problem = runProblem(run) {
                return problem
            }
            if run.status.isBusy && session.activeTranslation != run.id {
                return "busy run without an active job"
            }
        }
        if case .split(let x) = session.translationDisplay {
            guard let selection = session.selection, x >= selection.minX, x <= selection.maxX else {
                return "wipe divider outside the selection"
            }
        }
        return exportProblem(session)
    }

    /// 候选 ⊆ 块；已到达 ⊆ 候选；结束后只保留本次到达的译文
    private static func runProblem(_ run: TranslationRun) -> String? {
        let blockIDs = Set(run.blocks.map(\.id))
        if !Set(run.candidateIDs).isSubset(of: blockIDs) {
            return "candidates outside the recognized blocks"
        }
        if !run.arrivedIDs.isSubset(of: Set(run.candidateIDs)) && !run.candidateIDs.isEmpty {
            return "arrived blocks outside the candidates"
        }
        if !run.status.isBusy && !Set(run.translatedBlocks.map(\.blockID)).isSubset(of: run.arrivedIDs) {
            return "finished run still shows inherited blocks"
        }
        return nil
    }

    /// 导出只由「原文 | 译文」开关决定
    private static func exportProblem(_ session: ScreenshotSession) -> String? {
        let expected = session.showsTranslation ? session.translation?.translatedBlocks ?? [] : []
        return session.exportedTranslation == expected
            ? nil : "export does not follow the original / translation switch"
    }
}
