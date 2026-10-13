import Foundation

// MARK: - 准备阶段（可在任意线程）：计算摘要、写入 blob、生成缩略图，不碰历史

extension ClipStore {
    /// 原始图片先转码为 PNG（转码后才计算去重摘要、检查大小上限），其余同下
    public nonisolated static func prepare(_ image: RawImage, blobs: any ClipBlobStoring) throws -> PreparedClip {
        let normalized = try ImageNormalizer.normalize(image)
        // 缩略图直接从未压缩的 TIFF 生成，比再解码一遍刚压好的 PNG 快
        return try prepareImage(
            png: normalized.png, width: normalized.width, height: normalized.height,
            thumbnailSource: image.data, blobs: blobs)
    }

    /// 计算摘要、写入 blob（加密存储中为密文，内存存储中只在内存），图片另生成卡片缩略图
    public nonisolated static func prepare(_ content: ClipContent, blobs: any ClipBlobStoring) throws -> PreparedClip {
        switch content {
        case .text(let text):
            return PreparedClip(payload: .text(text), blob: nil)
        case .richText(let text, let formats):
            let data = try RichFormats.encode(formats)
            let blob = PreparedClip.Blob(kind: .formats, contentHash: ContentHasher.sha256(data), data: data, in: blobs)
            try blobs.write(data, name: blob.name)
            return PreparedClip(payload: .text(text), blob: blob)
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
        blobs: any ClipBlobStoring
    ) throws -> PreparedClip {
        let digest = ContentHasher.sha256(png)
        let blob = PreparedClip.Blob(kind: .image, contentHash: digest, data: png, in: blobs)
        try blobs.write(png, name: blob.name)
        let ref = ImageRef(name: blob.name, width: width, height: height)
        return PreparedClip(
            payload: .image(width: width, height: height, digest: digest),
            blob: blob,
            thumbnail: prepareThumbnail(for: ref, source: thumbnailSource, blobs: blobs)
        )
    }
}

/// 已在后台准备好的剪贴板内容：摘要已算好、blob 已写入，入历史只剩插入
public struct PreparedClip: Sendable {
    enum Payload: Sendable {
        /// 文本；有富文本格式时 blob 即格式文件
        case text(String)
        /// 图片；blob 即原图
        case image(width: Int, height: Int, digest: String)
        case files([String])
    }

    /// 需要存在的 blob 及其内容（入历史时若已被删除则补写）。
    /// 记下种类与内容哈希：入历史时若已换了存储（锁定 → 解锁），据此在新存储中重新推出文件名
    struct Blob: Sendable {
        let kind: ClipBlobKind
        /// 用于推出文件名的内容哈希；缩略图为原图的文件名
        let contentHash: String
        let name: String
        let data: Data

        init(kind: ClipBlobKind, contentHash: String, data: Data, in blobs: any ClipBlobStoring) {
            self.kind = kind
            self.contentHash = contentHash
            self.data = data
            name = blobs.name(kind: kind, contentHash: contentHash)
        }
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

    /// 在 blobs 中的文件名（准备时用的存储可能已被替换）；缩略图名随原图的新名推出
    func rebased(onto blobs: any ClipBlobStoring) -> PreparedClip {
        let blob = blob.map { Blob(kind: $0.kind, contentHash: $0.contentHash, data: $0.data, in: blobs) }
        let thumbnail = thumbnail.flatMap { thumbnail in
            blob.map { Blob(kind: .thumbnail, contentHash: $0.name, data: thumbnail.data, in: blobs) }
        }
        return PreparedClip(payload: payload, blob: blob, thumbnail: thumbnail)
    }
}
