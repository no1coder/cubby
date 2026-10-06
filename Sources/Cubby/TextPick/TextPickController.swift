import AppKit
import CubbyCore
import Observation

/// 拆词卡要输出的内容：结果文字与它所属的条目（粘贴时提升原条目，docs/TEXT-PICK-DESIGN.md P9）
struct TextPickRequest: Equatable {
    let itemID: UUID
    let text: String
}

/// 拆词卡的状态（docs/TEXT-PICK-DESIGN.md §2、§4）：当前条目、分词结果、选取与跟随选中项。
/// 短文本同步分词（打开时就有内容、高度可立即算出）；长文本的数据检测要上百毫秒，放到后台，完成后再显示
@MainActor
@Observable
final class TextPickController {
    /// 不超过这么多 UTF-16 单元的文本同步分词（约 10 ms 内）；更长的文本在 440 宽下必然超过主面板高度
    private static let synchronousLimit = 2_000

    private(set) var isOpen = false
    /// 卡片显示的条目（头部的来源图标）
    private(set) var item: ClipItem?
    /// 分词结果；不支持的条目或后台分词未完成时为 nil
    private(set) var document: TextPickDocument?
    /// 当前条目没有可拆分的文字（显示状态页）
    private(set) var isUnsupported = false
    private(set) var selection = TextPickSelection()
    /// 按 P8 拼好的结果与所选的词数（选取变化时更新，视图多次读取不重复拼接）
    private(set) var result = ""
    /// 结果的字符数（用户看到的字符）
    private(set) var resultLength = 0
    private(set) var pickedWordCount = 0
    /// 从预览切来：关闭时回到预览
    private(set) var openedFromPreview = false
    /// 每换一份文档递增：画布据此重新排版、播放打开动画，窗口据此调整高度
    private(set) var documentVersion = 0

    /// 当前条目的可拆文字（判断跟随时内容是否变化，例如图片稍后才识别出文字）
    @ObservationIgnored private var sourceText: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var layoutCache: (version: Int, width: CGFloat, layout: TextPickLayout)?

    var isLoading: Bool {
        isOpen && !isUnsupported && document == nil
    }

    var tokenCount: Int {
        document?.tokens.count ?? 0
    }

    var isAllSelected: Bool {
        selection.isAll(count: tokenCount)
    }

    /// 窗口高度随之变化的状态：换条目、进入 / 离开状态页、分词完成
    struct LayoutKey: Hashable {
        let itemID: UUID?
        let isUnsupported: Bool
        let documentVersion: Int
    }

    var layoutKey: LayoutKey {
        LayoutKey(itemID: item?.id, isUnsupported: isUnsupported, documentVersion: documentVersion)
    }

    // MARK: - 打开 / 关闭 / 跟随

    /// 打开拆词卡；没有可拆分文字的条目不打开，返回 false（调用方提示音 + 底栏提示，P4）
    func open(_ item: ClipItem, fromPreview: Bool) -> Bool {
        guard let text = TextPickSource(item: item).text else { return false }
        isOpen = true
        openedFromPreview = fromPreview
        load(item, text: text)
        return true
    }

    func close() {
        task?.cancel()
        task = nil
        isOpen = false
        item = nil
        sourceText = nil
        document = nil
        isUnsupported = false
        layoutCache = nil
        apply(TextPickSelection())
    }

    /// 选中项变化：跟到新条目，选取清空；不支持的条目显示状态页，移回来继续（P4）；没有选中项时关闭
    func follow(_ item: ClipItem?) {
        guard isOpen else { return }
        guard let item else {
            close()
            return
        }
        let text = TextPickSource(item: item).text
        guard item.id != self.item?.id || text != sourceText else { return }
        guard let text else {
            task?.cancel()
            self.item = item
            sourceText = nil
            document = nil
            isUnsupported = true
            apply(TextPickSelection())
            return
        }
        load(item, text: text)
    }

    private func load(_ item: ClipItem, text: String) {
        task?.cancel()
        self.item = item
        sourceText = text
        isUnsupported = false
        apply(TextPickSelection())
        guard text.utf16.count > Self.synchronousLimit else {
            show(TextPickTokenizer.document(for: text))
            return
        }
        document = nil
        let id = item.id
        task = Task { @MainActor [weak self] in
            // 按住方向键扫过多条长文本时只拆停下的那条：分词开始前先等一小会儿，期间换了条目就作废
            try? await Task.sleep(for: TextPickMetrics.backgroundTokenizeDelay)
            guard !Task.isCancelled else { return }
            let document = await Task.detached(priority: .userInitiated) {
                TextPickTokenizer.document(for: text)
            }.value
            guard let self, !Task.isCancelled, self.item?.id == id, self.sourceText == text else { return }
            self.show(document)
        }
    }

    private func show(_ newDocument: TextPickDocument) {
        document = newDocument
        documentVersion += 1
        layoutCache = nil
    }

    // MARK: - 选取

    /// 画布上的点选、拖选与 ⇧单击
    func select(_ newSelection: TextPickSelection) {
        guard newSelection != selection else { return }
        apply(newSelection)
    }

    /// ⌘A / 「全选」：已全选时清空（P7）
    func toggleAll() {
        guard tokenCount > 0 else { return }
        apply(selection.togglingAll(count: tokenCount))
    }

    private func apply(_ newSelection: TextPickSelection) {
        selection = newSelection
        guard let document, !newSelection.isEmpty else {
            result = ""
            resultLength = 0
            pickedWordCount = 0
            return
        }
        result = TextPickResult.text(of: document, selection: newSelection)
        resultLength = result.count
        pickedWordCount = newSelection.indices.reduce(0) { count, index in
            document.tokens.indices.contains(index) && document.tokens[index].kind != .punctuation ? count + 1 : count
        }
    }

    /// 要粘贴 / 复制的内容；没有选取时为 nil（调用方提示音）
    var request: TextPickRequest? {
        guard let item, !result.isEmpty else { return nil }
        return TextPickRequest(itemID: item.id, text: result)
    }

    // MARK: - 排版

    /// 当前文档在给定内容宽度下的排版（画布与窗口高度共用，按文档版本与宽度缓存）
    func layout(width: CGFloat) -> TextPickLayout? {
        guard let document else { return nil }
        if let cache = layoutCache, cache.version == documentVersion, cache.width == width {
            return cache.layout
        }
        let layout = TextPickTypesetter.layout(document, width: width)
        layoutCache = (documentVersion, width, layout)
        return layout
    }
}
