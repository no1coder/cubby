import CoreGraphics
@testable import CubbyCore

/// 模糊测试里的截图翻译：用户操作，以及按进行中那次运行的阶段模拟流水线回报（偶尔故意发过期回报）
enum FuzzTranslation {
    static let targets = ["zh-Hans", "ja", "fr", "en"]

    static func event(_ rng: inout FuzzRandom, session: ScreenshotSession) -> ScreenshotEvent {
        if let active = session.activeTranslation, let run = session.translationRuns[active], rng.chance(0.75) {
            return .translation(report(&rng, run: run))
        }
        if rng.chance(0.05) {
            // 过期回报：不属于进行中的运行
            let stale = TranslationRunID(rawValue: session.translationSerial + rng.int(below: 3) - 2)
            return .translation(.finished(stale))
        }
        return user(&rng, session: session)
    }

    /// 用户操作
    static func user(_ rng: inout FuzzRandom, session: ScreenshotSession) -> ScreenshotEvent {
        let selection = session.selection ?? CGRect(x: 0, y: 0, width: 100, height: 100)
        let x = rng.value(in: selection.minX - 40, selection.maxX + 40)
        return rng.weighted([
            (6, .command(.translate)),
            (3, .translation(.start)),
            (3, .translation(.retry)),
            (2, .translation(.retranslateSelection)),
            (3, .translation(.changeTarget(rng.pick(targets)))),
            (3, .translation(.showTranslation(rng.chance(0.5)))),
            (3, .translation(.setWipe(rng.chance(0.6)))),
            (3, .translation(.moveWipe(x))),
        ])
    }

    /// 按阶段挑一个合理的回报
    private static func report(_ rng: inout FuzzRandom, run: TranslationRun) -> TranslationEvent {
        let id = run.id
        if rng.chance(0.08) {
            return .failed(id, rng.pick([.network, .notConfigured, .languageNotInstalled, .server(status: 503)]))
        }
        switch run.status {
        case .recognizing:
            return .recognized(id, rng.chance(0.1) ? [] : blocks(in: run.area))
        case .translating(_, let total) where total == 0:
            let ids = run.blocks.map(\.id).filter { _ in rng.chance(0.7) }
            return rng.weighted([
                (10, .started(id, plan(ids.isEmpty ? [0] : ids, target: rng.pick(targets)))),
                (1, .nothingToTranslate(id)), (1, .needsTargetLanguage(id)),
            ])
        case .translating:
            let pending = run.pendingBlocks
            guard let block = pending.isEmpty ? nil : rng.pick(pending), rng.chance(0.8) else { return .finished(id) }
            return .arrived(id, placed(block))
        default:
            return .finished(id)
        }
    }

    /// 区域内的三个块（第三个块压在区域下缘外，模拟选区缩小后露在外面的块）
    static func blocks(in area: CGRect) -> [TextBlock] {
        let width = max(area.width * 0.6, 10)
        return (0..<3).map { index in
            let frame = CGRect(
                x: area.minX + 8, y: area.minY + 8 + CGFloat(index) * area.height / 3, width: width, height: 14)
            let text = "Block \(index)"
            return TextBlock(
                id: index, lines: [RecognizedLine(text: text, frame: frame)], alignment: .leading, text: text)
        }
    }

    static func plan(_ ids: [Int], target: String) -> TranslationPlan {
        TranslationPlan(
            blockIDs: ids, languages: TranslationLanguages(source: "en", target: target),
            engine: TranslationEngineBadge(name: "Fuzz", sendsTextOffDevice: false))
    }

    static func placed(_ block: TextBlock) -> TranslatedBlock {
        let erase = block.frame.insetBy(dx: -2, dy: -2)
        return TranslatedBlock(
            blockID: block.id, eraseFrame: erase, backdrop: .solid(.white), text: "T" + block.text, textFrame: erase,
            fontSize: 11, isBold: false, textColor: .black, alignment: .leading)
    }

    // MARK: - 渲染为 Swift 代码（失败报告）

    static func swift(_ event: TranslationEvent) -> String {
        switch event {
        case .start: ".start"
        case .retry: ".retry"
        case .retranslateSelection: ".retranslateSelection"
        case .changeTarget(let target): ".changeTarget(\(FuzzRendering.swift(target)))"
        case .showTranslation(let shows): ".showTranslation(\(shows))"
        case .setWipe(let enabled): ".setWipe(\(enabled))"
        case .moveWipe(let x): ".moveWipe(\(x))"
        case .recognized(let id, let blocks):
            ".recognized(\(swift(id)), \(blocks.isEmpty ? "[]" : "FuzzTranslation.blocks(in: \(area(blocks)))"))"
        case .started(let id, let plan):
            ".started(\(swift(id)), FuzzTranslation.plan(\(plan.blockIDs), target: \"\(plan.languages.target)\"))"
        case .arrived(let id, let block):
            ".arrived(\(swift(id)), FuzzTranslation.placed(\(swift(block))))"
        case .finished(let id): ".finished(\(swift(id)))"
        case .failed(let id, let failure): ".failed(\(swift(id)), .\(failure))"
        case .nothingToTranslate(let id): ".nothingToTranslate(\(swift(id)))"
        case .needsTargetLanguage(let id): ".needsTargetLanguage(\(swift(id)))"
        }
    }

    private static func swift(_ id: TranslationRunID) -> String {
        "TranslationRunID(rawValue: \(id.rawValue))"
    }

    /// 译文块对应的原文块（按 `placed` 的逆运算）
    private static func swift(_ block: TranslatedBlock) -> String {
        let frame = block.eraseFrame.insetBy(dx: 2, dy: 2)
        let text = String(block.text.dropFirst())
        return """
            TextBlock(id: \(block.blockID), lines: [RecognizedLine(text: \(FuzzRendering.swift(text)), \
            frame: \(FuzzRendering.swift(frame)))], alignment: .leading, text: \(FuzzRendering.swift(text)))
            """
    }

    /// `blocks(in:)` 的逆运算：由第一块推回区域（宽度按第一块宽度 / 0.6，高度按第二块的间距）
    private static func area(_ blocks: [TextBlock]) -> String {
        let first = blocks[0].frame
        let height = blocks.count > 1 ? (blocks[1].frame.minY - first.minY) * 3 : first.height
        return FuzzRendering.swift(
            CGRect(x: first.minX - 8, y: first.minY - 8, width: first.width / 0.6, height: height))
    }
}
