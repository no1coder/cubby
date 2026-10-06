import CubbyCore
import Foundation

// 剪贴板条目翻译在 App 层的契约（docs/CLIP-TRANSLATION-DESIGN.md §10.1）。修改需经协调者同意。
// C2（面板交互）调用，C3（引擎、图片与设置）实现；面板 E2E 用桩。

/// 条目能否翻译（只看内容；与引擎有关的「疑似密钥需确认」见 ClipTranslationPlan）
enum ClipTranslationEligibility: Equatable, Sendable {
    case eligible
    case unsupported(ClipTranslationUnsupportedReason)
}

enum ClipTranslationUnsupportedReason: Equatable, Sendable {
    case link
    case file
    case color
    case code
    /// 没有可翻译的文字（空白、纯数字符号）
    case noText
    /// 原文超过长度上限
    case tooLong
    /// 图片过大（设计文档 §2.3）
    case imageTooLarge
    /// 系统版本不支持（macOS 26 以下）
    case unavailable
}

/// 一次翻译的计划：翻译卡头部与隐私行据此显示
struct ClipTranslationPlan: Equatable, Sendable {
    let languages: TranslationLanguages
    /// 检测到的源语言（BCP-47），用于「英语（自动检测）」；未知为 nil
    let detectedSource: String?
    /// 完整的引擎名（「DeepSeek · 模型名」）：悬停说明、引擎选单，以及与缓存译文的引擎比对
    let engineName: String
    /// 引擎徽标上的简称（「DeepSeek」「siliconflow」）：只用于显示，不写入缓存
    let engineShortName: String
    let sendsTextOffDevice: Bool
    /// 云端引擎的主机名（「已发送到 api.deepseek.com」）；本机引擎为 nil
    let host: String?
    /// 云端引擎且内容疑似含密钥：必须由用户点「仍然翻译」确认后才可发送（每次、每条）
    let needsSecretConfirmation: Bool
    /// 该目标语言已有缓存：translate 会立即给出完整结果、不联网
    let isCached: Bool
}

/// 翻译卡「对照」视图的一段原文
struct ClipTranslationSegment: Equatable, Sendable {
    let index: Int
    /// 该段原文：富文本条目保留段落样式（标题、列表）与行内样式（粗体、链接、行内代码）
    let original: AttributedString
    /// 代码行、URL、空行等不翻译，原样显示与粘贴
    let isTranslatable: Bool
}

/// 翻译完成后的结果（粘贴、复制、存为新条目都用它）
struct ClipTranslationResult: Equatable, Sendable {
    /// 完整译文纯文本（图片为按阅读顺序拼接的块译文）
    let plainText: String
    /// 富文本条目：保留结构的译文（粘贴时写 RTF / HTML + 纯文本）；纯文本与图片条目为 nil
    let richText: AttributedString?
    /// 图片条目：译后 PNG（带 DPI）的文件 URL；文本条目为 nil
    let imageURL: URL?
    let engineName: String
    let isOnDevice: Bool
    let fromCache: Bool
}

/// 流式事件：先 started，再若干段 / 块，最后 finished；出错时以 TranslationFailure 结束
enum ClipTranslationEvent: Sendable {
    /// 文本：原文分段（缓存命中时紧接着给出全部段）；图片：segments 为空
    case started(segments: [ClipTranslationSegment])
    /// 文本：第 index 段译文到达
    case segment(index: Int, translation: AttributedString)
    /// 图片：一块译文的版面到达（用 TranslationPainter 叠画在原图上），original 为该块原文（悬停气泡）
    case imageBlock(TranslatedBlock, original: String)
    /// 全部完成（已写入缓存）
    case finished(ClipTranslationResult)
}

/// 面板取得剪贴板翻译能力的入口
@MainActor
protocol ClipTranslating: AnyObject {
    /// 语言选单候选（BCP-47，按显示顺序），与截图翻译共享
    var selectableLanguages: [String] { get }
    func eligibility(of item: ClipItem) -> ClipTranslationEligibility
    /// target 为 nil 时按自动规则（含「按粘贴目标应用记住的语言」）；pasteTarget 为当前粘贴目标的 bundle id。
    /// 引擎不可用时给出原因
    func plan(
        for item: ClipItem, target: String?, pasteTarget: String?
    ) -> Result<ClipTranslationPlan, TranslationFailure>
    /// 开始翻译；取消消费任务即取消翻译。confirmedSecret：用户已点「仍然翻译」
    func translate(_ item: ClipItem, plan: ClipTranslationPlan, confirmedSecret: Bool) -> AsyncThrowingStream<
        ClipTranslationEvent, any Error
    >
    /// ⇄ 对调：把一段文字（当前译文）译到指定语言；不写缓存
    func translate(text: String, languages: TranslationLanguages) -> AsyncThrowingStream<
        ClipTranslationEvent, any Error
    >
    /// 用户在语言选单里选定目标语言（nil = 自动）；rememberFor 非 nil 时记为该粘贴目标应用的默认目标语言
    func setTarget(_ language: String?, rememberFor pasteTarget: String?)
    /// 该粘贴目标应用是否记住了目标语言（语言选单里的勾选状态）
    func rememberedTarget(for pasteTarget: String) -> String?
    /// 「存为新条目」（⌘S）：受暂停记录、疑似密钥、长度上限约束；返回是否已保存
    func saveAsNewItem(_ result: ClipTranslationResult) -> Bool
    func canResolve(_ failure: TranslationFailure) -> Bool
    /// 带用户去设置 / 下载语言；用户处理完后返回，true 表示值得重试
    func resolve(_ failure: TranslationFailure) async -> Bool
}
