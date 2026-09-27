import Foundation
import os

// MARK: - 译文缓存（docs/CLIP-TRANSLATION-DESIGN.md §2.3、§2.4）

extension ClipStore {
    private nonisolated static let translationLogger = Logger(
        subsystem: "io.github.no1coder.Cubby", category: "ClipTranslation")

    /// 写入一条文本译文（持久化走合并保存，译文全部到达后调用一次）。规则见 ClipHistory.settingTranslation：
    /// 条目不存在（含已删除待撤销）、类型不支持、超过单语言上限或值未变时不写入。
    /// 返回该译文此刻是否在缓存中；未写入且带译后图片时，删除不再被引用的图片文件
    @discardableResult
    public func setTranslation(_ translation: ClipTranslation, for id: UUID) -> Bool {
        apply(history.settingTranslation(translation, for: id))
        let isStored = item(id: id)?.translations?.entry(for: translation.target) == translation
        if !isStored, let name = translation.imageName {
            removeUnreferencedBlobs([name])
        }
        return isStored
    }

    /// 写入一条图片译文：后台把译后 PNG（带 DPI）写入 blob 目录（文件名为内容哈希，0600），回主线程后写入缓存；
    /// translation.imageName 被替换为该文件名。返回已缓存的译文；未能缓存时返回 nil，且不留下没有主人的文件
    @discardableResult
    public func setTranslation(_ translation: ClipTranslation, imagePNG png: Data, for id: UUID) async
        -> ClipTranslation?
    {
        let blobs = self.blobs
        guard let name = await Self.writeTranslatedImage(png, blobs: blobs) else { return nil }
        // 写入期间，同名文件可能随另一个被删除的条目一起删掉（同一张图存为了新条目）：补写
        if !blobs.exists(name) {
            guard (try? blobs.write(png, name: name)) != nil else { return nil }
        }
        let stored = translation.withImageName(name)
        return setTranslation(stored, for: id) ? stored : nil
    }

    /// 清除全部译文并写盘（设置里的「清除全部译文」）。待撤销的条目一并清除，撤销后不会带回旧译文；
    /// 译后图片随之删除（仍被其他条目引用的除外）
    public func clearTranslations() {
        let pendingImages = lastRemoval?.item.translatedImageNames ?? []
        updatePendingRemoval { $0.translations == nil ? $0 : $0.withTranslations(nil) }
        apply(history.removingTranslations())
        removeUnreferencedBlobs(pendingImages)
    }

    /// 译后图片的文件地址；文本译文或文件名非法时为 nil
    public func translatedImageURL(for translation: ClipTranslation) -> URL? {
        translation.imageName.flatMap { blobs.url(for: $0) }
    }

    /// 在后台线程写入译后 PNG，返回文件名；写入失败返回 nil
    @concurrent
    private nonisolated static func writeTranslatedImage(_ png: Data, blobs: BlobStore) async -> String? {
        let name = ContentHasher.sha256(png) + ".png"
        do {
            try blobs.write(png, name: name)
            return name
        } catch {
            translationLogger.error("Failed to write translated image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension ClipItem {
    /// 启动修复：丢弃译后图片已丢失的译文（例如降级到不认识译文的版本时被当作孤立文件删掉）；全部丢弃时为 nil
    func repairingTranslations(blobExists: (String) -> Bool) -> ClipItem {
        guard let entries = translations?.entries else { return self }
        let intact = entries.filter { $0.imageName.map(blobExists) ?? true }
        guard intact.count != entries.count || intact.isEmpty else { return self }
        return withTranslations(intact.isEmpty ? nil : ClipTranslations(intact))
    }
}
