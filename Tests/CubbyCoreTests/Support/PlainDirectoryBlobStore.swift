import Foundation
@testable import CubbyCore

/// 测试用的明文目录存储：沿用加密前的文件名规则（`<摘要>.png`、`<摘要>.formats`、`<摘要>.thumb`），
/// 让 ClipStore 的行为测试可以直接按文件名断言磁盘上的文件。正式代码只用 EncryptedBlobStore 与 InMemoryClipBlobStore
struct PlainDirectoryBlobStore: ClipBlobStoring {
    let plain: BlobStore

    init(directory: URL) {
        plain = BlobStore(directory: directory)
    }

    var directory: URL { plain.directory }
    var isPersistent: Bool { true }

    func name(kind: ClipBlobKind, contentHash: String) -> String {
        switch kind {
        case .image, .translatedImage: contentHash + ".png"
        case .formats: contentHash + ".formats"
        case .thumbnail: ImageThumbnail.legacyName(forImage: contentHash)
        }
    }

    func write(_ data: Data, name: String) throws {
        try plain.write(data, name: name)
    }

    func data(_ name: String) throws -> Data {
        try plain.read(name)
    }

    func exists(_ name: String) -> Bool {
        plain.exists(name)
    }

    @discardableResult
    func remove(_ names: some Sequence<String>) -> [String] {
        plain.remove(names)
    }

    @discardableResult
    func removeAll(except keep: Set<String>) throws -> [String] {
        try plain.removeAll(except: keep)
    }

    func url(for name: String) -> URL? {
        plain.url(for: name)
    }
}

extension ClipStore {
    /// 测试用：明文目录存储中图片原图的文件地址（正式代码没有返回 URL 的接口）；名称非法时为 nil
    func imageURL(for item: ClipItem) -> URL? {
        guard let plain = blobs as? PlainDirectoryBlobStore else { return nil }
        return item.image.flatMap { plain.url(for: $0.name) }
    }
}
