import CubbyCore
import Foundation

/// 剪贴板翻译使用的引擎及其接收方式（docs/CLIP-TRANSLATION-DESIGN.md §7）
struct ClipEngine: Sendable {
    let engine: any TranslationEngine
    /// 大模型收受限 Markdown，系统翻译收纯文本（行内代码换成占位符）
    let input: ClipTranslationBatch.Input
    /// 云端引擎的主机名（「已发送到 api.deepseek.com」）；本机引擎为 nil
    let host: String?

    var displayName: String {
        engine.displayName
    }

    var sendsTextOffDevice: Bool {
        engine.sendsTextOffDevice
    }

    /// 缓存的译文是否出自这个引擎：换引擎（或换模型）即视为未缓存，重译后覆盖（缓存键只有目标语言，§0 K4）
    func produced(_ translation: ClipTranslation) -> Bool {
        translation.engineName == displayName && translation.isOnDevice == !sendsTextOffDevice
    }
}

/// 剪贴板翻译在截图翻译的 TranslationProviding 之上需要的能力（§7 缺口 2）。
/// 正式实现是 TranslationService（同一个实例同时给截图与面板）；面板 E2E 可用桩
@MainActor
protocol ClipTranslationProviding: TranslationProviding {
    /// 与 makeEngine() 相同的选择规则（设置里选了大模型且已配置 → 大模型，否则系统翻译）；
    /// prompt 为大模型提示词的场景：文本条目用剪贴板文本版，图片条目沿用截图版
    func makeClipEngine(prompt: LLMTranslationPrompt.Profile) -> Result<ClipEngine, TranslationFailure>
    /// 不看设置、只在本机运行的系统翻译（复制时自动翻译，§6）。缺少语言包时只报错，
    /// 不记录供「下载语言」使用的语言对
    func makeOnDeviceEngine() -> any TranslationEngine
    /// 该语言对的系统翻译语言包是否已下载（只查询，绝不触发下载）；源语言未知时为 false
    func isInstalled(_ languages: TranslationLanguages) async -> Bool
}

/// 服务拒绝发送（不是引擎的失败，什么都没有发出）：面板据此重新 plan，或先让用户确认疑似密钥
enum ClipTranslationRefusal: Error, Equatable, Sendable {
    /// 计划之后引擎在本机与云端之间变了（设置被改）：重新 plan 后再翻译
    case planOutdated
    /// 云端引擎、内容疑似含密钥而用户没有确认；⇄ 对调无法确认，这种情况一律不发送
    case secretNotConfirmed
}
