import Foundation

/// 最近构建过的翻译文档（不可变值，每次修改返回新值）：富文本条目的文档要在后台解析 HTML / RTF 才能得到，
/// 同步的 plan 用它按实际发送的文字判断疑似密钥（ClipSecretGate）。条目内容不可变，按 id、内容指纹与格式文件名对应；
/// 只保留最近 capacity 条
public struct ClipDocumentCache: Equatable, Sendable {
    public static let capacity = 16

    private struct Entry: Equatable, Sendable {
        let id: UUID
        let contentHash: String
        let formatsName: String?
        let document: ClipTranslationDocument

        func matches(_ item: ClipItem) -> Bool {
            id == item.id && contentHash == item.contentHash && formatsName == item.formatsName
        }
    }

    /// 最近放入的在后
    private let entries: [Entry]

    public init() {
        entries = []
    }

    private init(entries: [Entry]) {
        self.entries = entries
    }

    /// 该条目当前内容的文档；没有构建过或内容已变时为 nil
    public func document(for item: ClipItem) -> ClipTranslationDocument? {
        entries.last { $0.matches(item) }?.document
    }

    /// 放入（同一条目只留最新的一份），超出容量时丢弃最早的
    public func inserting(_ document: ClipTranslationDocument, for item: ClipItem) -> ClipDocumentCache {
        let entry = Entry(id: item.id, contentHash: item.contentHash, formatsName: item.formatsName, document: document)
        let kept = entries.filter { $0.id != item.id } + [entry]
        return ClipDocumentCache(entries: Array(kept.suffix(Self.capacity)))
    }
}
