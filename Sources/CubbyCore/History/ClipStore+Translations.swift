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

    /// 写入一条图片译文：后台把译后 PNG（带 DPI）写入存储（文件名由内容推出），回主线程后写入缓存；
    /// translation.imageName 被替换为该文件名。返回已缓存的译文；未能缓存时返回 nil，且不留下没有主人的文件
    @discardableResult
    public func setTranslation(_ translation: ClipTranslation, imagePNG png: Data, for id: UUID) async
        -> ClipTranslation?
    {
        let digest = ContentHasher.sha256(png)
        guard await Self.writeTranslatedImage(png, digest: digest, blobs: blobs) else { return nil }
        // 写入期间，同名文件可能随另一个被删除的条目一起删掉（同一张图存为了新条目），
        // 或存储已从内存切换为加密存储：按当前存储重新推出文件名，不在时补写
        let name = blobs.name(kind: .translatedImage, contentHash: digest)
        if !blobs.exists(name) {
            do {
                try blobs.write(png, name: name)
            } catch {
                Self.translationLogger.error(
                    "Failed to write translated image: \(error.localizedDescription, privacy: .public)")
                return nil
            }
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

    /// 译后图片的数据来源；文本译文为 nil
    public func translatedImageSource(for translation: ClipTranslation) -> ClipImageSource? {
        translation.imageName.map { ClipImageSource(name: $0, blobs: blobs, hasThumbnail: false) }
    }

    /// 在后台线程写入译后 PNG；写入失败返回 false
    @concurrent
    private nonisolated static func writeTranslatedImage(
        _ png: Data, digest: String, blobs: any ClipBlobStoring
    ) async -> Bool {
        do {
            try blobs.write(png, name: blobs.name(kind: .translatedImage, contentHash: digest))
            return true
        } catch {
            translationLogger.error("Failed to write translated image: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
