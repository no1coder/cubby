import Foundation

// MARK: - 读取条目内容（E10：只有数据接口，不返回文件 URL）

extension ClipStore {
    /// 图片条目原图的数据来源（可交给后台解码 / 识别 / 导出）；不是图片时为 nil
    public func imageSource(for item: ClipItem) -> ClipImageSource? {
        item.image.map {
            ClipImageSource(
                name: $0.name, blobs: blobs, hasThumbnail: ImageThumbnail.isNeeded(width: $0.width, height: $0.height))
        }
    }

    /// 读取图片条目的原图（同步；大图请用 imageSource(for:)?.load() 在后台读取）。不是图片或读取失败时为 nil
    public func imageData(for item: ClipItem) -> Data? {
        guard let source = imageSource(for: item) else { return nil }
        do {
            return try source.data()
        } catch {
            logger.error("Failed to read an image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 读取条目的富文本格式；没有或读取失败时返回空字典（退化为纯文本）
    public func formats(for item: ClipItem) -> [String: Data] {
        guard let name = item.formatsName else { return [:] }
        do {
            return try RichFormats.decode(blobs.data(name))
        } catch {
            logger.error("Failed to read rich text formats: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}

extension ClipStore {
    /// 存储中是否有该文件（如译后图片仍在，缓存可用）
    public func blobExists(_ name: String) -> Bool {
        blobs.exists(name)
    }
}
