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
    /// ① 后台：读取 storage、把内存图片按新存储的文件名写入 target、合并（不裁剪，重复条目沿用内存中的 id）、
    ///    有变化时保存、只有读取干净且保存成功后才清理孤儿文件；
    /// ② 主线程：把期间发生的变化（新记录、删除、收藏……）在同一个基础上重新合并，切换存储并开启写盘。
    /// 期间到来的后台记录排队，等切换后直接写进加密存储。
    /// - Parameter knownCorruption: 启动前的步骤（迁移、还原）已发现历史损坏并移入 Backups 的位置：
    ///   按「从损坏中恢复」报告，本次运行不清理文件（那些文件可能只被损坏的备份引用，E8 ④）
    @discardableResult
    public func unlock(
        storage: HistoryPersisting, blobs target: any ClipBlobStoring, knownCorruption: URL? = nil
    ) async -> UnlockOutcome {
        if let unlocking { return await unlocking.value }
        guard isInMemory else { return .alreadyPersistent }
        // 在任务内部清掉 unlocking（同在主线程）：等待它的后台记录醒来时一定看到 nil，不会对已完成的任务空转
        let task = Task { () -> UnlockOutcome in
            let outcome = await performUnlock(storage: storage, target: target, knownCorruption: knownCorruption)
            unlocking = nil
            return outcome
        }
        unlocking = task
        return await task.value
    }

    private func performUnlock(
        storage: HistoryPersisting, target: any ClipBlobStoring, knownCorruption: URL?
    ) async -> UnlockOutcome {
        let source = blobs
        let snapshot = UnlockSnapshot(
            items: history.items, removal: lastRemoval, revision: revision, knownCorruption: knownCorruption)
        let outcome = await Self.prepareUnlock(
            snapshot, storage: storage, source: source, target: target, logger: logger)
        guard case .ready(let prepared) = outcome else {
            if case .readOnly(let issue) = outcome { loadIssue = issue }
            return .readOnly
        }
        // 后台读写期间内存里又有变化：以同一个基础重新合并（只有新的内存文件需要加密写入）
        let final =
            revision == snapshot.revision
            ? prepared.merged : Self.merge(history.items, into: prepared.base, from: source, to: target, logger: logger)
        let removal =
            lastRemoval == snapshot.removal ? prepared.removal : Self.transfer(lastRemoval, source, target, logger)
        switchToPersistent(storage: storage, target: target, history: final, removal: removal, prepared: prepared)
        if final.history != prepared.merged.history || !prepared.saved {
            saver?.schedule(final.history)
        }
        // 内存存储的 removeAll 不会失败
        _ = try? source.removeAll(except: [])
        logger.info("Unlocked history: merged \(final.history.items.count) items")
        return prepared.saved ? .unlocked : .unlockedWithoutSaving
    }

    private func switchToPersistent(
        storage: HistoryPersisting, target: any ClipBlobStoring, history merged: HistoryMerge.Result,
        removal: Removal?, prepared: UnlockPreparation
    ) {
        blobs = target
        saver = CoalescingSaver(storage: storage)
        canPersist = true
        isInMemory = false
        loadIssue = prepared.issue
        allowsDiskCleanup = prepared.allowsCleanup
        lastRemoval = removal
        replacedItemIDs.merge(merged.replacedIDs) { _, new in new }
        history = merged.history
        revision += 1
        buildSearchIndex()
    }

    // MARK: - 后台准备

    /// 解锁开始时的内存状态
    struct UnlockSnapshot: Sendable {
        let items: [ClipItem]
        let removal: Removal?
        let revision: Int
        let knownCorruption: URL?
    }

    enum PrepareOutcome: Sendable {
        case ready(UnlockPreparation)
        /// 读不了（更新版本、读取错误）：保持内存模式
        case readOnly(LoadIssue?)
    }

    /// 后台准备的结果；base 是修复后的磁盘历史，供主线程在同一基础上重新合并
    struct UnlockPreparation: Sendable {
        let base: ClipHistory
        let merged: HistoryMerge.Result
        let removal: Removal?
        let issue: LoadIssue?
        let saved: Bool
        let allowsCleanup: Bool
    }

    /// 在后台执行器上：读取、搬运内存文件、合并、保存、清理
    @concurrent
    nonisolated static func prepareUnlock(
        _ snapshot: UnlockSnapshot, storage: HistoryPersisting, source: any ClipBlobStoring,
        target: any ClipBlobStoring, logger: Logger
    ) async -> PrepareOutcome {
        let loaded = loadInitialHistory(from: storage, logger: logger)
        guard loaded.canPersist else { return .readOnly(loaded.issue) }
        let base = repairingMissingBlobs(loaded.history, blobs: target)
        let merged = merge(snapshot.items, into: base, from: source, to: target, logger: logger)
        let removal = transfer(snapshot.removal, source, target, logger)
        let needsSave = merged.history != loaded.history || loaded.needsResave
        let saved = needsSave ? save(merged.history, to: storage, logger: logger) : true
        let issue = loaded.issue ?? snapshot.knownCorruption.map { LoadIssue.restoredFromCorruption(backupURL: $0) }
        let allowsCleanup = saved && issue == nil
        if allowsCleanup {
            let keep = merged.history.storedBlobNames(in: target)
                .union(removal?.item.storedBlobNames(in: target) ?? [])
            removeOrphans(in: target, keeping: keep, logger: logger)
        }
        return .ready(
            UnlockPreparation(
                base: base, merged: merged, removal: removal, issue: issue, saved: saved, allowsCleanup: allowsCleanup))
    }

    /// 把内存条目搬进 target 后并入 base；内存里没有条目时原样采用 base（不重排、不裁剪）
    nonisolated static func merge(
        _ items: [ClipItem], into base: ClipHistory, from source: any ClipBlobStoring,
        to target: any ClipBlobStoring, logger: Logger
    ) -> HistoryMerge.Result {
        let incoming = items.compactMap { transfer($0, from: source, to: target, logger: logger) }
        guard !incoming.isEmpty else { return HistoryMerge.Result(history: base, replacedIDs: [:]) }
        return HistoryMerge.merge(base: base, incoming: incoming, ids: .incoming)
    }

    private nonisolated static func transfer(
        _ removal: Removal?, _ source: any ClipBlobStoring, _ target: any ClipBlobStoring, _ logger: Logger
    ) -> Removal? {
        removal.flatMap { removal in
            transfer(removal.item, from: source, to: target, logger: logger).map {
                Removal(item: $0, index: removal.index)
            }
        }
    }

    private nonisolated static func save(_ history: ClipHistory, to storage: HistoryPersisting, logger: Logger) -> Bool
    {
        do {
            try storage.save(history)
            return true
        } catch {
            logger.error("Failed to save the merged history: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private nonisolated static func removeOrphans(
        in target: any ClipBlobStoring, keeping keep: Set<String>, logger: Logger
    ) {
        do {
            let removed = try target.removeAll(except: keep)
            if !removed.isEmpty { logger.info("Removed \(removed.count) orphaned files") }
        } catch {
            logger.error("Failed to remove orphaned files: \(error.localizedDescription, privacy: .public)")
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
