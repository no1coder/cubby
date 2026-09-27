import CoreGraphics
@testable import CubbyCore

/// 翻译测试的夹具：标准选区里的三个块（0、1 可翻译，2 是数字不翻译）与桩译文
enum TranslationFixture {
    static let hello = block(0, "Hello", CGRect(x: 220, y: 170, width: 200, height: 20))
    static let world = block(1, "World wide", CGRect(x: 220, y: 210, width: 300, height: 20))
    static let number = block(2, "42", CGRect(x: 220, y: 250, width: 40, height: 20))
    static let blocks = [hello, world, number]
    static let candidateIDs = [0, 1]
    static let languages = TranslationLanguages(source: "en", target: "zh-Hans")
    static let engine = TranslationEngineBadge(name: "Stub", sendsTextOffDevice: false)
    static let plan = TranslationPlan(blockIDs: candidateIDs, languages: languages, engine: engine)
    static let failure = TranslationFailure.network

    static func block(_ id: Int, _ text: String, _ frame: CGRect) -> TextBlock {
        TextBlock(id: id, lines: [RecognizedLine(text: text, frame: frame)], alignment: .leading, text: text)
    }

    /// 桩排版：原位白底黑字，译文为 "[T] " + 大写原文（与 E2E 桩引擎一致）
    static func placed(_ block: TextBlock, prefix: String = "[T] ") -> TranslatedBlock {
        let erase = block.frame.insetBy(dx: -2, dy: -2)
        return TranslatedBlock(
            blockID: block.id, eraseFrame: erase, backdrop: .solid(.white), text: prefix + block.text.uppercased(),
            textFrame: erase, fontSize: 12, isBold: false, textColor: .black, alignment: .leading)
    }
}

extension SessionHarness {
    /// 标准选区（adjusting），翻译可用
    static func translatable() -> SessionHarness {
        let harness = adjusting()
        return SessionHarness(session: harness.session.settingTranslationAvailable(true), topology: harness.topology)
    }

    /// 当前运行的 id（没有时崩溃：测试前提不成立）
    var runID: TranslationRunID {
        session.translation!.id
    }

    /// 开始翻译并识别出夹具的三个块
    func startedAndRecognized() -> SessionHarness {
        let started = send(.translation(.start))
        return started.send(.translation(.recognized(started.runID, TranslationFixture.blocks)))
    }

    /// 走完一次成功的翻译：识别 → 开始 → 两块到达 → 结束
    func translated() -> SessionHarness {
        let recognized = startedAndRecognized()
        let run = recognized.runID
        return recognized.send(
            .translation(.started(run, TranslationFixture.plan)),
            .translation(.arrived(run, TranslationFixture.placed(TranslationFixture.hello))),
            .translation(.arrived(run, TranslationFixture.placed(TranslationFixture.world))),
            .translation(.finished(run))
        )
    }

    /// 只到达第一块就失败
    func partiallyTranslated() -> SessionHarness {
        let recognized = startedAndRecognized()
        let run = recognized.runID
        return recognized.send(
            .translation(.started(run, TranslationFixture.plan)),
            .translation(.arrived(run, TranslationFixture.placed(TranslationFixture.hello))),
            .translation(.failed(run, TranslationFixture.failure))
        )
    }

    /// 在「World wide」块上画两笔短马赛克（各盖住约 15%，合计约 30%），再回到指针
    func drawingSmallMosaics() -> SessionHarness {
        send(.command(.selectTool(.mosaic)))
            .drag(from: CGPoint(x: 240, y: 220), to: CGPoint(x: 261, y: 220))
            .drag(from: CGPoint(x: 400, y: 220), to: CGPoint(x: 421, y: 220))
            .send(.command(.selectTool(.pointer)))
    }

    /// 各马赛克标注盖住 block 的面积比例
    func mosaicCoverage(of block: TextBlock) -> [CGFloat] {
        let frame = block.frame
        return session.document.annotations.filter { $0.tool == .mosaic }.map { mosaic in
            let overlap = mosaic.bounds.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height / (frame.width * frame.height)
        }
    }

    /// 最后一次事件里的翻译副作用
    var translationEffects: [TranslationEffect] {
        effects.compactMap {
            if case .translation(let effect) = $0 { return effect }
            return nil
        }
    }
}
