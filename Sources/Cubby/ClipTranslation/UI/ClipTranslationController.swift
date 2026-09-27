import AppKit
import CubbyCore
import Observation

/// 面板里的剪贴板翻译（docs/CLIP-TRANSLATION-DESIGN.md §1.3）：翻译卡、⌥↩ 行内任务与按住 ⌥ 预览。
/// 同一时刻最多一个翻译卡任务 + 一个 ⌥↩ 任务 + 一个预览；新任务取消同类旧任务，未完成的部分结果丢弃。
/// 视图模型只负责路由按键；本对象为 nil 表示功能不可用（macOS 26 以下或翻译服务未接线，K8）
@MainActor
@Observable
final class ClipTranslationController {
    let card: TranslationCardController
    let inline: InlineTranslationController
    let peek: TranslationPeekController

    @ObservationIgnored let environment: ClipTranslationEnvironment
    /// 粘贴 / 复制译文（面板控制器写剪贴板）；复制返回是否成功
    @ObservationIgnored var onPaste: ((TranslationPasteRequest) -> Void)? {
        didSet { wire() }
    }
    @ObservationIgnored var onCopy: ((TranslationPasteRequest) -> Bool)? {
        didSet { wire() }
    }
    /// 「去设置 / 下载语言」：面板先无动画隐藏，再交给翻译服务处理（§4）
    @ObservationIgnored var onResolve: ((TranslationFailure) -> Void)? {
        didSet { wire() }
    }
    /// 底栏定时提示（⌥ 已松开时预览的失败说明）
    @ObservationIgnored var onNotice: ((String) -> Void)? {
        didSet { wire() }
    }

    init(environment: ClipTranslationEnvironment) {
        self.environment = environment
        card = TranslationCardController(environment: environment)
        inline = InlineTranslationController(environment: environment)
        peek = TranslationPeekController(environment: environment)
    }

    var translator: any ClipTranslating {
        environment.translator
    }

    // MARK: - 按键

    /// ⌥ 单独按下 / 松开（flagsChanged）。翻译卡打开时按住 ⌥ 看原文；否则计时开始列表预览
    func optionChanged(isDown: Bool, canPeek: Bool, selected: @escaping @MainActor () -> ClipItem?) {
        if card.isOpen {
            card.setPeeking(isDown)
            return
        }
        if isDown {
            guard canPeek, !(inline.job?.isRunning ?? false) else { return }
            peek.optionPressed(item: selected)
        } else {
            peek.optionReleased()
        }
    }

    /// 任意按键按下：取消按住 ⌥ 的计时与预览。⌥↩ 在预览中粘贴显示的内容（pasteShownPeek），
    /// 没有预览时只取消计时（否则计时到点会对同一条再发一次翻译）
    func keyPressed(isOptionReturn: Bool, isEscape: Bool) {
        guard isOptionReturn else {
            peek.otherKeyPressed(isEscape: isEscape)
            return
        }
        if peek.peek == nil { peek.cancel() }
    }

    /// 预览中按 ↩ 粘贴显示的内容；没有预览时返回 false
    func pasteShownPeek() -> Bool {
        peek.pasteShown()
    }

    // MARK: - esc 与生命周期

    /// esc 的第二层（§1.5）：取消进行中的翻译（卡片或 ⌥↩），或收起 ⌥↩ 的行内提示
    func cancelActiveWork() -> TranslationCancellation? {
        if card.cancelWork() {
            return .card
        }
        if peek.cancelPendingPaste() {
            return .inline
        }
        guard inline.job != nil else { return nil }
        return inline.cancel() ? .inline : .inlineIssue
    }

    /// 选中项变化：卡片跟随新条目；⌥↩ 与预览只属于原条目，取消
    func selectionChanged(to item: ClipItem?) {
        card.follow(item)
        if let job = inline.job, job.itemID != item?.id {
            inline.cancel()
        }
        if let current = peek.peek, current.itemID != item?.id {
            peek.cancel()
        }
    }

    /// 面板隐藏：取消全部任务（§1.4）
    func tearDown() {
        card.tearDown()
        inline.cancel()
        peek.cancel()
    }

    // MARK: - 缓存

    /// 已缓存的译文（右键「复制译文」）：直接由缓存条目拼出，不经翻译服务、不看缓存出自哪个引擎（换了引擎也能复制）。
    /// 优先自动规则下的目标语言，否则取最近缓存的一种；没有可用的缓存为 nil
    func cachedResult(for item: ClipItem) -> ClipTranslationResult? {
        let entries = item.translations?.entries ?? []
        let planned = translator.plan(for: item, target: nil, pasteTarget: environment.pasteTarget()?.bundleID)
        let autoTarget = (try? planned.get())?.languages.target
        guard
            let entry = autoTarget.flatMap(item.translation(for:))
                ?? entries.max(by: { $0.createdAt < $1.createdAt })
        else { return nil }
        let result = CachedTranslation.result(
            for: item, entry: entry, imageURL: environment.translatedImageURL(entry))
        return result.isEmpty ? nil : result
    }

    // MARK: - 私有

    private func wire() {
        card.onPaste = onPaste
        card.onCopy = onCopy
        card.onResolve = onResolve
        inline.onPaste = onPaste
        inline.onResolve = onResolve
        peek.onPaste = onPaste
        peek.onNotice = onNotice
    }
}

/// esc 取消了什么（取消 ⌥↩ 时底栏提示「已取消翻译」）
enum TranslationCancellation: Equatable {
    case card
    case inline
    /// 只是收起了 ⌥↩ 的行内提示
    case inlineIssue
}
