import CubbyCore
import Foundation

// 翻译卡、⌥↩ 行内任务与按住 ⌥ 预览的状态（值类型，docs/CLIP-TRANSLATION-DESIGN.md §1.3）。
// 控制器整体替换这些值，视图只读。

/// 翻译卡的三种显示方式（← / → 切换）
enum TranslationViewMode: Int, CaseIterable, Sendable {
    case translation
    case sideBySide
    case original
}

/// 翻译卡的阶段
enum TranslationCardPhase: Equatable, Sendable {
    /// 大模型：卡片跟随选中项时先在这一条上停留片刻再发送
    case holding
    /// 已发出、还没有任何分段到达（图片：正在本机识别文字）
    case waiting
    /// 分段 / 图片块陆续到达
    case streaming
    case done
    case failed(TranslationFailure)
    /// 云端引擎且疑似含密钥：必须点「仍然翻译」
    case needsSecretConfirmation
    /// 原文已是目标语言（参数为 BCP-47）
    case alreadyTarget(String)
    case unsupported(ClipTranslationUnsupportedReason)
    /// esc 取消：已到达的部分已丢弃
    case cancelled

    /// 正在进行（esc 先取消它）
    var isWorking: Bool {
        switch self {
        case .holding, .waiting, .streaming: true
        default: false
        }
    }
}

/// 一块图片译文：版面 + 原文（悬停气泡）
struct TranslatedImageBlock: Equatable, Sendable {
    let block: TranslatedBlock
    let original: String
}

/// 一次翻译累积的内容：由事件流逐个折叠而来
struct TranslationContent: Equatable, Sendable {
    let segments: [ClipTranslationSegment]
    let arrived: [Int: AttributedString]
    let imageBlocks: [TranslatedImageBlock]
    let result: ClipTranslationResult?
    /// 已收到 started（文本分段已知）
    let hasStarted: Bool

    static let empty = TranslationContent(segments: [], arrived: [:], imageBlocks: [], result: nil, hasStarted: false)

    /// 需要翻译的段数（代码行、URL、空行不翻译）
    var translatableCount: Int {
        segments.lazy.filter(\.isTranslatable).count
    }

    /// 已到达的段数（图片为已到达的块数）
    var arrivedCount: Int {
        imageBlocks.isEmpty ? arrived.count : imageBlocks.count
    }

    /// 第 index 段显示用的译文：不翻译的段用原文；未到达为 nil
    func translation(at index: Int) -> AttributedString? {
        if let arrived = arrived[index] { return arrived }
        guard segments.indices.contains(index), !segments[index].isTranslatable else { return nil }
        return segments[index].original
    }

    /// 已显示部分的纯文本（按住 ⌥ 预览、流式统计）：按段落顺序、只含已到达的段
    var shownPlainText: String {
        if let result { return result.plainText }
        return segments.indices
            .compactMap { translation(at: $0).map { String($0.characters) } }
            .joined(separator: "\n")
    }

    func applying(_ event: ClipTranslationEvent) -> TranslationContent {
        switch event {
        case .started(let segments):
            TranslationContent(
                segments: segments, arrived: [:], imageBlocks: [], result: nil, hasStarted: true)
        case .segment(let index, let translation):
            TranslationContent(
                segments: segments, arrived: arrived.merging([index: translation]) { $1 }, imageBlocks: imageBlocks,
                result: result, hasStarted: hasStarted)
        case .imageBlock(let block, let original):
            TranslationContent(
                segments: segments, arrived: arrived,
                imageBlocks: imageBlocks.filter { $0.block.blockID != block.blockID }
                    + [TranslatedImageBlock(block: block, original: original)],
                result: result, hasStarted: true)
        case .finished(let result):
            TranslationContent(
                segments: segments, arrived: arrived, imageBlocks: imageBlocks, result: result, hasStarted: true)
        }
    }
}

/// 粘贴译文的方式
enum TranslationPasteStyle: Equatable, Sendable {
    /// ↩：富文本条目写 RTF / HTML + 纯文本（按「默认粘贴格式」设置），图片写译后 PNG
    case standard
    /// ⇧↩：只写纯文本
    case plainText
}

/// 翻译卡
struct TranslationCard: Equatable, Sendable {
    let itemID: UUID
    let isImage: Bool
    var plan: ClipTranslationPlan?
    var phase: TranslationCardPhase
    var content: TranslationContent
    var mode: TranslationViewMode
    /// ⇄ 已对调：显示的是把译文译回源语言的结果（不写缓存）
    var isReversed = false
    /// 按住 ⌥ 看原文
    var isPeeking = false
    /// 图片卷帘位置（0…1，左侧原文、右侧译文）
    var wipe = 0.5
    /// 点过 / 拖过分隔线：← / → 改为微调卷帘
    var isDividerFocused = false
    /// 从空格预览切过来：关闭后回到预览
    var openedFromPreview: Bool
    /// 用户在语言选单里选定的目标语言（卡片跟随选中项时沿用）；nil = 自动
    var chosenTarget: String?
    /// 用户点「仍然翻译」时的计划：只对同一次发送有效（换语言、引擎或主机后失效，换条目时随卡片重建）
    var confirmedPlan: ClipTranslationPlan?
    /// 翻译进行中按了 ↩：完成后按此方式粘贴
    var pendingPaste: TranslationPasteStyle?
    var startedAt: ContinuousClock.Instant?
    var elapsed: Duration?
    /// 每开始一轮翻译递增：视图据此重置流式显现
    var runID = 0

    init(itemID: UUID, isImage: Bool, mode: TranslationViewMode, openedFromPreview: Bool, chosenTarget: String?) {
        self.itemID = itemID
        self.isImage = isImage
        self.phase = .waiting
        self.content = .empty
        self.mode = mode
        self.openedFromPreview = openedFromPreview
        self.chosenTarget = chosenTarget
    }

    /// 显示方向：对调后源 / 目标互换
    var displayedLanguages: (source: String?, target: String?) {
        guard let plan else { return (nil, chosenTarget) }
        if isReversed { return (plan.languages.target, plan.detectedSource) }
        return (plan.detectedSource, plan.languages.target)
    }

    /// 能否 ⇄ 对调：文本条目、源语言已知，且正向译文已完成（或已处于对调状态）。
    /// 对调会把译文发给引擎且无法逐条确认：云端引擎遇到疑似密钥时一律不可用
    var canSwap: Bool {
        guard !isImage, let plan, plan.detectedSource != nil, !isSwapBlockedBySecret else { return false }
        return isReversed || phase == .done
    }

    /// 云端引擎且疑似含密钥：⇄ 对调不可用（翻译服务同样会拒绝）
    var isSwapBlockedBySecret: Bool {
        plan.map { $0.sendsTextOffDevice && $0.needsSecretConfirmation } ?? false
    }

    /// 有可复制 / 粘贴的结果
    var result: ClipTranslationResult? {
        phase == .done ? content.result : nil
    }
}

/// 翻译卡底栏的短暂提示（约 1.6 s）
struct TranslationFlash: Equatable, Identifiable, Sendable {
    let id = UUID()
    let message: String
    let isWarning: Bool
}

/// ⌥↩ 行内任务的问题（卡片行内显示原因与操作）
enum InlineTranslationIssue: Equatable, Sendable {
    case failure(TranslationFailure)
    /// 超过 ⌥↩ 的总时限
    case timedOut
    /// 云端引擎且疑似含密钥：参数为引擎名
    case needsSecretConfirmation(String)
    /// 原文已是目标语言（BCP-47）
    case alreadyTarget(String)
    /// 译文写入剪贴板失败
    case pasteFailed
    /// 没有可翻译的文字（例如图片里没有文字）
    case nothingToTranslate
}

/// ⌥↩ 翻译后粘贴的行内任务
struct InlineTranslation: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case running
        case failed(InlineTranslationIssue)
    }

    let itemID: UUID
    var plan: ClipTranslationPlan?
    var phase: Phase
    var content: TranslationContent
    /// 用户点「仍然翻译」时的计划（只对同一次发送有效）
    var confirmedPlan: ClipTranslationPlan?

    var isRunning: Bool {
        phase == .running
    }
}

/// 列表中按住 ⌥ 的译文预览
struct TranslationPeek: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// 云端引擎：预览已显示，停留满 0.6 s（按住 ⌥ 的 300 ms 计入）才发送
        case holding
        case waiting
        case streaming
        case done
        /// 无法预览（不支持、未配置、疑似密钥等），参数为说明
        case note(String)
    }

    let itemID: UUID
    var plan: ClipTranslationPlan?
    var phase: Phase
    var content: TranslationContent
    /// 预览进行中按了 ↩：完成后粘贴
    var pasteOnDone = false

    /// 还在等译文（停留、已发出、陆续到达）
    var isStreaming: Bool {
        phase == .holding || phase == .waiting || phase == .streaming
    }
}

/// 粘贴 / 复制译文的请求（由面板控制器写剪贴板并投递）
struct TranslationPasteRequest: Sendable {
    /// 请求来自哪里：写剪贴板失败时在那里提示
    enum Origin: Sendable {
        case card
        case inline
        case peek
        case menu
    }

    /// 原条目：粘贴后提升到最前
    let item: ClipItem
    let result: ClipTranslationResult
    let style: TranslationPasteStyle
    let origin: Origin
}

extension ClipTranslationResult {
    /// 没有任何可用的译文（例如图片里没有可翻译的文字）：不粘贴、不复制
    var isEmpty: Bool {
        imageURL == nil && plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 交互时长（原型数值，A10）；E2E 可换成更短的值
struct TranslationTimings: Sendable {
    /// 大模型：卡片跟随选中项时在一条上停留多久才发送（A3）
    var cloudDwell: Duration = TranslationSendDwell.cloud
    /// 列表中按住 ⌥ 多久开始预览（A4）
    var optionHold: Duration = .milliseconds(300)
    /// ⌥↩ 的总时限（§4）
    var inlineCap: Duration = .seconds(30)
    /// 卡片底栏提示
    var flash: Duration = .milliseconds(1600)
    /// 图片块悬停多久显示原文气泡
    var bubbleDelay: Duration = .milliseconds(400)
}
