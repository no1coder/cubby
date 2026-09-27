import CubbyCore
import Foundation

/// 翻译界面共用的依赖：翻译服务、条目查询、粘贴目标与时长
@MainActor
struct ClipTranslationEnvironment {
    let translator: any ClipTranslating
    /// 按 id 取条目的最新值（历史可能在翻译期间变化）
    let item: (UUID) -> ClipItem?
    /// 面板呼出时的粘贴目标（「粘贴到 <App> 时总是译为此语言」按它记住）
    let pasteTarget: () -> PasteTarget?
    /// 缓存里译后图片的文件（右键「复制译文」直接从缓存取）
    let translatedImageURL: (ClipTranslation) -> URL?
    let timings: TranslationTimings
    /// 两个 BCP-47 是否同一语言（「原文已是目标语言」、语言选单的原文语言与勾选）；与翻译服务同一判定
    var isSameLanguage: (String, String) -> Bool = ClipLanguageMatch.isSameLanguage
}

/// 由缓存条目直接拼出结果（不经翻译服务）
enum CachedTranslation {
    static func result(for item: ClipItem, entry: ClipTranslation, imageURL: URL?) -> ClipTranslationResult {
        ClipTranslationResult(
            plainText: plainText(for: item, entry: entry), richText: nil,
            imageURL: entry.imageName == nil ? nil : imageURL,
            engineName: entry.engineName, isOnDevice: entry.isOnDevice, fromCache: true)
    }

    /// 纯文本条目且分段算法未变：按原文的分隔符拼回（未翻译的段用原文）；否则各段按换行拼接（富文本、旧分段、图片）
    private static func plainText(for item: ClipItem, entry: ClipTranslation) -> String {
        guard let text = item.text, item.formatsName == nil, entry.imageName == nil, entry.usesInlineMarkup != true,
            entry.segmentation == ClipTextSegmenter.version
        else { return entry.plainText }
        return ClipTextSegmenter.join(original: text, segments: entry.segments)
    }
}

/// 开始一次翻译前的判断结果
enum TranslationPlanOutcome: Equatable {
    case unsupported(ClipTranslationUnsupportedReason)
    case failed(TranslationFailure)
    case alreadyTarget(ClipTranslationPlan)
    case needsSecretConfirmation(ClipTranslationPlan)
    case ready(ClipTranslationPlan)
}

@MainActor
enum TranslationPlanning {
    /// 资格 → 计划 → 原文已是目标语言 → 疑似密钥，依次判断
    /// confirmedPlan：用户点「仍然翻译」时看到的计划。确认只对同一次发送有效（同一条、同一目标语言、同一引擎与主机），
    /// 新计划与它不同（换了语言、换了引擎或主机）时重新要求确认
    static func outcome(
        for item: ClipItem, target: String?, confirmedPlan: ClipTranslationPlan?,
        environment: ClipTranslationEnvironment
    ) -> TranslationPlanOutcome {
        let translator = environment.translator
        if case .unsupported(let reason) = translator.eligibility(of: item) {
            return .unsupported(reason)
        }
        let plan: ClipTranslationPlan
        switch translator.plan(for: item, target: target, pasteTarget: environment.pasteTarget()?.bundleID) {
        case .failure(let failure): return .failed(failure)
        case .success(let value): plan = value
        }
        if let source = plan.detectedSource, environment.isSameLanguage(source, plan.languages.target) {
            return .alreadyTarget(plan)
        }
        if plan.needsSecretConfirmation, !plan.isConfirmed(by: confirmedPlan), !plan.isCached {
            return .needsSecretConfirmation(plan)
        }
        return .ready(plan)
    }
}

extension ClipTranslationPlan {
    /// 两个计划是否同一次发送：目标语言、引擎与主机都相同（「仍然翻译」只对同一次发送有效）
    func isSameSend(as other: ClipTranslationPlan) -> Bool {
        languages.target == other.languages.target && engineName == other.engineName && host == other.host
            && sendsTextOffDevice == other.sendsTextOffDevice
    }

    /// 用户对这次发送确认过疑似密钥
    func isConfirmed(by confirmedPlan: ClipTranslationPlan?) -> Bool {
        confirmedPlan.map(isSameSend) ?? false
    }
}

/// 计划过期（引擎在本机与云端之间变了）时自动重新 plan 的次数上限：设置在翻译期间反复切换时不无限重试
let maxTranslationReplans = 2

/// 事件流的结束方式
enum TranslationStreamEnd: Equatable {
    case finished
    case failed(TranslationFailure)
    /// 服务拒绝发送（什么都没有发出）：计划过期要重新 plan，或疑似密钥未确认
    case refused(ClipTranslationRefusal)
    case cancelled
}

@MainActor
enum TranslationStream {
    /// 在主线程逐个消费事件；任务被取消时以 cancelled 结束。
    /// 未完成的流（有段 / 块没翻译）以 TranslationFailure 结束，已到达的部分不算结果；其他错误视为返回内容无法解析
    static func consume(
        _ stream: AsyncThrowingStream<ClipTranslationEvent, any Error>,
        onEvent: (ClipTranslationEvent) -> Void
    ) async -> TranslationStreamEnd {
        do {
            for try await event in stream {
                guard !Task.isCancelled else { return .cancelled }
                onEvent(event)
            }
            return Task.isCancelled ? .cancelled : .finished
        } catch let failure as TranslationFailure {
            return Task.isCancelled ? .cancelled : .failed(failure)
        } catch let refusal as ClipTranslationRefusal {
            return Task.isCancelled ? .cancelled : .refused(refusal)
        } catch {
            return Task.isCancelled || error is CancellationError ? .cancelled : .failed(.invalidResponse)
        }
    }
}
