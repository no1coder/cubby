import AppKit
import CubbyCore

/// 覆盖层里截图翻译的 App 侧状态：流水线、悬停看原文的 400 ms 计时、翻译条与卷帘等视图的输入。
/// 会话状态都在 Core（`ScreenshotSession`）里，这里只放与时间、引擎有关的部分
@MainActor
final class OverlayTranslationController {
    let services: ScreenshotTranslationServices
    /// 气泡显示中的块（悬停满 400 ms 后才有值）
    private(set) var bubbleBlockID: Int?
    private var hoverCandidate: Int?
    /// 拖卷帘分隔线时的光标位置：分隔线自己接收鼠标，会话里的光标停在按下前，这期间不出气泡
    private var suppressedCursor: CGPoint?
    private let names = TranslationLanguageNames()
    private var hoverTask: Task<Void, Never>?
    private let rerender: @MainActor () -> Void
    private lazy var pipeline = ScreenshotTranslationPipeline(
        services: services, hiddenRegions: hiddenRegions, selection: selection
    ) { [weak self] event in self?.send(event) }
    private let send: @MainActor (TranslationEvent) -> Void
    private let hiddenRegions: @MainActor () -> [CGRect]
    private let selection: @MainActor () -> CGRect?

    /// send：把流水线回报交给会话；hiddenRegions：会话当前的马赛克区域；selection：会话当前的选区；
    /// rerender：气泡计时到点后重绘
    init(
        services: ScreenshotTranslationServices,
        send: @escaping @MainActor (TranslationEvent) -> Void,
        hiddenRegions: @escaping @MainActor () -> [CGRect],
        selection: @escaping @MainActor () -> CGRect?,
        rerender: @escaping @MainActor () -> Void
    ) {
        self.services = services
        self.send = send
        self.hiddenRegions = hiddenRegions
        self.selection = selection
        self.rerender = rerender
    }

    func perform(_ effect: TranslationEffect, capture: CaptureSession) {
        pipeline.perform(effect, capture: capture)
    }

    /// 会话结束：取消进行中的任务与计时
    func cancel() {
        pipeline.cancel()
        hoverTask?.cancel()
        hoverTask = nil
    }

    /// 拖动卷帘分隔线：收起气泡，直到指针再在画布上移动
    func wipeDragged(cursor: CGPoint) {
        suppressedCursor = cursor
        hoverTask?.cancel()
        hoverCandidate = nil
        bubbleBlockID = nil
    }

    /// 每次渲染前调用：悬停的块变了就重新计时，气泡先收起
    func track(_ session: ScreenshotSession) {
        if suppressedCursor != session.cursor {
            suppressedCursor = nil
        }
        let hovered = suppressedCursor == nil ? session.hoveredTranslationBlockID : nil
        guard hovered != hoverCandidate else { return }
        hoverCandidate = hovered
        hoverTask?.cancel()
        bubbleBlockID = nil
        guard let hovered else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: OverlayTokens.translationHoverDelay)
            guard !Task.isCancelled, let self, self.hoverCandidate == hovered else { return }
            self.bubbleBlockID = hovered
            self.rerender()
        }
    }

    // MARK: - 视图输入

    func barModel(for session: ScreenshotSession) -> TranslationBarModel? {
        TranslationBarModel.make(for: session, provider: services.provider, names: names, endonyms: endonyms)
    }

    /// 语言选单各项的自称（会话内不变，只算一次）
    private lazy var endonyms: [String: String] = Dictionary(
        services.provider.selectableLanguages.map { ($0, names.endonym($0)) }
    ) { first, _ in first }

    /// 卷帘、按住空格提示、悬停气泡
    func chrome(for session: ScreenshotSession) -> OverlayTranslationChrome {
        var chrome = OverlayTranslationChrome()
        if case .split(let x) = session.translationDisplay, let selection = session.selection {
            chrome.wipe = OverlayTranslationChrome.Wipe(x: x, selection: selection, isFocused: session.isWipeFocused)
        }
        chrome.peekSelection = session.isPeekingOriginal ? session.selection : nil
        if let bubble = bubble(for: session), let selection = session.selection {
            chrome.bubble = OverlayTranslationChrome.Bubble(
                text: bubble.text, block: bubble.frame, selection: selection)
        }
        return chrome
    }

    /// 气泡的原文与块的位置；悬停已失效（块被撤销、切到原文等）时为 nil
    func bubble(for session: ScreenshotSession) -> (text: String, frame: CGRect)? {
        guard let id = bubbleBlockID, session.hoveredTranslationBlockID == id, let run = session.translation,
            let block = run.blocks.first(where: { $0.id == id }), let placed = run.translatedBlock(id: id)
        else { return nil }
        return (block.text, placed.eraseFrame)
    }
}

/// 覆盖层上与截图翻译有关的浮层：卷帘分隔线、按住空格的提示、悬停气泡（全局点）
struct OverlayTranslationChrome: Equatable {
    struct Wipe: Equatable {
        let x: CGFloat
        let selection: CGRect
        let isFocused: Bool
    }

    struct Bubble: Equatable {
        let text: String
        let block: CGRect
        let selection: CGRect
    }

    var wipe: Wipe?
    /// 按住空格看原文时的选区（提示显示在选区顶部居中）
    var peekSelection: CGRect?
    var bubble: Bubble?
}

/// 覆盖层上翻译相关的用户操作（翻译条按钮、卷帘拖动）
enum OverlayTranslationInput {
    case bar(TranslationBarAction)
    /// 拖动分隔线到全局点 x
    case moveWipe(CGFloat)
    /// VoiceOver 增减分隔线（true = 向右）
    case stepWipe(Bool)
}

extension OverlayRenderModel {
    /// 某块屏幕的译文层：本屏的块、显示方式、流光、悬停描边
    static func translationState(
        for session: ScreenshotSession,
        screen: CaptureScreen,
        outline: CGRect?
    ) -> OverlayTranslationState {
        guard let run = session.translation else { return OverlayTranslationState() }
        let onScreen = { (rect: CGRect) in !rect.isNull && rect.intersects(screen.frame) }
        var state = OverlayTranslationState()
        state.blocks = run.translatedBlocks.filter { onScreen($0.eraseFrame.union($0.textFrame)) }
        state.display = session.translationDisplay
        state.animatesArrivals = run.status.isBusy
        state.shimmers = run.pendingBlocks.map { block in
            OverlayTranslationState.Shimmer(id: block.id, rect: block.frame.insetBy(dx: -2, dy: -2))
        }.filter { onScreen($0.rect) }
        state.shimmerSpan = run.area
        state.outline = outline
        return state
    }
}
