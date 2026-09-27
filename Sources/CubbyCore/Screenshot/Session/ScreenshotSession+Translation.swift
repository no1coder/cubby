import CoreGraphics

/// 截图翻译的派生属性：译文层怎么显示、导出哪些块、悬停的块、复制的文字、选区是否已变化
extension ScreenshotSession {
    /// 卷帘分隔线 ← / → 微调：选区宽度的 1/50（⇧ 为 1/10）
    public static let wipeSmallStep: CGFloat = 1.0 / 50
    static let wipeLargeStep: CGFloat = 1.0 / 10

    /// 当前文档应用的翻译运行（撤销掉之后为 nil）
    public var translation: TranslationRun? {
        document.translation.flatMap { translationRuns[$0] }
    }

    /// 识别或翻译进行中
    public var isTranslating: Bool {
        activeTranslation != nil
    }

    /// 工具栏的撤销 / 重做：翻译进行中不可用（Esc 才是取消翻译）
    public var canUndo: Bool {
        document.canUndo && !isTranslating
    }

    public var canRedo: Bool {
        document.canRedo && !isTranslating
    }

    /// 有标注或译文：Esc 需按两次、会话中再按快捷键不取消（译文同样是用户的劳动，可能还花了钱）
    public var hasDiscardableContent: Bool {
        hasAnnotations || document.translation != nil
    }

    /// 按住空格临时看原文：有选区的两个阶段、翻译已完成时（编辑文字时空格是输入，不经过这里）
    public var isPeekingOriginal: Bool {
        (phase == .adjusting || phase == .annotating) && modifiers.contains(.space)
            && translation?.hasResult == true
    }

    /// 译文层当前怎么显示：进行中总是显示已到达的块；按住空格看原文；卷帘对比；否则按「原文 | 译文」开关
    public var translationDisplay: TranslationDisplay {
        guard let run = translation, !run.placed.isEmpty else { return .hidden }
        if run.status.isBusy {
            return .full
        }
        if isPeekingOriginal {
            return .hidden
        }
        if let x = wipeLineX {
            return .split(x: x)
        }
        return showsTranslation ? .full : .hidden
    }

    /// 导出（复制 / 存储 / 贴图）的译文块：只由「原文 | 译文」开关决定，按住空格与卷帘不影响
    public var exportedTranslation: [TranslatedBlock] {
        showsTranslation ? translation?.translatedBlocks ?? [] : []
    }

    /// 悬停看原文：指针工具、没有按下鼠标、光标停在一块显示中的译文上（标注优先）
    public var hoveredTranslationBlockID: Int? {
        guard phase == .adjusting, !isPointerBusy, let run = translation else { return nil }
        switch translationDisplay {
        case .hidden: return nil
        case .split(let x) where cursor.x < x: return nil
        case .full, .split: break
        }
        guard document.topmost(at: cursor, tolerance: ScreenshotReducer.annotationHitTolerance) == nil else {
            return nil
        }
        return run.translatedBlocks.last { $0.eraseFrame.contains(cursor) }?.blockID
    }

    /// 「复制译文」与 ⌘T 的文字：按块 id（阅读顺序）逐块一行，没有译文的块用原文；
    /// 马赛克遮住的块（与「不发送」同一口径：`TranslationCandidates.isHidden`，各马赛克合计盖住 ≥ 20%）
    /// 与选区外的块不复制——被遮住的文字不该从剪贴板里再冒出来，即使翻译时它还没被遮住。没有译文时为 nil
    public var translatedText: String? {
        guard let run = translation, !run.placed.isEmpty else { return nil }
        let hidden = translationHiddenRegions
        let lines = run.blocks.filter { block in
            (selection.map(block.frame.intersects) ?? true) && !TranslationCandidates.isHidden(block.frame, by: hidden)
        }.map { run.placed[$0.id]?.text ?? $0.text }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 选区已超出识别过的区域（翻译条提示「选区已变化 · 重新翻译」）
    public var isTranslationStale: Bool {
        guard let run = translation, !run.status.isBusy, let selection else { return false }
        return !run.area.insetBy(dx: -Self.staleTolerance, dy: -Self.staleTolerance).contains(selection)
    }

    /// 卷帘分隔线的实际位置：打开且有译文结果时，夹在选区内；默认选区水平中点
    var wipeLineX: CGFloat? {
        guard isWipeEnabled, translation?.hasResult == true, let selection else { return nil }
        return Self.clampedWipe(wipePosition ?? selection.midX, in: selection)
    }

    /// 马赛克标注覆盖的区域（全局点）：这里的文字不发送、不复制
    public var translationHiddenRegions: [CGRect] {
        document.annotations.filter { $0.tool == .mosaic }.map(\.bounds).filter { !$0.isNull }
    }

    // MARK: - 内部

    /// 返回存入（或替换）了 run 的新会话；self 不变
    func storing(_ run: TranslationRun) -> ScreenshotSession {
        updating { $0.translationRuns = translationRuns.merging([run.id: run]) { $1 } }
    }

    /// 选区吸附到像素网格后的浮点误差
    private static let staleTolerance: CGFloat = 0.01

    static func clampedWipe(_ x: CGFloat, in selection: CGRect) -> CGFloat {
        min(max(x, selection.minX), selection.maxX)
    }
}
