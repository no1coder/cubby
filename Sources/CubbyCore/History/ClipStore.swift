import Foundation
import Observation
import os

/// 剪贴板历史的状态中心：负责条目创建、状态变更、撤销、持久化与 blob 文件清理
@MainActor
@Observable
public final class ClipStore {
    /// 可撤销的删除记录
    public struct Removal: Equatable, Sendable {
        public let item: ClipItem
        public let index: Int
    }

    public private(set) var history: ClipHistory
    public private(set) var limit: Int
    /// 每次历史变化递增，视图层可据此做缓存失效
    public private(set) var revision = 0
    /// 最近一次删除，可通过 undoRemove() 恢复
    public private(set) var lastRemoval: Removal?
    /// 读取失败（非损坏）或历史文件来自更新版本时为 false：本次运行不写盘、不删除 blob，避免覆盖已有数据
    public let canPersist: Bool
    /// 启动加载时遇到的问题（nil 表示正常），界面据此提示原因
    public private(set) var loadIssue: LoadIssue?

    @ObservationIgnored let blobs: BlobStore
    @ObservationIgnored private let saver: CoalescingSaver
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "ClipStore")
    /// 最近一次后台记录：后续的后台记录等它入历史后再入，保证按调用顺序
    @ObservationIgnored private var pendingRecord: Task<ClipItem?, Never>?
    /// 搜索索引：加载后在后台构建（见 ClipStore+Search），之后每次历史变化时与 history 在同一处同步增量更新；
    /// nil 表示尚未就绪（搜索退回逐条匹配，结果相同）
    @ObservationIgnored public internal(set) var searchIndex: ClipSearchIndex?
    @ObservationIgnored var searchIndexTask: Task<Void, Never>?
    /// 旧条目缩略图回填（见 ClipStore+Thumbnails）
    @ObservationIgnored var thumbnailBackfill: Task<Int, Never>?

    public init(
        storage: HistoryPersisting,
        blobs: BlobStore,
        limit: Int,
        now: @escaping () -> Date = Date.init
    ) {
        self.blobs = blobs
        self.saver = CoalescingSaver(storage: storage)
        self.limit = max(limit, 1)
        self.now = now

        let loaded = Self.loadInitialHistory(from: storage, logger: logger)
        self.canPersist = loaded.canPersist
        self.loadIssue = loaded.issue
        guard loaded.canPersist else {
            self.history = loaded.history
            buildSearchIndex()
            return
        }
        // 异常退出可能留下引用已删除文件的条目，启动时修正
        let repaired = Self.repairingMissingBlobs(loaded.history, blobs: blobs)
        self.history = repaired
        removeOrphanedBlobs()
        // 修复了条目或从旧格式迁移而来时，写回一次（后者同时写入新的格式版本号）
        if loaded.needsResave || repaired != loaded.history {
            saver.schedule(repaired)
        }
        buildSearchIndex()
    }

    // MARK: - 变更操作

    /// 记录新内容（同步：摘要与 blob 写入都在主线程）；失败时返回 nil
    @discardableResult
    public func record(_ content: ClipContent, source: SourceApp?) -> ClipItem? {
        do {
            return record(try Self.prepare(content, blobs: blobs), source: source)
        } catch {
            logger.error("Failed to record clipboard content: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 后台记录：摘要计算与 blob 写入在后台完成，回主线程后只做插入（大图不再卡主线程）。
    /// 多次调用按调用顺序入历史；去重、上限、撤销与文件权限与同步 record 相同。
    /// 返回的任务完成时给出新条目（失败为 nil），不关心结果时可忽略
    @discardableResult
    public func recordInBackground(_ content: ClipContent, source: SourceApp?) -> Task<ClipItem?, Never> {
        recordInBackground(source: source) { blobs in try ClipStore.prepare(content, blobs: blobs) }
    }

    /// 后台记录剪贴板上的原始图片（只有 TIFF）：转码为 PNG、解析尺寸、检查大小也在后台完成，规则同上
    @discardableResult
    public func recordInBackground(_ image: RawImage, source: SourceApp?) -> Task<ClipItem?, Never> {
        recordInBackground(source: source) { blobs in try ClipStore.prepare(image, blobs: blobs) }
    }

    private func recordInBackground(
        source: SourceApp?,
        prepare: @escaping @Sendable (BlobStore) throws -> PreparedClip
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
                return self.record(prepared, source: source)
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

    /// 插入已准备好的内容；blob 若在准备后被删除（例如期间清空了历史）则补写，条目不会指向缺失的文件
    @discardableResult
    public func record(_ prepared: PreparedClip, source: SourceApp?) -> ClipItem? {
        do {
            for blob in [prepared.blob, prepared.thumbnail].compactMap(\.self) where !blobs.exists(blob.name) {
                try blobs.write(blob.data, name: blob.name)
            }
            apply(history.inserting(item(from: prepared, source: source, date: now()), limit: limit))
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
            removeUnreferencedBlobs(previous.item.storedBlobNames)
        }
    }

    /// 撤销最近一次删除，返回恢复后的条目（相同内容已被重新记录时返回现有条目）
    @discardableResult
    public func undoRemove() -> ClipItem? {
        guard let removal = lastRemoval else { return nil }
        lastRemoval = nil
        apply(history.restoring(removal.item, at: removal.index))
        // 合并到现有条目时，被删条目独有的文件不再需要
        removeUnreferencedBlobs(removal.item.storedBlobNames)
        return item(id: removal.item.id)
            ?? history.items.first { $0.contentHash == removal.item.contentHash }
    }

    /// 放弃撤销机会，清理被删除条目的文件
    public func discardUndo() {
        guard let removal = lastRemoval else { return }
        lastRemoval = nil
        removeUnreferencedBlobs(removal.item.storedBlobNames)
    }

    /// 清空历史（保留收藏）
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
        apply(history.trimmed(to: limit))
    }

    // MARK: - 查询

    public func item(id: UUID) -> ClipItem? {
        history.items.first { $0.id == id }
    }

    public func imageURL(for item: ClipItem) -> URL? {
        item.image.flatMap { blobs.url(for: $0.name) }
    }

    /// 读取条目的富文本格式；没有或读取失败时返回空字典（退化为纯文本）
    public func formats(for item: ClipItem) -> [String: Data] {
        guard let name = item.formatsName else { return [:] }
        do {
            return try RichFormats.decode(blobs.read(name))
        } catch {
            logger.error("Failed to read rich text formats: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// 等待所有排队中的保存完成（退出应用前、测试中使用）
    public func flush() {
        saver.flush()
    }

    // MARK: - 内部实现

    func apply(_ newHistory: ClipHistory) {
        guard newHistory != history else { return }
        let protected = Set(lastRemoval?.item.storedBlobNames ?? [])
        let orphaned = history.storedBlobNames.subtracting(newHistory.storedBlobNames).subtracting(protected)
        history = newHistory
        // 与 history 同步更新（只折叠新增或变化的条目），搜索不会看到过期数据
        searchIndex = searchIndex?.updated(for: newHistory.items)
        revision += 1

        // 文件同步删除，避免与后续写入同名文件产生竞争
        removeBlobs(orphaned)
        if canPersist {
            saver.schedule(newHistory)
        }
    }

    /// 删除不再被历史或待撤销条目引用的文件
    func removeUnreferencedBlobs(_ names: [String]) {
        let protected = Set(lastRemoval?.item.storedBlobNames ?? [])
        removeBlobs(Set(names).subtracting(history.storedBlobNames).subtracting(protected))
    }

    func removeBlobs(_ names: Set<String>) {
        // 只读模式下磁盘上的历史仍可能引用这些文件（文件名基于内容哈希，可能与本次新记录同名），一律保留
        guard canPersist, !names.isEmpty else { return }
        let failed = blobs.remove(names)
        if !failed.isEmpty {
            logger.error("Failed to delete files: \(failed, privacy: .public)")
        }
    }

    /// 准备阶段（可在任意线程）：原始图片先转码为 PNG（转码后才计算去重摘要、检查大小上限），其余同下
    public nonisolated static func prepare(_ image: RawImage, blobs: BlobStore) throws -> PreparedClip {
        let normalized = try ImageNormalizer.normalize(image)
        // 缩略图直接从未压缩的 TIFF 生成，比再解码一遍刚压好的 PNG 快
        return try prepareImage(
            png: normalized.png, width: normalized.width, height: normalized.height,
            thumbnailSource: image.data, blobs: blobs)
    }

    /// 准备阶段（可在任意线程）：计算摘要、写入 blob（权限 0600），图片另生成卡片缩略图；不碰历史
    public nonisolated static func prepare(_ content: ClipContent, blobs: BlobStore) throws -> PreparedClip {
        switch content {
        case .text(let text):
            return PreparedClip(payload: .text(text, formatsName: nil), blob: nil)
        case .richText(let text, let formats):
            let data = try RichFormats.encode(formats)
            let name = ContentHasher.sha256(data) + ".formats"
            try blobs.write(data, name: name)
            return PreparedClip(payload: .text(text, formatsName: name), blob: .init(name: name, data: data))
        case .image(let png, let width, let height):
            return try prepareImage(png: png, width: width, height: height, thumbnailSource: png, blobs: blobs)
        case .files(let urls):
            return PreparedClip(payload: .files(urls.map(\.path)), blob: nil)
        }
    }

    /// 图片：摘要按 PNG 计算（去重），写入原图，再由 thumbnailSource 生成卡片缩略图
    private nonisolated static func prepareImage(
        png: Data,
        width: Int,
        height: Int,
        thumbnailSource: Data,
        blobs: BlobStore
    ) throws -> PreparedClip {
        let digest = ContentHasher.sha256(png)
        let name = digest + ".png"
        try blobs.write(png, name: name)
        let ref = ImageRef(name: name, width: width, height: height)
        return PreparedClip(
            payload: .image(ref, digest: digest),
            blob: .init(name: name, data: png),
            thumbnail: prepareThumbnail(for: ref, source: thumbnailSource, blobs: blobs)
        )
    }

    private func item(from prepared: PreparedClip, source: SourceApp?, date: Date) -> ClipItem {
        switch prepared.payload {
        case .text(let text, let formatsName):
            return textItem(text, formatsName: formatsName, source: source, date: date)
        case .image(let ref, let digest):
            return ClipItem(
                kind: .image,
                payload: .image(ref),
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

    private func textItem(_ text: String, formatsName: String?, source: SourceApp?, date: Date) -> ClipItem {
        ClipItem(
            kind: ContentClassifier.kind(forText: text),
            payload: .text(text),
            source: source,
            createdAt: date,
            contentHash: ContentHasher.hash(text: text),
            formatsName: formatsName
        )
    }

    private func removeOrphanedBlobs() {
        do {
            // 在用图片的缩略图不在历史里记录，按原图名推出后一并保留
            let removed = try blobs.removeAll(except: history.storedBlobNames)
            if !removed.isEmpty {
                logger.info("Removed \(removed.count) orphaned files")
            }
        } catch {
            logger.error("Failed to remove orphaned files: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 移除图片文件已丢失的条目；富文本格式丢失时退化为纯文本（其译文按富文本分段，一并丢弃）；
    /// 译后图片丢失时只丢弃该条译文，不动条目
    private static func repairingMissingBlobs(_ history: ClipHistory, blobs: BlobStore) -> ClipHistory {
        let items = history.items.compactMap { item -> ClipItem? in
            if let image = item.image, !blobs.exists(image.name) { return nil }
            if let formatsName = item.formatsName, !blobs.exists(formatsName) {
                return item.withFormatsName(nil).withTranslations(nil)
            }
            return item.repairingTranslations(blobExists: blobs.exists)
        }
        return items == history.items ? history : ClipHistory(items: items)
    }
}

/// 已在后台准备好的剪贴板内容：摘要已算好、blob 已写入，入历史只剩插入
public struct PreparedClip: Sendable {
    enum Payload: Sendable {
        case text(String, formatsName: String?)
        case image(ImageRef, digest: String)
        case files([String])
    }

    /// 需要存在的 blob 及其内容（入历史时若已被删除则补写）
    struct Blob: Sendable {
        let name: String
        let data: Data
    }

    let payload: Payload
    let blob: Blob?
    /// 图片的卡片缩略图（原图不大或无法生成时为 nil）
    let thumbnail: Blob?

    init(payload: Payload, blob: Blob?, thumbnail: Blob? = nil) {
        self.payload = payload
        self.blob = blob
        self.thumbnail = thumbnail
    }

    /// blob 文件名（图片、富文本格式）；纯文本与文件为 nil
    public var blobName: String? {
        blob?.name
    }

    /// 缩略图文件名；没有生成缩略图时为 nil
    public var thumbnailName: String? {
        thumbnail?.name
    }
}
