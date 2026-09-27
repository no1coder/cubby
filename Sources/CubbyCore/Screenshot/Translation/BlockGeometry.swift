import CoreGraphics
import Foundation

/// 原文块的几何量（全局点）：中位行框高、抹除外扩、原文字号、行距与各行的视觉中线（§3.1 实测）
struct BlockGeometry: Equatable {
    /// 行框高 ≈ 字号 × k：拉丁文字 1.05，CJK 1.22
    static let latinBoxRatio: CGFloat = 1.05
    static let ideographicBoxRatio: CGFloat = 1.22
    /// 行框顶到基线的距离 / 字号
    static let latinAscentRatio: CGFloat = 0.77
    static let ideographicAscentRatio: CGFloat = 0.86
    /// 文字视觉中线在基线上方的高度 / 字号（拉丁取大写字母半高附近，CJK 取字面中心）
    static let latinCenterRatio: CGFloat = 0.35
    static let ideographicCenterRatio: CGFloat = 0.38
    /// 抹除外扩：max(2 pt, 0.1 × 中位行框高)
    static let minimumPad: CGFloat = 2
    static let padRatio: CGFloat = 0.1
    /// 字号下限（点）
    static let minimumFontSize: CGFloat = 1

    let frame: CGRect
    let text: String
    /// 从上到下
    let lineFrames: [CGRect]
    let lineTexts: [String]
    /// 中位行框高
    let lineHeight: CGFloat
    let pad: CGFloat
    /// 原文以汉字 / 假名 / 韩文为主
    let isIdeographic: Bool
    /// 按行框高推算的原文字号（点，取 0.5 的倍数）；墨迹量不到时的兜底
    let fontSize: CGFloat
    /// 相邻行顶的中位间距；单行块为行框高
    let pitch: CGFloat

    init(_ block: TextBlock) {
        self.init(lines: block.lines.sorted { $0.frame.minY < $1.frame.minY }, text: block.text)
    }

    private init(lines: [RecognizedLine], text: String) {
        let frames = lines.map(\.frame)
        let lineHeight = TranslationMath.median(frames.map(\.height))
        let ideographic = TextScript.isMostlyIdeographic(text)
        let ratio = ideographic ? Self.ideographicBoxRatio : Self.latinBoxRatio
        let gaps = zip(frames.dropFirst(), frames).map { $0.minY - $1.minY }
        self.frame = frames.dropFirst().reduce(frames.first ?? .null) { $0.union($1) }
        self.text = text
        self.lineFrames = frames
        self.lineTexts = lines.map(\.text)
        self.lineHeight = lineHeight
        self.pad = max(Self.minimumPad, Self.padRatio * lineHeight)
        self.isIdeographic = ideographic
        self.fontSize = max(Self.minimumFontSize, (lineHeight / ratio * 2).rounded() / 2)
        self.pitch = gaps.isEmpty ? lineHeight : TranslationMath.median(gaps)
    }

    var isMultiLine: Bool { lineFrames.count > 1 }

    /// 把各行换成按墨迹收紧的行框（nil 保留原行框）
    func tightened(to frames: [CGRect?]) -> BlockGeometry {
        let lines = zip(lineTexts, lineFrames).enumerated().map { index, line in
            RecognizedLine(text: line.0, frame: (index < frames.count ? frames[index] : nil) ?? line.1)
        }
        return BlockGeometry(lines: lines, text: text)
    }

    /// 原文第 index 行文字的视觉中线（全局 y）；没有这一行时取整块的竖直中点（没有行时为 0）
    func visualCenter(ofLine index: Int) -> CGFloat {
        guard lineFrames.indices.contains(index) else { return frame.isNull ? 0 : frame.midY }
        let ascent = isIdeographic ? Self.ideographicAscentRatio : Self.latinAscentRatio
        let center = isIdeographic ? Self.ideographicCenterRatio : Self.latinCenterRatio
        return lineFrames[index].minY + (ascent - center) * fontSize
    }
}
