import Foundation

/// 条目引用的一个二进制文件：种类 + 文件名
public struct ClipBlobReference: Equatable, Hashable, Sendable {
    public let kind: ClipBlobKind
    public let name: String
}

extension ClipItem {
    /// 历史中记录的全部文件引用（原图、富文本格式、译后图片；缩略图不记录，由原图名推出）
    public var blobReferences: [ClipBlobReference] {
        var references: [ClipBlobReference] = []
        if let image { references.append(ClipBlobReference(kind: .image, name: image.name)) }
        if let formatsName { references.append(ClipBlobReference(kind: .formats, name: formatsName)) }
        references += translatedImageNames.map { ClipBlobReference(kind: .translatedImage, name: $0) }
        return references
    }

    /// 条目在存储里占用的全部文件：历史中记录的，加上由原图名推出的卡片缩略图。
    /// 删除 / 撤销 / 清空 / 淘汰 / 孤儿清理都按这个集合处理，缩略图与原图同进退
    func storedBlobNames(in blobs: any ClipBlobStoring) -> [String] {
        guard let image else { return blobNames }
        return blobNames + [blobs.thumbnailName(forImage: image.name)]
    }

    /// 按 resolve 改写全部文件引用（换存储、迁移时用）。resolve 返回新文件名；返回 nil 表示该文件已丢失，
    /// 按启动修复的规则处理：原图丢失 → 整条丢弃（返回 nil）；富文本格式丢失 → 退化为纯文本并丢弃译文；
    /// 译后图片丢失 → 只丢弃那一条译文
    func rewritingBlobNames(_ resolve: (ClipBlobReference) throws -> String?) rethrows -> ClipItem? {
        var item = self
        if let image {
            guard let name = try resolve(ClipBlobReference(kind: .image, name: image.name)) else { return nil }
            item = item.withPayload(.image(ImageRef(name: name, width: image.width, height: image.height)))
        }
        if let formatsName {
            if let name = try resolve(ClipBlobReference(kind: .formats, name: formatsName)) {
                item = item.withFormatsName(name)
            } else {
                return item.withFormatsName(nil).withTranslations(nil)
            }
        }
        guard let entries = item.translations?.entries else { return item }
        let rewritten = try entries.compactMap { entry -> ClipTranslation? in
            guard let imageName = entry.imageName else { return entry }
            let reference = ClipBlobReference(kind: .translatedImage, name: imageName)
            return try resolve(reference).map { entry.withImageName($0) }
        }
        return item.withTranslations(rewritten.isEmpty ? nil : ClipTranslations(rewritten))
    }

    /// 替换承载的数据，其余字段不变（只用于改写图片文件名）
    func withPayload(_ payload: ClipPayload) -> ClipItem {
        ClipItem(
            id: id, kind: kind, payload: payload, source: source, createdAt: createdAt,
            isFavorite: isFavorite, contentHash: contentHash, formatsName: formatsName, recognizedText: recognizedText,
            translations: translations, linkTitle: linkTitle)
    }
}

extension ClipHistory {
    func storedBlobNames(in blobs: any ClipBlobStoring) -> Set<String> {
        Set(items.flatMap { $0.storedBlobNames(in: blobs) })
    }
}
