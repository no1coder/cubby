import AppKit
import Observation
import CubbyCore

/// 面板旁的详情区（设计文档 K1）
enum DetailPane: Equatable {
    case preview
    case translation
}

/// 面板的交互状态：搜索、分类、选中项、预览、提示以及各类操作
@MainActor
@Observable
final class PanelViewModel {
    private static let toastDuration: Duration = .seconds(4)
    /// 关闭后这么久内再次呼出，保留上次的分类（搜索词总是清空）
    private static let categoryMemory: TimeInterval = 30

    var searchText = "" {
        didSet { if searchText != oldValue { selectedID = nil } }
    }
    private(set) var category: ClipCategory = .all
    private(set) var selectedID: UUID?
    /// 每次面板显示时递增，驱动视图重新聚焦搜索框并滚动到顶部
    private(set) var focusToken = 0
    /// 面板旁的详情区：空格预览或翻译卡（二者互斥，共用预览面板窗口）
    private(set) var detailPane: DetailPane?
    private(set) var isShowingHelp = false
    /// 面板显示时计算一次：是否能直接粘贴（避免每次渲染都查询辅助功能权限）
    private(set) var canPasteDirectly = false
    private(set) var toast: PanelToast?
    private(set) var target: PasteTarget?
    private(set) var warnings: [PanelWarning] = []
    /// 用户点了「稍后」的提醒及当时的状态签名：本次运行期间状态不变就不再显示
    private(set) var dismissedWarnings: [PanelWarning: String] = [:]

    @ObservationIgnored let store: ClipStore
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored var onPaste: ((ClipItem, PasteMode) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored var onOpenUserGuide: (() -> Void)?
    @ObservationIgnored var onTakeScreenshot: (() -> Void)?
    @ObservationIgnored var onDetailPaneChange: ((DetailPane?) -> Void)?
    /// 把图片条目贴到屏幕上（由 PanelController 注入）
    @ObservationIgnored var onPinImage: ((ClipItem) -> Void)?
    /// 面板上次隐藏的时间，用于判断是否保留分类
    @ObservationIgnored private var lastHiddenAt: Date?
    /// 搜索会话：预折叠索引 + 前缀逐键收窄，同一次渲染内多次访问不重复计算
    @ObservationIgnored private var search = ClipSearchSession()
    /// 剪贴板翻译；nil 表示不可用（macOS 26 以下或翻译服务未接线），所有入口随之隐藏
    var translation: ClipTranslationController?
    /// 在卡片上显示译文首行（「设置 › 翻译」的开关；只因译文命中搜索时无论开关都显示）
    var showsTranslationOnCards: Bool {
        get { settings.showsTranslationOnCards }
        set { settings.showsTranslationOnCards = newValue }
    }

    init(store: ClipStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    // MARK: - 派生数据

    /// 过滤并按相关度排序的结果（ClipSearchSession 内部按历史版本与查询缓存）
    var items: [ClipItem] {
        search.results(for: ClipQuery(text: searchText, category: category), in: store)
    }

    /// 显式选中的条目不在结果中时回落到第一条
    var selectedItem: ClipItem? {
        let visible = items
        return visible.first { $0.id == selectedID } ?? visible.first
    }

    /// 已恢复记录时立即隐藏「已暂停」横幅（settings 可观察，横幅随之消失）
    var visibleWarnings: [PanelWarning] {
        warnings.filter { warning in
            guard warning != .paused || settings.isPaused else { return false }
            return dismissedWarnings[warning] != warning.stateSignature
        }
    }

    func dismissWarning(_ warning: PanelWarning) {
        guard warning.isDismissible else { return }
        dismissedWarnings[warning] = warning.stateSignature
    }

    func performAction(for warning: PanelWarning) {
        warning.performAction(settings: settings)
    }

    var keywords: [String] {
        ClipQuery(text: searchText).keywords
    }

    var totalCount: Int {
        store.history.items.count
    }

    // MARK: - 面板生命周期

    func prepareForDisplay(target: PasteTarget?, warnings: [PanelWarning], canPasteDirectly: Bool, now: Date = Date()) {
        self.target = target
        self.warnings = warnings
        self.canPasteDirectly = canPasteDirectly
        isShowingHelp = false
        searchText = ""
        if !Self.remembersCategory(hiddenAt: lastHiddenAt, now: now) {
            category = .all
        }
        selectedID = nil
        focusToken += 1
    }

    func panelDidHide(at date: Date = Date()) {
        lastHiddenAt = date
        translation?.tearDown()
        setDetailPane(nil)
        dismissToast()
    }

    private static func remembersCategory(hiddenAt: Date?, now: Date) -> Bool {
        guard let hiddenAt else { return false }
        let elapsed = now.timeIntervalSince(hiddenAt)
        return elapsed >= 0 && elapsed < categoryMemory
    }

    // MARK: - 键盘指令

    /// 执行指令；返回 false 表示未处理，事件应继续传递（例如搜索框自身的 ⌘Z）
    @discardableResult
    func handle(_ command: PanelCommand) -> Bool {
        switch command {
        case .moveUp, .moveDown, .moveToFirst, .moveToLast, .pageUp, .pageDown: moveSelection(command)
        case .paste, .pasteAlternate, .copyOnly: pasteSelected(command)
        case .pasteAt(let index): paste(at: index)
        case .escape: escape()
        case .nextCategory: cycleCategory(by: 1)
        case .previousCategory: cycleCategory(by: -1)
        case .delete: if let item = selectedItem { delete(item) }
        case .undo: return undoDelete()
        case .toggleFavorite: if let item = selectedItem { toggleFavorite(item) }
        case .pinToScreen: pinSelected()
        case .togglePreview: setPreviewVisible(!isPreviewVisible)
        case .translate: toggleTranslationCard()
        case .translateAndPaste: translateAndPasteSelected()
        case .copyTranslation, .saveTranslation, .stepTranslationView: return handleCardCommand(command)
        case .open: if let item = selectedItem { open(item) }
        case .openSettings: onOpenSettings?()
        case .takeScreenshot: onTakeScreenshot?()
        }
        return true
    }

    // MARK: - 选择与分类

    func select(_ item: ClipItem) {
        selectedID = item.id
    }

    func selectCategory(_ newCategory: ClipCategory) {
        category = newCategory
        selectedID = nil
    }

    private func moveSelection(_ command: PanelCommand) {
        let visible = items
        let current = visible.firstIndex { $0.id == selectedItem?.id } ?? 0
        guard let next = command.selectionIndex(from: current, count: visible.count) else { return }
        selectedID = visible[next].id
    }

    private func cycleCategory(by offset: Int) {
        selectCategory(category.cycled(by: offset))
    }

    // MARK: - 条目操作

    func paste(_ item: ClipItem, mode: PasteMode = .standard) {
        onPaste?(item, mode)
    }

    /// ↩ / ⇧↩ / ⌘↩：翻译卡打开时改为粘贴 / 纯文本粘贴 / 复制译文（§1.1）
    private func pasteSelected(_ command: PanelCommand) {
        if handleCardCommand(command) { return }
        guard let item = selectedItem else { return }
        switch command {
        case .pasteAlternate: paste(item, mode: .alternate)
        case .copyOnly: paste(item, mode: .copyOnly)
        default: paste(item, mode: .standard)
        }
    }

    private func paste(at index: Int) {
        let visible = items
        guard visible.indices.contains(index) else { return }
        paste(visible[index])
    }

    func toggleFavorite(_ item: ClipItem) {
        store.toggleFavorite(id: item.id)
    }

    func delete(_ item: ClipItem) {
        let visible = items
        // 删除当前选中项后选中相邻条目，保持键盘操作连贯
        if item.id == selectedItem?.id, let index = visible.firstIndex(where: { $0.id == item.id }) {
            let neighbor =
                visible.indices.contains(index + 1)
                ? visible[index + 1]
                : (index > 0 ? visible[index - 1] : nil)
            selectedID = neighbor?.id
        }
        store.remove(id: item.id)
        showToast(.deleted())
    }

    /// 撤销删除；没有可撤销的删除时返回 false
    func undoDelete() -> Bool {
        guard let restored = store.undoRemove() else { return false }
        selectedID = restored.id
        toast = nil
        return true
    }

    /// 只有图片能贴到屏幕上；其他类型提示音反馈
    func pin(_ item: ClipItem) {
        guard item.kind == .image, let onPinImage else {
            NSSound.beep()
            return
        }
        onPinImage(item)
    }

    private func pinSelected() {
        guard let item = selectedItem else { return }
        pin(item)
    }

    func open(_ item: ClipItem) {
        guard !ItemOpener.open(item, imageURL: store.imageURL(for: item)) else { return }
        NSSound.beep()
    }

    func imageURL(for item: ClipItem) -> URL? {
        store.imageURL(for: item)
    }

    var isPreviewVisible: Bool {
        detailPane == .preview
    }

    /// 空格 / ⌘Y：翻译卡打开时切到预览（§1.5）
    func setPreviewVisible(_ visible: Bool) {
        if visible {
            translation?.card.close()
            setDetailPane(.preview)
        } else if isPreviewVisible {
            setDetailPane(nil)
        }
    }

    /// 没有选中条目（如空历史）时不打开详情区
    func setDetailPane(_ pane: DetailPane?) {
        guard pane != detailPane, pane == nil || selectedItem != nil else { return }
        detailPane = pane
        onDetailPaneChange?(pane)
    }

    // MARK: - 提示

    func showToast(_ newToast: PanelToast) {
        // 旧提示被替换时，其撤销机会随之失效
        if toast?.action == .undoDelete, newToast.action != .undoDelete {
            store.discardUndo()
        }
        toast = newToast
        Task { @MainActor [weak self, id = newToast.id] in
            try? await Task.sleep(for: Self.toastDuration)
            guard let self, self.toast?.id == id else { return }
            self.dismissToast()
        }
    }

    func dismissToast() {
        if toast?.action == .undoDelete {
            store.discardUndo()
        }
        toast = nil
    }

    func toggleHelp() {
        isShowingHelp.toggle()
    }

    /// 帮助浮层底部的「完整使用说明…」：先关帮助，再由 PanelController 收起面板并打开使用说明窗口
    func openUserGuide() {
        isShowingHelp = false
        onOpenUserGuide?()
    }

    /// 帮助 → 取消进行中的翻译 → 关闭详情区（翻译卡 / 预览）→ 清空搜索 → 关闭面板（§1.5）
    private func escape() {
        if isShowingHelp {
            isShowingHelp = false
        } else if let cancelled = translation?.cancelActiveWork() {
            if cancelled == .inline { showToast(.info(TranslationCopy.cancelledTitle, symbolName: "xmark")) }
        } else if detailPane == .translation {
            closeTranslationCard()
        } else if isPreviewVisible {
            setPreviewVisible(false)
        } else if !searchText.isEmpty {
            searchText = ""
        } else {
            onClose?()
        }
    }
}
