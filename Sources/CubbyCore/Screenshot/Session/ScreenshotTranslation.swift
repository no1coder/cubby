import CoreGraphics

// 截图翻译在会话里的状态（docs/TRANSLATION-DESIGN.md §2，契约扩展）。
//
// 译文层放在文档旁边而不是文档里：文档的撤销快照只记「当前是哪一次翻译」（`TranslationRunID`），
// 译文内容（块、排好版的译文、阶段）在会话的 `translationRuns` 里按 id 原地更新。
// 这样流式到达的块不占撤销步，翻译期间照常画的标注也不会被后到的译文覆盖掉；
// 「应用翻译」「换语言重译」各是一步撤销；Esc 取消时从历史里抹掉那一步（`purgingTranslation`）。

/// 一次翻译运行的标识（会话内递增）
public struct TranslationRunID: Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// 翻译条上显示的引擎：名称与简称，以及文字是否会离开本机（云端引擎带云图标）
public struct TranslationEngineBadge: Equatable, Sendable {
    /// 完整名称（「api.siliconflow.cn · Qwen/Qwen2.5-72B-Instruct」）：悬停说明、读屏与失败提示用
    public let name: String
    /// 徽标上显示的简称（「siliconflow」）；未给出时与 name 相同
    public let shortName: String
    public let sendsTextOffDevice: Bool

    public init(name: String, shortName: String? = nil, sendsTextOffDevice: Bool) {
        self.name = name
        self.shortName = shortName ?? name
        self.sendsTextOffDevice = sendsTextOffDevice
    }
}

/// 一次运行的阶段
public enum TranslationStatus: Equatable, Sendable {
    /// 正在识别文字
    case recognizing
    /// 正在翻译；total 为 0 表示还在准备（过滤、语言判断、创建引擎）
    case translating(done: Int, total: Int)
    /// 全部完成
    case ready
    /// 部分块没有译文（引擎中途失败或没有返回）；failure 为中途失败的原因
    case partial(missing: Int, failure: TranslationFailure?)
    /// 一块也没译成
    case failed(TranslationFailure)
    /// 没有可翻译的文字
    case noText
    /// 自动模式下原文已是首选语言：需要用户在语言选单里选目标语言
    case needsTargetLanguage

    /// 识别或翻译进行中
    public var isBusy: Bool {
        switch self {
        case .recognizing, .translating: true
        default: false
        }
    }
}

/// 流水线开始翻译时的计划：送去翻译的块、语言、引擎
public struct TranslationPlan: Equatable, Sendable {
    public let blockIDs: [Int]
    public let languages: TranslationLanguages
    public let engine: TranslationEngineBadge

    public init(blockIDs: [Int], languages: TranslationLanguages, engine: TranslationEngineBadge) {
        self.blockIDs = blockIDs
        self.languages = languages
        self.engine = engine
    }
}

/// 一次翻译运行：识别出的块、送去翻译的块、已排好版的译文与阶段（不可变值）
public struct TranslationRun: Equatable, Sendable {
    public let id: TranslationRunID
    /// 应用这次翻译之前生效的运行（换语言重译、选区变化后重译时为上一次；Esc 取消时回到它）
    public let parent: TranslationRunID?
    /// 识别的区域（当时的选区，全局点）：新选区超出它时提示「选区已变化」
    public let area: CGRect
    /// 识别区域所在的屏幕
    public let screenID: UInt32
    public let status: TranslationStatus
    /// 语言对；识别完成前可能只有用户选定的目标语言，或为 nil
    public let languages: TranslationLanguages?
    public let engine: TranslationEngineBadge?
    /// 识别出的全部块（按 id 顺序）
    public let blocks: [TextBlock]
    /// 送去翻译的块 id（按 id 顺序）
    public let candidateIDs: [Int]
    /// 已排好版的译文，按块 id
    let placed: [Int: TranslatedBlock]
    /// 本次运行已到达的块（换语言时从上一次继承、尚未被替换的译文不在其中）
    let arrivedIDs: Set<Int>
    /// 正在重试部分失败时缺失的块：此时按 Esc 只停掉重试、回到部分完成，而不是抹掉整次翻译
    let isRetrying: Bool

    /// 已排好版的译文（按块 id 顺序）
    public var translatedBlocks: [TranslatedBlock] {
        placed.keys.sorted().compactMap { placed[$0] }
    }

    /// 某块的译文
    public func translatedBlock(id: Int) -> TranslatedBlock? {
        placed[id]
    }

    /// 送去翻译、还在等译文的块（流光显示在这些块上）
    public var pendingBlocks: [TextBlock] {
        guard status.isBusy else { return [] }
        let pending = Set(candidateIDs).subtracting(arrivedIDs)
        return blocks.filter { pending.contains($0.id) }
    }

    /// 已完成（全部或部分）且至少有一块译文：可以切换原文 / 译文、卷帘对比、按住空格看原文
    public var hasResult: Bool {
        switch status {
        case .ready, .partial: !placed.isEmpty
        default: false
        }
    }

    /// 失败、无文字、待选语言：翻译条只显示提示，Esc 关闭这次翻译
    var isDismissible: Bool {
        switch status {
        case .failed, .noText, .needsTargetLanguage: true
        default: false
        }
    }

    /// 新的一次运行：从识别开始
    static func recognizing(
        id: TranslationRunID, parent: TranslationRunID?, area: CGRect, screenID: UInt32,
        languages: TranslationLanguages?
    ) -> TranslationRun {
        TranslationRun(
            id: id, parent: parent, area: area, screenID: screenID, status: .recognizing, languages: languages,
            engine: nil, blocks: [], candidateIDs: [], placed: [:], arrivedIDs: [], isRetrying: false)
    }

    /// 返回应用了 change 的新值；self 不变
    func updating(_ change: (inout Draft) -> Void) -> TranslationRun {
        var draft = Draft(self)
        change(&draft)
        return TranslationRun(
            id: id, parent: draft.parent, area: draft.area, screenID: draft.screenID, status: draft.status,
            languages: draft.languages, engine: draft.engine, blocks: draft.blocks,
            candidateIDs: draft.candidateIDs, placed: draft.placed, arrivedIDs: draft.arrivedIDs,
            isRetrying: draft.isRetrying)
    }

    /// 可变镜像：只在构造新值的闭包内使用
    struct Draft {
        var parent: TranslationRunID?
        var area: CGRect
        var screenID: UInt32
        var status: TranslationStatus
        var languages: TranslationLanguages?
        var engine: TranslationEngineBadge?
        var blocks: [TextBlock]
        var candidateIDs: [Int]
        var placed: [Int: TranslatedBlock]
        var arrivedIDs: Set<Int>
        var isRetrying: Bool

        init(_ run: TranslationRun) {
            parent = run.parent
            area = run.area
            screenID = run.screenID
            status = run.status
            languages = run.languages
            engine = run.engine
            blocks = run.blocks
            candidateIDs = run.candidateIDs
            placed = run.placed
            arrivedIDs = run.arrivedIDs
            isRetrying = run.isRetrying
        }
    }
}

/// 译文层当前怎么显示（只影响查看；导出由「原文 | 译文」开关决定）
public enum TranslationDisplay: Equatable, Sendable {
    /// 显示原图（开关在原文、按住空格、没有译文）
    case hidden
    /// 整层译文
    case full
    /// 卷帘对比：分隔线 x（全局点）左侧原文、右侧译文
    case split(x: CGFloat)
}

/// 截图翻译的事件（契约扩展）：前半是用户操作，后半是流水线回报
public enum TranslationEvent: Equatable, Sendable {
    /// ⇧⌘T / 工具栏「翻译」：开始翻译；已有译文时切换原文 / 译文；失败时重试
    case start
    /// 翻译条「重试」：部分失败只重发缺失的块，其余情况整体重试
    case retry
    /// 翻译条「选区已变化 · 重新翻译」：按当前选区重新识别并翻译（一步撤销）
    case retranslateSelection
    /// 语言选单选定目标语言（BCP-47）：沿用已识别的块重译（不重新识别）
    case changeTarget(String)
    /// 「原文 | 译文」开关（决定导出版本）
    case showTranslation(Bool)
    /// 卷帘对比开关
    case setWipe(Bool)
    /// 拖动卷帘分隔线到 x（全局点）
    case moveWipe(CGFloat)

    /// 识别完成（空数组 = 没有文字）
    case recognized(TranslationRunID, [TextBlock])
    /// 开始翻译（引擎已创建）
    case started(TranslationRunID, TranslationPlan)
    /// 一块译文到达并已排版
    case arrived(TranslationRunID, TranslatedBlock)
    /// 引擎的流正常结束
    case finished(TranslationRunID)
    /// 失败（未配置、网络等）
    case failed(TranslationRunID, TranslationFailure)
    /// 识别出的块都不需要翻译（数字、代码、已是目标语言、被遮挡）
    case nothingToTranslate(TranslationRunID)
    /// 自动模式下找不到与原文不同的目标语言
    case needsTargetLanguage(TranslationRunID)

    /// 流水线回报（不是用户操作）：不解除「待确认放弃」，编辑文字时也不提交文字；
    /// 覆盖层暂停（存储对话框）期间也要照常交给会话，否则进行中的运行会一直停在「进行中」
    public var isPipelineReport: Bool {
        switch self {
        case .start, .retry, .retranslateSelection, .changeTarget, .showTranslation, .setWipe, .moveWipe: false
        case .recognized, .started, .arrived, .finished, .failed, .nothingToTranslate, .needsTargetLanguage: true
        }
    }
}

/// reducer 要求 App 层流水线执行的动作（契约扩展）
public enum TranslationEffect: Equatable, Sendable {
    /// 识别选区里的文字，再翻译（hidden = 马赛克覆盖的区域，这些块不发送）
    case recognize(TranslationRunID, selection: CGRect, screenID: UInt32, hidden: [CGRect])
    /// 沿用已识别的块：重新过滤、判断语言后翻译（换语言、整体重试）
    case translate(TranslationRunID, blocks: [TextBlock], screenID: UInt32, hidden: [CGRect])
    /// 只重发这些块，沿用语言（部分失败后的重试）；hidden 同上，发送前再按它过滤一次
    case retry(
        TranslationRunID, blocks: [TextBlock], screenID: UInt32, languages: TranslationLanguages, hidden: [CGRect])
    /// 取消进行中的识别 / 翻译
    case cancel
}

extension ScreenshotEvent {
    /// 截图翻译流水线的回报（契约扩展）：覆盖层暂停期间也要交给会话
    public var isTranslationReport: Bool {
        if case .translation(let event) = self {
            return event.isPipelineReport
        }
        return false
    }
}
