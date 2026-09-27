import CoreGraphics
import Foundation

/// 原文块 + 译文 + 冻结帧像素 → 版面（§3.5）。纯函数，可在任意线程逐块调用；只读取块周围的小块像素
public enum TranslationPlacer {
    /// 衬底：外扩 6 pt，背景模糊半径 10 pt
    static let plateOutset: CGFloat = 6
    static let plateBlurRadius: CGFloat = 10
    /// 单行块推断对齐时左右同色空白的比较范围：max(24 em, 块宽)。范围太小时，左对齐的短标签两侧都「空到头」会被误判为居中
    static let alignmentReach: CGFloat = 24
    /// 按钮这类短标签的词数上限（§3.5），以及「左右都很窄」的上限（em）
    static let shortLabelWords = 3
    static let tightLabelReach: CGFloat = 3
    /// 单行块需要折行时的行距 / 字号
    static let wrappedPitchRatio: CGFloat = 1.3
    /// 左右空白相差不超过 max(3 pt, 25%) 视为对称 → 居中
    static let symmetryTolerance: CGFloat = 3
    static let symmetryRatio: CGFloat = 0.25
    /// 右侧空白 ≤ 2 em 且不到左侧一半 → 右对齐
    static let trailingReach: CGFloat = 2

    typealias Style = TranslationTypesetter.Style

    public static func place(_ block: TextBlock, translation: String, in frame: FrozenFrame) -> TranslatedBlock {
        place(block, translation: translation, in: frame, within: nil)
    }

    /// limit：扩展不越过的范围（通常是选区，全局点）；nil 时只受帧范围限制
    public static func place(_ block: TextBlock, translation: String, in frame: FrozenFrame, within limit: CGRect?)
        -> TranslatedBlock
    {
        guard !block.lines.isEmpty else { return empty(block, translation: translation) }
        let recognized = BlockGeometry(block)
        let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = TranslationLanguageGuess.language(of: text)
        let widest = Style(fontSize: recognized.fontSize, isBold: true, language: language)
        let appearance = BlockAppearance.sample(
            recognized, frame: frame, reach: reach(recognized, text: text, style: widest), limit: limit)
        let geometry = appearance.geometry
        let style = Style(fontSize: appearance.source.fontSize, isBold: appearance.isBold, language: language)
        let alignment =
            geometry.isMultiLine || block.alignment != .leading
            ? block.alignment : singleLineAlignment(geometry, appearance)
        let fit = TranslationFitter.fit(request(text, style: style, geometry, appearance, alignment))
        let lines = text.isEmpty ? [] : position(fit, geometry, appearance, alignment, screen: frame.screen)
        let textFrame =
            lines.isEmpty ? geometry.frame : FramePixelGrid.outward(textBounds(lines, style: fit.style), frame.screen)
        let backdrop = Backdrop(geometry: geometry, appearance: appearance, textFrame: textFrame, frame: frame)
        return TranslatedBlock(
            blockID: block.id, eraseFrame: backdrop.rects.reduce(textFrame) { $0.union($1) },
            backdrop: backdrop.kind, text: text, textFrame: textFrame, style: fit.style,
            textColor: appearance.textColor, alignment: alignment, eraseRects: backdrop.rects,
            plateImage: backdrop.image, lines: lines)
    }

    /// 没有行的块（契约上允许构造）：不抹除、不排字，只带回译文与块外框
    private static func empty(_ block: TextBlock, translation: String) -> TranslatedBlock {
        let frame = block.frame.isNull ? CGRect.zero : block.frame
        return TranslatedBlock(
            blockID: block.id, eraseFrame: frame, backdrop: .solid(.white),
            text: translation.trimmingCharacters(in: .whitespacesAndNewlines), textFrame: frame,
            style: Style(fontSize: BlockGeometry.minimumFontSize, isBold: false, language: nil), textColor: .black,
            alignment: block.alignment, eraseRects: [], plateImage: nil, lines: [])
    }

    // MARK: - 对齐与放不下

    /// 单行块（分块时没有从同列推断出居中 / 右对齐时）：纯色背景上左右同色空白对称，且两侧都止于控件边框 / 容器边界
    /// （按钮、分段控件、标题栏、空状态），或是左右都很窄的短标签 → 居中；右侧紧贴、左侧空旷 → 右对齐（数值列）；
    /// 否则左对齐。两侧止于别的文字的对称空白（表格中间一列）不算居中
    static func singleLineAlignment(_ geometry: BlockGeometry, _ appearance: BlockAppearance) -> TextBlockAlignment {
        guard appearance.isSolid else { return .leading }
        let em = appearance.source.fontSize
        let reach = max(alignmentReach * em, geometry.frame.width)
        let left = min(appearance.freeLeft, reach)
        let right = min(appearance.freeRight, reach)
        let symmetric = abs(left - right) <= max(symmetryTolerance, symmetryRatio * max(left, right))
        // 空白一直延伸到比较范围之外（标题栏）等同于止于容器边界
        let enclosed = (appearance.leftAtEdge || left >= reach) && (appearance.rightAtEdge || right >= reach)
        let tight = wordCount(geometry.text) <= shortLabelWords && max(left, right) <= tightLabelReach * em
        if symmetric && (enclosed || tight) { return .center }
        if right < left / 2 && right <= trailingReach * em { return .trailing }
        return .leading
    }

    /// 词数：拉丁文字按空白分词；CJK 按两个字约一个词
    static func wordCount(_ text: String) -> Int {
        let ideographs = text.filter(TextScript.isCJK).count
        let latin = text.filter { !TextScript.isCJK($0) }.split(whereSeparator: \.isWhitespace).count
        return latin + (ideographs + 1) / 2
    }

    /// 需要扫描多远的同色空白：对齐推断的范围，以及放下译文所需的扩展（可用空白只取一半，故 × 2）
    private static func reach(_ geometry: BlockGeometry, text: String, style: Style) -> BlockAppearance.Reach {
        // 行框推算的字号往往偏小（见 InkMetrics），多扫 25%
        let em = geometry.fontSize * 1.25
        guard geometry.isMultiLine else {
            let width = TranslationTypesetter.width(of: text, style: style)
            let needed = max(0, width - geometry.frame.width)
            let horizontal = max(alignmentReach * em, geometry.frame.width, 2 * needed + em)
            let extraLines = (width / max(geometry.frame.width, 1)).rounded(.up) - 1
            return BlockAppearance.Reach(
                horizontal: horizontal, below: extraLines > 0 ? (2 * extraLines + 1) * wrappedPitchRatio * em : 0)
        }
        let lines = TranslationTypesetter.breakLines(text, style: style, width: geometry.frame.width).count
        let extra = CGFloat(max(0, lines - geometry.lineFrames.count)) * geometry.pitch
        return BlockAppearance.Reach(horizontal: 0, below: extra > 0 ? 2 * extra + geometry.pitch : 0)
    }

    /// 同色空白中可用于扩展的部分：挡住它的是别的内容时至少保留 max(margin, 空白的一半)（对方也可能向这边扩展）；
    /// 是控件边框 / 分隔线时只保留 max(3 pt, margin 的四分之一)
    static func usable(_ free: CGFloat, margin: CGFloat, atEdge: Bool) -> CGFloat {
        max(0, free - (atEdge ? max(3, margin / 4) : max(margin, free / 2)))
    }

    private static func request(
        _ text: String, style: Style, _ geometry: BlockGeometry, _ appearance: BlockAppearance,
        _ alignment: TextBlockAlignment
    ) -> TranslationFitter.Request {
        let em = appearance.source.fontSize
        let extraWidth: CGFloat =
            switch alignment {
            case .leading: usable(appearance.freeRight, margin: em, atEdge: appearance.rightAtEdge)
            case .trailing: usable(appearance.freeLeft, margin: em, atEdge: appearance.leftAtEdge)
            case .center:
                2
                    * min(
                        usable(appearance.freeLeft, margin: em, atEdge: appearance.leftAtEdge),
                        usable(appearance.freeRight, margin: em, atEdge: appearance.rightAtEdge))
            }
        let pitch = geometry.isMultiLine ? appearance.source.pitch : (wrappedPitchRatio * em).rounded()
        return TranslationFitter.Request(
            text: text, style: style, isMultiLine: geometry.isMultiLine, width: geometry.frame.width,
            height: geometry.frame.height, lineHeight: geometry.lineHeight, pitch: pitch,
            extraWidth: geometry.isMultiLine ? 0 : extraWidth,
            extraHeight: usable(appearance.freeBelow, margin: pitch / 2, atEdge: appearance.belowAtEdge))
    }

    // MARK: - 排版位置

    /// 各行起点：首行视觉中线对齐原文首行（墨迹量出），其后按（缩放后的）原文行距；
    /// 水平按原文的笔位边缘对齐（界面排版对齐的是笔位，不是墨迹）
    private static func position(
        _ fit: TranslationFitter.Result, _ geometry: BlockGeometry, _ appearance: BlockAppearance,
        _ alignment: TextBlockAlignment, screen: CaptureScreen
    ) -> [TranslatedLine] {
        let baseline =
            appearance.source.firstCenter
            + TranslationTypesetter.centerHeight(of: fit.lines.first ?? "", style: fit.style)
        let source = Style(fontSize: appearance.source.fontSize, isBold: appearance.isBold, language: nil)
        let pen = penEdges(geometry, style: source)
        return fit.lines.enumerated().map { index, text in
            let width = TranslationTypesetter.width(of: text, style: fit.style)
            let x: CGFloat =
                switch alignment {
                case .leading: pen.left
                case .trailing: pen.right - width
                case .center: (pen.left + pen.right - width) / 2
                }
            let origin = CGPoint(x: x, y: baseline + CGFloat(index) * fit.pitch)
            return TranslatedLine(text: text, origin: FramePixelGrid.rounded(origin, screen))
        }
    }

    /// 原文的笔位左右缘：各行墨迹边缘减去首 / 尾字符的字形边距（按系统字体估计），取各行的中位数
    static func penEdges(_ geometry: BlockGeometry, style: Style) -> (left: CGFloat, right: CGFloat) {
        let lines = zip(geometry.lineFrames, geometry.lineTexts)
        let lefts = lines.map { frame, text in
            frame.minX - TranslationTypesetter.bearings(of: text.first, style: style).left
        }
        let rights = lines.map { frame, text in
            frame.maxX + TranslationTypesetter.bearings(of: text.last, style: style).right
        }
        return (TranslationMath.median(lefts), TranslationMath.median(rights))
    }

    /// 各行排版框与字形外框的并集（全局点）
    static func textBounds(_ lines: [TranslatedLine], style: Style) -> CGRect {
        let ascent = TranslationTypesetter.ascent(style)
        let descent = TranslationTypesetter.descent(style)
        return lines.reduce(CGRect.null) { bounds, line in
            let width = TranslationTypesetter.width(of: line.text, style: style)
            let ink = TranslationTypesetter.inkBounds(of: line.text, style: style)
            let typographic = CGRect(
                x: line.origin.x, y: line.origin.y - ascent, width: width, height: ascent + descent)
            let glyphs = CGRect(
                x: line.origin.x + ink.minX, y: line.origin.y - ink.maxY, width: ink.width, height: ink.height)
            return bounds.union(typographic).union(glyphs)
        }
    }
}

/// 抹除方式：纯色 → 每行行框外扩 pad 填背景色；复杂 → 外扩 6 pt 的圆角衬底 + 模糊背景
private struct Backdrop {
    let kind: TranslationBackdrop
    let rects: [CGRect]
    let image: TranslationPlateImage?

    init(geometry: BlockGeometry, appearance: BlockAppearance, textFrame: CGRect, frame: FrozenFrame) {
        let screen = frame.screen
        if appearance.isSolid {
            kind = .solid(appearance.background)
            rects = geometry.lineFrames.map {
                FramePixelGrid.outward($0.insetBy(dx: -geometry.pad, dy: -geometry.pad), screen)
            }
            image = nil
        } else {
            let outset = TranslationPlacer.plateOutset
            let plate = FramePixelGrid.outward(
                geometry.frame.union(textFrame).insetBy(dx: -outset, dy: -outset), screen)
            kind = .plate(appearance.background)
            rects = [plate]
            let deinking = PlateBlur.Deinking(
                model: appearance.inkModel,
                lines: geometry.lineFrames.map { $0.insetBy(dx: -geometry.pad, dy: -geometry.pad) })
            image = PlateBlur.image(
                frame: frame, plate: plate, radius: TranslationPlacer.plateBlurRadius, deinking: deinking
            ).map(TranslationPlateImage.init)
        }
    }
}

/// 全局点与冻结帧像素网格的对齐
enum FramePixelGrid {
    /// 容忍浮点误差：离整数像素不到这么多时视为已对齐
    private static let epsilon: CGFloat = 0.001

    static func outward(_ rect: CGRect, _ screen: CaptureScreen) -> CGRect {
        let scale = screen.scale
        let origin = screen.frame.origin
        let minX = ((rect.minX - origin.x) * scale + epsilon).rounded(.down)
        let minY = ((rect.minY - origin.y) * scale + epsilon).rounded(.down)
        let maxX = ((rect.maxX - origin.x) * scale - epsilon).rounded(.up)
        let maxY = ((rect.maxY - origin.y) * scale - epsilon).rounded(.up)
        return CGRect(
            x: origin.x + minX / scale, y: origin.y + minY / scale, width: (maxX - minX) / scale,
            height: (maxY - minY) / scale)
    }

    static func rounded(_ point: CGPoint, _ screen: CaptureScreen) -> CGPoint {
        let scale = screen.scale
        let origin = screen.frame.origin
        return CGPoint(
            x: origin.x + ((point.x - origin.x) * scale).rounded() / scale,
            y: origin.y + ((point.y - origin.y) * scale).rounded() / scale)
    }
}
