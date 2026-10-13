import Foundation
import Observation
import os

/// 剪贴板历史的状态中心：负责条目创建、状态变更、撤销、持久化与 blob 文件清理。
///
/// 持久化状态可在运行中切换（E8 ①）：历史已锁定或密钥尚未就绪时以 init(inMemoryWithLimit:) 创建，
/// 条目与图片只在内存中；之后 unlock(storage:blobs:) 读入加密历史、合并内存条目、开启写盘（见 ClipStore+Unlock）
@MainActor
@Observable
public final class ClipStore {
    /// 可撤销的删除记录
    public struct Removal: Equatable, Sendable {
        public let item: ClipItem
        public let index: Int
    }

    public internal(set) var history: ClipHistory
    public private(set) var limit: Int
    /// 每次历史变化递增，视图层可据此做缓存失效
    public internal(set) var revision = 0
    /// 最近一次删除，可通过 undoRemove() 恢复
    public internal(set) var lastRemoval: Removal?
    /// 本次运行是否把历史写盘。读取失败（非损坏）、文件来自更新版本、历史只在内存中时为 false：
    /// 不写盘、不删除磁盘上的文件，避免覆盖已有数据
    public internal(set) var canPersist: Bool
    /// 历史与图片只在内存中（已锁定或尚未就绪，E8 ①）：什么都不写盘
    public internal(set) var isInMemory: Bool
    /// 启动加载时遇到的问题（nil 表示正常），界面据此提示原因
    public internal(set) var loadIssue: LoadIssue?
    /// 自动裁剪（记录新内容、setLimit）时与收藏一样保留、且不占上限名额的条目，例如晾衣绳上的条目；由应用层同步。
    /// 设置它本身不裁剪也不保存，下次裁剪时生效。remove(id:) 与 clearHistory() 不看它：清空只保留收藏
    @ObservationIgnored public var protectedIDs: Set<UUID> = []

    @ObservationIgnored var blobs: any ClipBlobStoring
    /// nil：历史只在内存中，没有可写的存储
    @ObservationIgnored var saver: CoalescingSaver?
    /// 本次运行是否允许删除磁盘上的文件：只有干净地读入历史（没有任何加载问题）且可写盘后才允许（E8 ④）
    @ObservationIgnored var allowsDiskCleanup = false
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ClipStore")
    /// 最近一次后台记录：后续的后台记录等它入历史后再入，保证按调用顺序
    @ObservationIgnored private var pendingRecord: Task<ClipItem?, Never>?
    /// 搜索索引：加载后在后台构建（见 ClipStore+Search），之后每次历史变化时与 history 在同一处同步增量更新；
    /// nil 表示尚未就绪（搜索退回逐条匹配，结果相同）
    @ObservationIgnored public internal(set) var searchIndex: ClipSearchIndex?
    @ObservationIgnored var searchIndexTask: Task<Void, Never>?
    /// 旧条目缩略图回填（见 ClipStore+Thumbnails）
    @ObservationIgnored var thumbnailBackfill: Task<Int, Never>?
    /// 回填时生成并写入一张缩略图；测试可替换为能在生成前后暂停的实现，把删除确定地插在指定的一步
    @ObservationIgnored var thumbnailWriter: ThumbnailWriter = ClipStore.writeThumbnail

    /// 立即从 storage 读入历史并按结果决定本次运行是否写盘
    public init(
        storage: HistoryPersisting,
        blobs: any ClipBlobStoring,
        limit: Int,
        now: @escaping () -> Date = Date.init
    ) {
        self.blobs = blobs
        self.saver = CoalescingSaver(storage: storage)
        self.limit = max(limit, 1)
        self.now = now
        history = .empty
        canPersist = false
        isInMemory = !blobs.isPersistent
        adoptInitialLoad(Self.loadInitialHistory(from: storage, logger: logger))
    }

    /// 只在内存中记录（历史已锁定或密钥尚未就绪，E8 ①）：空历史，不写盘、不读盘，之后可 unlock
    public init(inMemoryWithLimit limit: Int, now: @escaping () -> Date = Date.init) {
        blobs = InMemoryClipBlobStore()
        saver = nil
        self.limit = max(limit, 1)
        self.now = now
        history = .empty
        canPersist = false
        isInMemory = true
        buildSearchIndex()
    }

    private func adoptInitialLoad(_ loaded: InitialLoad) {
        canPersist = loaded.canPersist
        loadIssue = loaded.issue
        guard loaded.canPersist else {
            history = loaded.history
            buildSearchIndex()
            return
        }
        // 异常退出可能留下引用已删除文件的条目，启动时修正
        let repaired = Self.repairingMissingBlobs(loaded.history, blobs: blobs)
        history = repaired
        // 历史损坏时备份里的条目仍引用这些文件：本次运行一个都不删（E8 ④）
        allowsDiskCleanup = loaded.issue == nil
        if allowsDiskCleanup {
            removeOrphanedBlobs()
        }
        // 修复了条目或从旧格式迁移而来时，写回一次（后者同时写入新的格式版本号）
        if loaded.needsResave || repaired != loaded.history {
            saver?.schedule(repaired)
        }
        buildSearchIndex()
    }

    // MARK: - 变更操作

    /// 记录新内容（同步：摘要与 blob 写入都在主线程）；失败时返回 nil。
    /// linkTitle 是复制时随链接带来的网页标题，只有链接条目会保存（规则见 LinkTitle）
    @discardableResult
    public func record(_ content: ClipContent, source: SourceApp?, linkTitle: String? = nil) -> ClipItem? {
        do {
            return record(try Self.prepare(content, blobs: blobs), source: source, linkTitle: linkTitle)
        } catch {
            logger.error("Failed to record clipboard content: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 后台记录：摘要计算与 blob 写入在后台完成，回主线程后只做插入（大图不再卡主线程）。
    /// 多次调用按调用顺序入历史；去重、上限、撤销与文件权限与同步 record 相同。
    /// 返回的任务完成时给出新条目（失败为 nil），不关心结果时可忽略
    @discardableResult
    public func recordInBackground(
        _ content: ClipContent, source: SourceApp?, linkTitle: String? = nil
    ) -> Task<ClipItem?, Never> {
        recordInBackground(source: source, linkTitle: linkTitle) { blobs in
            try ClipStore.prepare(content, blobs: blobs)
        }
    }

    /// 后台记录剪贴板上的原始图片（只有 TIFF）：转码为 PNG、解析尺寸、检查大小也在后台完成，规则同上
    @discardableResult
    public func recordInBackground(_ image: RawImage, source: SourceApp?) -> Task<ClipItem?, Never> {
        recordInBackground(source: source) { blobs in try ClipStore.prepare(image, blobs: blobs) }
    }

    private func recordInBackground(
        source: SourceApp?,
        linkTitle: String? = nil,
        prepare: @escaping @Sendable (any ClipBlobStoring) throws -> PreparedClip
    ) -> Task<ClipItem?, Never> {
        let blobs = self.blobs
        let preparation = Task.detached(priority: .userInitiated) {
            Result { try prepare(blobs) }
        }
        let previous = pendingRecord
        let task = Task { [weak self] () -> ClipItem? in
            _ = await previous?.value
            let result = await preparation.value
            guard let self else { return nil }
            switch result {
            case .success(let prepared):
                return self.record(prepared, source: source, linkTitle: linkTitle)
            case .failure(ImageCaptureError.tooLarge(let bytes)):
                // 超过采集上限是预期内的忽略（与文本超限一致），不算错误
                self.logger.notice("Skipped an image over the capture limit (\(bytes) bytes)")
                return nil
            case .failure(let error):
                self.logger.error(
                    "Failed to prepare clipboard content: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        pendingRecord = task
        return task
    }

    /// 插入已准备好的内容。文件名按当前存储重新推出（准备期间可能已从内存切换到加密存储）；
    /// blob 若不在当前存储中（期间清空了历史或刚切换了存储）则补写，条目不会指向缺失的文件
    @discardableResult
    public func record(_ prepared: PreparedClip, source: SourceApp?, linkTitle: String? = nil) -> ClipItem? {
        do {
            let rebased = prepared.rebased(onto: blobs)
            for blob in [rebased.blob, rebased.thumbnail].compactMap(\.self) where !blobs.exists(blob.name) {
                try blobs.write(blob.data, name: blob.name)
            }
            let item = item(from: rebased, source: source, date: now(), linkTitle: linkTitle)
            apply(history.inserting(item, limit: limit, keeping: protectedIDs))
            return history.items.first
        } catch {
            logger.error("Failed to record clipboard content: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func promote(id: UUID) {
        apply(history.promoting(id: id, at: now()))
    }

    public func toggleFavorite(id: UUID) {
        apply(history.togglingFavorite(id: id))
    }

    /// 删除条目；其文件暂时保留，以便撤销
    public func remove(id: UUID) {
        guard let index = history.items.firstIndex(where: { $0.id == id }) else { return }
        let previous = lastRemoval
        lastRemoval = Removal(item: history.items[index], index: index)
        apply(history.removing(id: id))
        if let previous {
            removeUnreferencedBlobs(of: previous.item)
        }
    }

    /// 撤销最近一次删除，返回恢复后的条目（相同内容已被重新记录时返回现有条目）
    @discardableResult
    public func undoRemove() -> ClipItem? {
        guard let removal = lastRemoval else { return nil }
        lastRemoval = nil
        apply(history.restoring(removal.item, at: removal.index))
        // 合并到现有条目时，被删条目独有的文件不再需要
        removeUnreferencedBlobs(of: removal.item)
        return item(id: removal.item.id)
            ?? history.items.first { $0.contentHash == removal.item.contentHash }
    }

    /// 放弃撤销机会，清理被删除条目的文件
    public func discardUndo() {
        guard let removal = lastRemoval else { return }
        lastRemoval = nil
        removeUnreferencedBlobs(of: removal.item)
    }

    /// 清空历史（只保留收藏；protectedIDs 中未收藏的条目也会被清掉）
    public func clearHistory() {
        discardUndo()
        apply(history.removingNonFavorites())
    }

    /// 设置图片条目的识别文字（持久化走合并保存）；id 不存在（含已删除待撤销）、不是图片或值未变时忽略。
    /// 不改变条目位置，也不影响待撤销的删除
    public func setRecognizedText(_ text: String?, for id: UUID) {
        apply(history.settingRecognizedText(text, for: id))
    }

    /// 批量设置识别文字（回填时合并写盘，减少整份历史的重写次数）；规则同 setRecognizedText
    public func setRecognizedTexts(_ texts: [UUID: String]) {
        guard !texts.isEmpty else { return }
        apply(history.settingRecognizedTexts(texts))
    }

    /// 清除全部识别文字并写盘（关闭图片文字搜索时）。待撤销的条目一并清除，撤销后也不会带回旧文字
    public func clearRecognizedText() {
        updatePendingRemoval { $0.recognizedText == nil ? $0 : $0.withRecognizedText(nil) }
        apply(history.removingRecognizedText())
    }

    /// 改写待撤销的删除记录中的条目（位置不变）；没有待撤销的删除时什么也不做
    func updatePendingRemoval(_ transform: (ClipItem) -> ClipItem) {
        guard let removal = lastRemoval else { return }
        lastRemoval = Removal(item: transform(removal.item), index: removal.index)
    }

    public func setLimit(_ newLimit: Int) {
        limit = max(newLimit, 1)
        apply(history.trimmed(to: limit, keeping: protectedIDs))
    }

    // MARK: - 查询

    public func item(id: UUID) -> ClipItem? {
        history.items.first { $0.id == id }
    }

    /// 等待所有排队中的保存完成（退出应用前、测试中使用）
    public func flush() {
        saver?.flush()
    }

    // MARK: - 内部实现

    func apply(_ newHistory: ClipHistory) {
        guard newHistory != history else { return }
        // 先比较历史里记录的文件名（便宜），只为确实不再引用的原图推出缩略图名（加密存储中要算 HMAC）
        let referenced = newHistory.blobNames.union(lastRemoval?.item.blobNames ?? [])
        let orphaned = history.blobNames.subtracting(referenced)
        let orphanedImages = history.imageNames.intersection(orphaned)
        history = newHistory
        // 与 history 同步更新（只折叠新增或变化的条目），搜索不会看到过期数据
        searchIndex = searchIndex?.updated(for: newHistory.items)
        revision += 1

        // 文件同步删除，避免与后续写入同名文件产生竞争
        removeBlobs(orphaned.union(orphanedImages.map(blobs.thumbnailName(forImage:))))
        if canPersist {
            saver?.schedule(newHistory)
        }
    }

    /// 删除条目独有、已不再被历史或待撤销条目引用的文件（含其缩略图）
    func removeUnreferencedBlobs(of item: ClipItem) {
        let referenced = history.blobNames.union(lastRemoval?.item.blobNames ?? [])
        var names = Set(item.blobNames).subtracting(referenced)
        if let image = item.image, names.contains(image.name) {
            names.insert(blobs.thumbnailName(forImage: image.name))
        }
        removeBlobs(names)
    }

    /// 删除不再被历史或待撤销条目引用的文件（只用于不带缩略图的文件，如译后图片）
    func removeUnreferencedBlobs(_ names: [String]) {
        removeBlobs(Set(names).subtracting(history.blobNames).subtracting(lastRemoval?.item.blobNames ?? []))
    }

    /// 内存中的文件总可以删；磁盘上的只在可写盘且本次加载干净时删除——
    /// 只读模式下磁盘上的历史仍可能引用它们（文件名基于内容，可能与本次新记录同名），损坏时留给备份（E8 ④）
    func removeBlobs(_ names: Set<String>) {
        guard !names.isEmpty, !blobs.isPersistent || (canPersist && allowsDiskCleanup) else { return }
        let failed = blobs.remove(names)
        if !failed.isEmpty {
            logger.error("Failed to delete files: \(failed, privacy: .public)")
        }
    }

    private func item(from prepared: PreparedClip, source: SourceApp?, date: Date, linkTitle: String?) -> ClipItem {
        switch prepared.payload {
        case .text(let text):
            return textItem(text, formatsName: prepared.blob?.name, source: source, date: date, linkTitle: linkTitle)
        case .image(let width, let height, let digest):
            let name = prepared.blob?.name ?? ""
            return ClipItem(
                kind: .image,
                payload: .image(ImageRef(name: name, width: width, height: height)),
                source: source,
                createdAt: date,
                contentHash: ContentHasher.hash(imageDigest: digest)
            )
        case .files(let paths):
            return ClipItem(
                kind: .file,
                payload: .files(paths),
                source: source,
                createdAt: date,
                contentHash: ContentHasher.hash(filePaths: paths)
            )
        }
    }

    /// 标题再规范化一次（幂等），保证任何调用方传入的标题都满足 LinkTitle 的规则；非链接条目由 ClipItem 丢弃标题
    private func textItem(
        _ text: String, formatsName: String?, source: SourceApp?, date: Date, linkTitle: String?
    ) -> ClipItem {
        ClipItem(
            kind: ContentClassifier.kind(forText: text),
            payload: .text(text),
            source: source,
            createdAt: date,
            contentHash: ContentHasher.hash(text: text),
            formatsName: formatsName,
            linkTitle: LinkTitle.normalized(linkTitle, url: text)
        )
    }

    /// 删除历史与待撤销条目都不再引用的文件（只在干净加载后调用）
    func removeOrphanedBlobs() {
        do {
            let keep = history.storedBlobNames(in: blobs)
                .union(lastRemoval?.item.storedBlobNames(in: blobs) ?? [])
            let removed = try blobs.removeAll(except: keep)
            if !removed.isEmpty {
                logger.info("Removed \(removed.count) orphaned files")
            }
        } catch {
            logger.error("Failed to remove orphaned files: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 移除图片文件已丢失的条目；富文本格式丢失时退化为纯文本（其译文按富文本分段，一并丢弃）；
    /// 译后图片丢失时只丢弃该条译文，不动条目
    static func repairingMissingBlobs(_ history: ClipHistory, blobs: any ClipBlobStoring) -> ClipHistory {
        let items = history.items.compactMap { item in
            item.rewritingBlobNames { blobs.exists($0.name) ? $0.name : nil }
        }
        return items == history.items ? history : ClipHistory(items: items)
    }
}
