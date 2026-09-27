import Foundation

// MARK: - 搜索

extension ClipStore {
    /// 搜索历史：索引就绪时走预折叠索引，否则逐条匹配；两者结果完全一致（见 ClipFilter.apply）
    public func search(_ query: ClipQuery) -> [ClipItem] {
        ClipFilter.apply(history.items, query: query, index: searchIndex)
    }

    /// 在后台为当前历史构建索引；完成时历史若已变化，在主线程补齐差异后再采用
    func buildSearchIndex() {
        let snapshot = history.items
        searchIndexTask = Task { [weak self] in
            let built = await Task.detached(priority: .utility) { ClipSearchIndex(items: snapshot) }.value
            self?.adoptSearchIndex(built)
        }
    }

    /// 等待首次索引构建完成（测试与基准用）
    func waitForSearchIndex() async {
        await searchIndexTask?.value
    }

    private func adoptSearchIndex(_ built: ClipSearchIndex) {
        searchIndex = built.updated(for: history.items)
    }
}
