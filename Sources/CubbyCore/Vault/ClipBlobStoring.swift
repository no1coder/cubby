import Foundation

/// 历史引用的二进制内容种类：参与加密存储的文件名派生（HistoryKeys.blobName 的 kind），取值一旦发布不可更改
public enum ClipBlobKind: String, CaseIterable, Sendable {
    /// 图片原图（PNG）
    case image
    /// 富文本格式（RichFormats 编码）
    case formats
    /// 卡片缩略图：内容哈希位置填原图的文件名，由原图名推出
    case thumbnail
    /// 图片译文的译后 PNG
    case translatedImage = "translated-image"
}

/// ClipStore 使用的二进制内容存储（E5、E10）：只提供数据接口，不返回文件 URL。
///
/// 正式实现为 EncryptedBlobStore（磁盘上的密文）；历史已锁定或尚未就绪时为 InMemoryClipBlobStore（E8 ①）。
/// 文件名只能经 name(kind:contentHash:) 得到，同一内容在同一存储里总是同名（据此去重）。
public protocol ClipBlobStoring: Sendable {
    /// 内容是否写在磁盘上：false（内存）时删除总是安全的，不存在「磁盘上的历史仍引用它」的问题
    var isPersistent: Bool { get }
    /// 某种内容在本存储中的文件名；结果总是合法的文件名
    func name(kind: ClipBlobKind, contentHash: String) -> String
    /// 写入；同名已存在时跳过（名称由内容派生，内容必然相同）
    func write(_ data: Data, name: String) throws
    /// 读取；不存在或无法解密时抛错
    func data(_ name: String) throws -> Data
    func exists(_ name: String) -> Bool
    /// 删除指定文件，返回删除失败的文件名（不存在不算失败）
    @discardableResult
    func remove(_ names: some Sequence<String>) -> [String]
    /// 删除所有不在 keep 中的文件，返回被删除的文件名
    @discardableResult
    func removeAll(except keep: Set<String>) throws -> [String]
}

extension ClipBlobStoring {
    /// 图片原图对应的卡片缩略图文件名（由原图名推出，不写入历史）
    public func thumbnailName(forImage imageName: String) -> String {
        name(kind: .thumbnail, contentHash: imageName)
    }

    /// 读取缩略图数据；没有缩略图（小图不生成）或读取失败时为 nil
    func thumbnailData(forImage imageName: String) -> Data? {
        let name = thumbnailName(forImage: imageName)
        guard exists(name) else { return nil }
        return try? data(name)
    }
}

extension EncryptedBlobStore: ClipBlobStoring {
    public var isPersistent: Bool { true }

    public func name(kind: ClipBlobKind, contentHash: String) -> String {
        keys.blobName(kind: kind.rawValue, contentHash: contentHash)
    }
}

/// 一张历史图片（原图或译后图）的数据来源：可在任意线程读取，供后台解码、文字识别、导出使用。
///
/// 相等与哈希只看文件名（缓存键、视图 .task(id:)）；文件名由内容派生，同名即同一内容。
public struct ClipImageSource: Sendable, Hashable {
    /// 存储中的文件名（加密存储中为 HMAC，不含内容信息）
    public let name: String
    /// 是否有预生成的卡片缩略图可用（译后图片没有）
    let hasThumbnail: Bool
    private let blobs: any ClipBlobStoring

    /// - Parameter hasThumbnail: 存储里是否可能有预生成的卡片缩略图（只有大图有；译后图片没有）
    public init(name: String, blobs: any ClipBlobStoring, hasThumbnail: Bool = false) {
        self.name = name
        self.blobs = blobs
        self.hasThumbnail = hasThumbnail
    }

    /// 解密后的原图数据（同步；大图请在后台调用，或用 load()）
    public func data() throws -> Data {
        try blobs.data(name)
    }

    /// 在全局并发执行器上读取（离开主线程）
    @concurrent
    public func load() async throws -> Data {
        try data()
    }

    /// 预生成的卡片缩略图数据；没有时为 nil
    public func thumbnailData() -> Data? {
        hasThumbnail ? blobs.thumbnailData(forImage: name) : nil
    }

    public static func == (lhs: ClipImageSource, rhs: ClipImageSource) -> Bool {
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
