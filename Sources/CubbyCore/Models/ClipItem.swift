import Foundation

/// 复制内容的来源应用
public struct SourceApp: Codable, Equatable, Sendable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// 图片条目的元数据，图片本体以文件形式保存在 BlobStore 中
public struct ImageRef: Codable, Equatable, Sendable {
    public let name: String
    public let width: Int
    public let height: Int

    public init(name: String, width: Int, height: Int) {
        self.name = name
        self.width = width
        self.height = height
    }
}

/// 条目实际承载的数据
public enum ClipPayload: Codable, Equatable, Sendable {
    case text(String)
    case image(ImageRef)
    case files([String])
}

/// 一条剪贴板历史记录（不可变，修改时返回新实例）
public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ClipKind
    public let payload: ClipPayload
    public let source: SourceApp?
    public let createdAt: Date
    public let isFavorite: Bool
    /// 内容指纹，用于去重
    public let contentHash: String
    /// 富文本格式（RTF / HTML 等）的 blob 文件名；纯文本条目为 nil
    public let formatsName: String?
    /// 图片中识别出的文字（本机 OCR），用于搜索：nil 表示尚未识别，空串表示已识别但没有可保存的文字。
    /// 旧版本写入的条目没有该字段，按 nil 解码；为 nil 时编码不写该字段
    public let recognizedText: String?
    /// 各目标语言的译文缓存（docs/CLIP-TRANSLATION-DESIGN.md §2）：nil 表示没有译文；
    /// 旧版本写入的条目没有该字段，按 nil 解码；为 nil 时编码不写该字段；内部损坏按项容错（ClipTranslations）
    public let translations: ClipTranslations?

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        payload: ClipPayload,
        source: SourceApp?,
        createdAt: Date,
        isFavorite: Bool = false,
        contentHash: String,
        formatsName: String? = nil,
        recognizedText: String? = nil,
        translations: ClipTranslations? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.source = source
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.contentHash = contentHash
        self.formatsName = formatsName
        self.recognizedText = recognizedText
        self.translations = translations
    }

    public func withFavorite(_ favorite: Bool) -> ClipItem {
        ClipItem(
            id: id, kind: kind, payload: payload, source: source, createdAt: createdAt,
            isFavorite: favorite, contentHash: contentHash, formatsName: formatsName, recognizedText: recognizedText,
            translations: translations)
    }

    /// 以新内容替换旧条目：沿用旧条目的 id 与收藏状态（新来源为空时沿用旧来源），其余取新值。
    /// 内容相同（哈希相同）意味着同一张图片，新条目尚未识别时沿用旧条目的识别文字，无需重新识别；
    /// 译文同理沿用，但富文本格式变了时不沿用（富文本译文按格式里的段落对齐，格式不同分段就可能不同）
    public func replacing(_ existing: ClipItem) -> ClipItem {
        let inherited = formatsName == existing.formatsName ? existing.translations : nil
        return ClipItem(
            id: existing.id, kind: kind, payload: payload, source: source ?? existing.source, createdAt: createdAt,
            isFavorite: existing.isFavorite, contentHash: contentHash, formatsName: formatsName,
            recognizedText: recognizedText ?? existing.recognizedText,
            translations: translations ?? inherited)
    }

    public func withFormatsName(_ name: String?) -> ClipItem {
        ClipItem(
            id: id, kind: kind, payload: payload, source: source, createdAt: createdAt,
            isFavorite: isFavorite, contentHash: contentHash, formatsName: name, recognizedText: recognizedText,
            translations: translations)
    }

    /// 设置或清除识别文字，其余字段不变
    public func withRecognizedText(_ text: String?) -> ClipItem {
        ClipItem(
            id: id, kind: kind, payload: payload, source: source, createdAt: createdAt,
            isFavorite: isFavorite, contentHash: contentHash, formatsName: formatsName, recognizedText: text,
            translations: translations)
    }

    /// 设置或清除译文缓存，其余字段不变
    public func withTranslations(_ translations: ClipTranslations?) -> ClipItem {
        ClipItem(
            id: id, kind: kind, payload: payload, source: source, createdAt: createdAt,
            isFavorite: isFavorite, contentHash: contentHash, formatsName: formatsName, recognizedText: recognizedText,
            translations: translations)
    }

    /// 再次被复制/粘贴时刷新时间；传入来源时一并更新，nil 表示保留原来源
    public func touched(at date: Date, source newSource: SourceApp? = nil) -> ClipItem {
        ClipItem(
            id: id, kind: kind, payload: payload, source: newSource ?? source, createdAt: date,
            isFavorite: isFavorite, contentHash: contentHash, formatsName: formatsName, recognizedText: recognizedText,
            translations: translations)
    }
}

// MARK: - 便捷访问

public extension ClipItem {
    var text: String? {
        if case .text(let value) = payload { return value }
        return nil
    }

    var image: ImageRef? {
        if case .image(let ref) = payload { return ref }
        return nil
    }

    var filePaths: [String] {
        if case .files(let paths) = payload { return paths }
        return []
    }

    /// 条目引用的全部 blob 文件名（图片、富文本格式、译后图片）
    var blobNames: [String] {
        [image?.name, formatsName].compactMap { $0 } + translatedImageNames
    }

    /// 译文缓存里的译后图片 blob 名
    var translatedImageNames: [String] {
        translations?.entries.compactMap(\.imageName) ?? []
    }

    /// 列表中显示的单行标题
    var title: String {
        switch payload {
        case .text(let value):
            return Self.firstLine(of: value, maxLength: 200)
        case .image(let ref):
            return String(
                localized: "Image \(ref.width)×\(ref.height)",
                comment: "Title of an image item: width × height in pixels"
            )
        case .files(let paths):
            let names = paths.map { ($0 as NSString).lastPathComponent }
            guard let first = names.first else {
                return String(localized: "Files", comment: "Title of a file item without any path")
            }
            guard names.count > 1 else { return first }
            // 同时传入「其余数量」与「总数」：英文用前者（and 2 more），中文用后者（等 3 个文件）
            return String(
                localized: "\(first) and \(names.count - 1) more (\(names.count) files)",
                comment: """
                    Title of an item with several files. %1$@ = first file name, %2$lld = number of other files, \
                    %3$lld = total number of files. Translations may omit %2$lld or %3$lld.
                    """
            )
        }
    }

    /// 只扫描开头部分，避免对 MB 级文本全量切分
    private static func firstLine(of text: String, maxLength: Int) -> String {
        let head = text.prefix(maxLength * 20)
        let line =
            head
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > maxLength ? String(line.prefix(maxLength)) + "…" : line
    }
}
