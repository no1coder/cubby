import Foundation
import os

extension ClipStore {
    /// 在后台生成并写入缩略图：缩略图名、原图引用、存储；返回是否新写入了文件
    typealias ThumbnailWriter = @concurrent @Sendable (String, ImageRef, any ClipBlobStoring) async -> Bool

    /// 启动后等这么久再回填，避开启动与搜索索引构建
    public nonisolated static let thumbnailBackfillDelay: Duration = .seconds(10)

    private nonisolated static let thumbnailLogger = Logger(
        subsystem: "io.github.no1coder.Cubby", category: "Thumbnails")

    /// 准备阶段（后台）由原图数据生成卡片缩略图。同一张图再次复制时沿用已有文件；生成或写入失败只记日志，不影响记录
    nonisolated static func prepareThumbnail(
        for ref: ImageRef, source: Data, blobs: any ClipBlobStoring
    ) -> PreparedClip.Blob? {
        guard ImageThumbnail.isNeeded(width: ref.width, height: ref.height) else { return nil }
        let name = blobs.thumbnailName(forImage: ref.name)
        if blobs.exists(name), let existing = try? blobs.data(name) {
            return PreparedClip.Blob(kind: .thumbnail, contentHash: ref.name, data: existing, in: blobs)
        }
        guard let data = ImageThumbnail.make(fromImageData: source, width: ref.width, height: ref.height) else {
            thumbnailLogger.info("Image could not be decoded, recorded without a thumbnail")
            return nil
        }
        do {
            try blobs.write(data, name: name)
            return PreparedClip.Blob(kind: .thumbnail, contentHash: ref.name, data: data, in: blobs)
        } catch {
            thumbnailLogger.error("Failed to write thumbnail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 为旧版本记录、还没有缩略图的图片补生成：等待 delay 后在低优先级任务里逐张串行生成
    /// （每张 5K 图 70–150ms 的解码在后台线程）。生成后回到主线程确认图片仍被历史或待撤销的删除引用，
    /// 已被删除的不留下文件。再次调用会取消上一次；只读模式不回填。任务结果为生成的数量
    @discardableResult
    public func backfillThumbnails(after delay: Duration = thumbnailBackfillDelay) -> Task<Int, Never> {
        thumbnailBackfill?.cancel()
        guard canPersist, !isInMemory else { return Task { 0 } }
        let task = Task(priority: .background) { [weak self] () -> Int in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return 0
            }
            return await self?.runThumbnailBackfill() ?? 0
        }
        thumbnailBackfill = task
        return task
    }

    private func runThumbnailBackfill() async -> Int {
        let clock = ContinuousClock()
        let start = clock.now
        let candidates = history.items.compactMap(\.image).filter {
            ImageThumbnail.isNeeded(width: $0.width, height: $0.height)
        }
        var created = 0
        for ref in candidates {
            guard !Task.isCancelled else { break }
            guard isReferenced(ref) else { continue }
            let name = blobs.thumbnailName(forImage: ref.name)
            guard await thumbnailWriter(name, ref, blobs) else { continue }
            // 生成期间图片可能已被删除（其文件随之删除）：此时刚写入的缩略图没有主人，立即清理
            if isReferenced(ref) {
                created += 1
            } else {
                removeBlobs([name])
            }
        }
        if created > 0 {
            let elapsed = clock.now - start
            Self.thumbnailLogger.info("Backfilled \(created) thumbnails in \(elapsed, privacy: .public)")
        }
        return created
    }

    /// 图片仍在历史中，或属于可撤销的删除
    private func isReferenced(_ ref: ImageRef) -> Bool {
        lastRemoval?.item.image?.name == ref.name || history.items.contains { $0.image?.name == ref.name }
    }

    /// 在后台线程读取（解密）原图、生成并写入缩略图；已存在、原图无法读取或解码、写入失败时返回 false
    @concurrent
    nonisolated static func writeThumbnail(
        name: String,
        ref: ImageRef,
        blobs: any ClipBlobStoring
    ) async -> Bool {
        guard !blobs.exists(name) else { return false }
        let original: Data
        do {
            original = try blobs.data(ref.name)
        } catch {
            thumbnailLogger.error(
                "Failed to read an image for its thumbnail: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let data = ImageThumbnail.make(fromImageData: original, width: ref.width, height: ref.height)
        else { return false }
        do {
            try blobs.write(data, name: name)
            return true
        } catch {
            thumbnailLogger.error("Failed to write thumbnail: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
