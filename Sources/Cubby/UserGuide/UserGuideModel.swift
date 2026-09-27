import AppKit
import Observation

/// 使用说明窗口的状态：载入、目录与当前节、搜索
@MainActor
@Observable
final class UserGuideModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var contents: [GuideContentsEntry] = []
    /// 目录中高亮的一项：随滚动更新，点目录时直接设定
    private(set) var currentEntryID: GuideContentsEntry.ID?
    /// 包含搜索词的目录项；nil 表示没有在搜索
    private(set) var matchingEntryIDs: Set<GuideContentsEntry.ID>?
    /// 每次 ⌘F 递增，搜索框据此获得焦点
    private(set) var searchFocusRequest = 0
    var query = "" {
        didSet {
            if query != oldValue { applySearch() }
        }
    }

    @ObservationIgnored let document = GuideTextController()
    @ObservationIgnored private var outline = GuideOutline.empty
    @ObservationIgnored private var plainText: NSString = ""
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var matches: [NSRange] = []
    @ObservationIgnored private var matchIndex = 0

    init() {
        document.onVisibleRegionChange = { [weak self] region in self?.visibleRegionDidChange(region) }
        document.onLinkClick = { [weak self] url in self?.open(url) }
    }

    /// 搜索时只列出包含搜索词的节
    var visibleContents: [GuideContentsEntry] {
        guard let matchingEntryIDs else { return contents }
        return contents.filter { matchingEntryIDs.contains($0.id) }
    }

    var hasNoResults: Bool {
        matchingEntryIDs != nil && matches.isEmpty
    }

    /// 第一次打开窗口时载入：后台读取并解析，主线程排版
    func loadIfNeeded() {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        let fileName = GuideSource.preferredFileName
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { GuideSource.load(fileName: fileName) }.value
            present(loaded)
        }
    }

    /// 点目录：跳到该节标题
    func select(_ id: GuideContentsEntry.ID) {
        document.scroll(toCharacter: id)
        currentEntryID = id
    }

    /// 搜索框里按 ↩：跳到下一处命中
    func revealNextMatch() {
        guard !matches.isEmpty else { return NSSound.beep() }
        matchIndex = (matchIndex + 1) % matches.count
        reveal(matches[matchIndex])
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    // MARK: - 私有

    private func present(_ loaded: GuideSource.Loaded?) {
        guard let loaded else {
            phase = .failed
            return
        }
        let rendering = GuideTypesetter.render(loaded.document)
        outline = GuideOutline(headings: rendering.headings)
        plainText = rendering.text.string as NSString
        directory = loaded.directory
        contents = outline.contents
        document.display(rendering.text)
        phase = .ready
        applySearch()
    }

    private func applySearch() {
        guard phase == .ready else { return }
        matches = GuideSearch.ranges(of: query, in: plainText)
        matchIndex = 0
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        matchingEntryIDs = isSearching ? outline.entries(containing: matches) : nil
        document.highlight(matches)
        if let first = matches.first { reveal(first) }
    }

    /// 滚到命中处，目录高亮它所在的节（而不是可见区域顶部的节）
    private func reveal(_ match: NSRange) {
        document.reveal(match)
        currentEntryID = outline.entry(containing: match.location)
    }

    private func visibleRegionDidChange(_ region: GuideVisibleRegion) {
        let current = outline.currentEntry(in: region)
        if current != currentEntryID { currentEntryID = current }
    }

    private func open(_ url: URL) {
        switch GuideLinkTarget.resolve(url, relativeTo: directory) {
        case .web(let url), .localFile(let url):
            NSWorkspace.shared.open(url)
        case .anchor(let anchor):
            guard let location = outline.location(ofAnchor: anchor) else { return NSSound.beep() }
            document.scroll(toCharacter: location)
            currentEntryID = outline.entry(containing: location)
        case .ignored:
            NSSound.beep()
        }
    }
}
