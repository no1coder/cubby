import Foundation
import os

extension ClipItem {
    /// 条目在 blob 目录里占用的全部文件：历史中记录的（原图、富文本格式），加上由原图名推出的卡片缩略图。
    /// 缩略图不写入历史，删除 / 撤销 / 清空 / 淘汰 / 孤儿清理都按这个集合处理，缩略图与原图同进退
    var storedBlobNames: [String] {
        guard let image else { return blobNames }
        return blobNames + [ImageThumbnail.name(forImage: image.name)]
    }
}

extension ClipHistory {
    var storedBlobNames: Set<String> {
        Set(items.flatMap(\.storedBlobNames))
    }
}

extension ClipStore {
    /// 启动后等这么久再回填，避开启动与搜索索引构建
    public nonisolated static let thumbnailBackfillDelay: Duration = .seconds(10)

    private nonisolated static let thumbnailLogger = Logger(
        subsystem: "io.github.no1coder.Cubby", category: "Thumbnails")

    /// 准备阶段（后台）由原图数据生成卡片缩略图。同一张图再次复制时沿用已有文件；生成或写入失败只记日志，不影响记录
    nonisolated static func prepareThumbnail(for ref: ImageRef, source: Data, blobs: BlobStore) -> PreparedClip.Blob? {
        guard ImageThumbnail.isNeeded(width: ref.width, height: ref.height) else { return nil }
        let name = ImageThumbnail.name(forImage: ref.name)
        if blobs.exists(name), let existing = try? blobs.read(name) {
            return PreparedClip.Blob(name: name, data: existing)
        }
        guard let data = ImageThumbnail.make(fromImageData: source, width: ref.width, height: ref.height) else {
            thumbnailLogger.info("Image could not be decoded, recorded without a thumbnail")
            return nil
        }
        do {
            try blobs.write(data, name: name)
            return PreparedClip.Blob(name: name, data: data)
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
        guard canPersist else { return Task { 0 } }
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
            guard isReferenced(ref), let url = blobs.url(for: ref.name) else { continue }
            let name = ImageThumbnail.name(forImage: ref.name)
            guard await Self.writeThumbnail(name: name, forImageAt: url, ref: ref, blobs: blobs) else { continue }
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

    /// 在后台线程解码原图、生成并写入缩略图（0600）；已存在、原图无法解码或写入失败时返回 false
    @concurrent
    private nonisolated static func writeThumbnail(
        name: String,
        forImageAt url: URL,
        ref: ImageRef,
        blobs: BlobStore
    ) async -> Bool {
        guard !blobs.exists(name),
            let data = ImageThumbnail.make(fromImageAt: url, width: ref.width, height: ref.height)
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
