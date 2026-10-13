import Foundation
import os

// MARK: - 从内存模式切换到加密存储（E8 ① 重试成功、启动时密钥就绪）

extension ClipStore {
    /// unlock 的结果
    public enum UnlockOutcome: Equatable, Sendable {
        /// 已切换为写盘：内存条目已并入加密历史并保存
        case unlocked
        /// 已切换，但合并后的历史没能保存：本次运行不清理磁盘上的文件，之后的变化照常尝试写盘
        case unlockedWithoutSaving
        /// 加密历史读不了（更新版本写入、读取错误）：保持内存模式，loadIssue 说明原因
        case readOnly
        /// 本来就不在内存模式，什么也不做
        case alreadyPersistent
    }

    /// 读入加密历史，把内存中的条目（及其图片）并入，然后开启写盘。顺序固定（E8 ①）：
    /// ① 读取 storage；② 把内存图片按新存储的文件名写入 target、改写条目引用；③ 按 HistoryMerge 的规则合并
    /// （内存里没有条目时不合并、不裁剪）；④ 切换存储、开启写盘，有变化时同步保存；⑤ 只有读取干净且保存成功后才清理孤儿文件
    @discardableResult
    public func unlock(storage: HistoryPersisting, blobs target: any ClipBlobStoring) -> UnlockOutcome {
        guard isInMemory else { return .alreadyPersistent }
        let loaded = Self.loadInitialHistory(from: storage, logger: logger)
        guard loaded.canPersist else {
            loadIssue = loaded.issue
            return .readOnly
        }
        let source = blobs
        let incoming = history.items.compactMap { Self.transfer($0, from: source, to: target, logger: logger) }
        let removal = lastRemoval.flatMap { removal in
            Self.transfer(removal.item, from: source, to: target, logger: logger)
                .map { Removal(item: $0, index: removal.index) }
        }
        let base = Self.repairingMissingBlobs(loaded.history, blobs: target)
        // 内存里没有新条目时原样采用磁盘上的历史：不重排、不按上限裁剪（与旧版本启动时一样，上限在下次记录时生效）
        let merged =
            incoming.isEmpty
            ? base : HistoryMerge.merging(base: base, incoming: incoming, limit: limit, keeping: protectedIDs)
        let needsSave = merged != loaded.history || loaded.needsResave
        let saved = needsSave ? save(merged, to: storage) : true
        blobs = target
        saver = CoalescingSaver(storage: storage)
        canPersist = true
        isInMemory = false
        loadIssue = loaded.issue
        allowsDiskCleanup = saved && loaded.issue == nil
        lastRemoval = removal
        history = merged
        revision += 1
        buildSearchIndex()
        if allowsDiskCleanup {
            removeOrphanedBlobs()
        }
        // 内存存储的 removeAll 不会失败
        _ = try? source.removeAll(except: [])
        logger.info("Unlocked history: merged \(incoming.count) items recorded in memory")
        return saved ? .unlocked : .unlockedWithoutSaving
    }

    private func save(_ history: ClipHistory, to storage: HistoryPersisting) -> Bool {
        do {
            try storage.save(history)
            return true
        } catch {
            logger.error("Failed to save the merged history: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 把条目引用的内存文件写进 target（按 target 的规则重新命名，图片连同缩略图），返回改写引用后的条目；
    /// 原图读不到时丢弃整条（规则同启动修复）。已是 target 的文件名（不是内存名）且存在时原样保留
    nonisolated static func transfer(
        _ item: ClipItem,
        from source: any ClipBlobStoring,
        to target: any ClipBlobStoring,
        logger: Logger
    ) -> ClipItem? {
        item.rewritingBlobNames { reference in
            guard let parsed = InMemoryClipBlobStore.parse(reference.name) else {
                return target.exists(reference.name) ? reference.name : nil
            }
            let name = target.name(kind: parsed.kind, contentHash: parsed.contentHash)
            do {
                if !target.exists(name) { try target.write(source.data(reference.name), name: name) }
                if reference.kind == .image {
                    try copyThumbnail(of: reference.name, as: name, from: source, to: target)
                }
                return name
            } catch {
                logger.error("Failed to move a file out of memory: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private nonisolated static func copyThumbnail(
        of sourceImage: String, as targetImage: String, from source: any ClipBlobStoring, to target: any ClipBlobStoring
    ) throws {
        let targetName = target.thumbnailName(forImage: targetImage)
        guard !target.exists(targetName), let data = source.thumbnailData(forImage: sourceImage) else { return }
        try target.write(data, name: targetName)
    }
}
