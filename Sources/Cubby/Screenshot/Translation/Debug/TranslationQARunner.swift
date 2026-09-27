#if DEBUG
import CoreGraphics
import CubbyCore
import Foundation

/// 对一个语料场景跑真实流水线：识别 → 分块 → 候选 → 按真值对上预置译文 → 版面 → 绘制
enum TranslationQARunner {
    /// 一块的记录（报告用）
    struct BlockRecord {
        let block: TextBlock
        let skip: TranslationCandidates.SkipReason?
        let translation: String?
        let placed: TranslatedBlock?
        let note: String?
    }

    struct SceneResult {
        let scene: TranslationQAScene
        let before: CGImage
        let after: CGImage
        let records: [BlockRecord]
        /// 预期翻译但没有被任何块对上的真值文字
        let missed: [String]
        let recognitionMilliseconds: Double
        let placeMilliseconds: [Double]
        let paintMilliseconds: Double
    }

    static func run(_ scene: TranslationQAScene) async throws -> SceneResult? {
        guard let rendering = TranslationQARenderer.render(scene) else { return nil }
        let scale = scene.scale ?? 2
        let screen = CaptureScreen(
            id: 1, frame: CGRect(x: 0, y: 0, width: scene.width, height: scene.height), scale: scale)
        let frame = FrozenFrame(screen: screen, image: rendering.image)
        let clock = ContinuousClock()
        let start = clock.now
        let blocks = try await VisionTranslationRecognizer().blocks(in: frame, selection: screen.frame)
        let recognition = milliseconds(clock.now - start)
        let matches = match(blocks, frames: rendering.textFrames)
        var timings: [Double] = []
        let records = blocks.map { block in
            record(block, scene: scene, match: matches[block.id], frame: frame, timings: &timings)
        }
        let placed = records.compactMap(\.placed)
        let paintStart = clock.now
        let after = paint(placed, over: rendering.image, screen: screen)
        let paint = milliseconds(clock.now - paintStart)
        let matched = Set(matches.values.filter(\.isPrimary).map(\.textIndex))
        let missed = scene.texts.indices.filter { scene.texts[$0].translation != nil && !matched.contains($0) }
        return SceneResult(
            scene: scene, before: rendering.image, after: after ?? rendering.image, records: records,
            missed: missed.map { scene.texts[$0].text }, recognitionMilliseconds: recognition,
            placeMilliseconds: timings, paintMilliseconds: paint)
    }

    // MARK: - 对上真值

    struct Match {
        let textIndex: Int
        /// 同一段真值被拆成多块时，只有重叠最大的一块拿到译文
        let isPrimary: Bool
    }

    /// 每块对上重叠面积最大的真值文字
    private static func match(_ blocks: [TextBlock], frames: [CGRect]) -> [Int: Match] {
        let best = blocks.compactMap { block -> (id: Int, index: Int, area: CGFloat)? in
            let scored = frames.enumerated().map { index, frame in
                (index, area(frame.insetBy(dx: -2, dy: -2).intersection(block.frame)))
            }
            guard let top = scored.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return nil }
            return (block.id, top.0, top.1)
        }
        var result: [Int: Match] = [:]
        for entry in best {
            let rivals = best.filter { $0.index == entry.index }
            let primary = rivals.max { $0.area < $1.area }?.id == entry.id
            result[entry.id] = Match(textIndex: entry.index, isPrimary: primary)
        }
        return result
    }

    private static func record(
        _ block: TextBlock, scene: TranslationQAScene, match: Match?, frame: FrozenFrame, timings: inout [Double]
    ) -> BlockRecord {
        let skip = TranslationCandidates.skipReason(for: block, target: scene.target, hidden: [])
        guard let match else {
            return BlockRecord(block: block, skip: skip, translation: nil, placed: nil, note: "no ground truth")
        }
        let expected = scene.texts[match.textIndex].translation
        if let skip {
            let note = expected == nil ? nil : "skipped (\(skip.rawValue)) but a translation was expected"
            return BlockRecord(block: block, skip: skip, translation: nil, placed: nil, note: note)
        }
        guard let expected else {
            return BlockRecord(block: block, skip: nil, translation: nil, placed: nil, note: "expected to be skipped")
        }
        guard match.isPrimary else {
            return BlockRecord(block: block, skip: nil, translation: nil, placed: nil, note: "split from another block")
        }
        let clock = ContinuousClock()
        let start = clock.now
        let placed = TranslationPlacer.place(block, translation: expected, in: frame, within: frame.screen.frame)
        timings.append(milliseconds(clock.now - start))
        return BlockRecord(block: block, skip: nil, translation: expected, placed: placed, note: nil)
    }

    // MARK: - 绘制

    /// 原图 + 译文层（与导出相同的 RenderEnvironment 约定）
    static func paint(_ blocks: [TranslatedBlock], over image: CGImage, screen: CaptureScreen) -> CGImage? {
        guard let context = TranslationQAImages.context(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let environment = RenderEnvironment(
            origin: screen.frame.origin, scale: screen.scale,
            targetPixelSize: CGSize(width: image.width, height: image.height), pixelatedFrame: nil,
            frameOrigin: screen.frame.origin)
        TranslationPainter.draw(blocks, in: context, environment: environment)
        return context.makeImage()
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
#endif
