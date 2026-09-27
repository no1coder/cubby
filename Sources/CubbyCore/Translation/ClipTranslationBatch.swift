import Foundation

/// 剪贴板文本条目 ↔ 翻译引擎的映射（docs/CLIP-TRANSLATION-DESIGN.md §7，纯函数、值类型，可在任意线程使用）：
/// 每个可翻译段构造一个 `TextBlock(id: 段序号, lines: [], alignment: .leading, text: …)`；
/// 引擎返回的一块译文按 id 对回段，得到可写入缓存的文字。
///
/// - 大模型（`.markup`）收到受限 Markdown（行内代码是 `` `c1` `` 占位符），译文解析回粗体、链接与代码；
/// - 系统翻译（`.plainText`）收到纯文本，行内代码换成 `{1}` 占位符（`ClipInlineCodeProtection`），译文返回后还原；
///   占位符被改坏的段报告 `needsRetry`，调用方用 `retrying(_:)` 不带保护重译一次。
///   富文本条目的系统译文同样以受限 Markdown 存储（文字转义、代码还原为代码），因此行内代码保持代码样式
public struct ClipTranslationBatch: Equatable, Sendable {
    /// 引擎接收的文字形式
    public enum Input: Equatable, Sendable {
        /// 受限 Markdown：大模型
        case markup
        /// 纯文本：系统翻译
        case plainText
    }

    /// 一块译文对回段之后的结果
    public enum Arrival: Equatable, Sendable {
        /// 第 index 段的译文（可写入缓存的规范形式）
        case translated(index: Int, text: String)
        /// 第 index 段的占位符被引擎改坏：需不带保护重译
        case needsRetry(index: Int)
    }

    public let document: ClipTranslationDocument
    public let input: Input
    /// 送给引擎的块（id = 段序号），按段顺序
    public let blocks: [TextBlock]
    /// 系统翻译各段的占位符保护（段序号 → 保护）
    private let protections: [Int: ClipInlineCodeProtection]

    /// 文档的全部可翻译段
    public init(document: ClipTranslationDocument, input: Input) {
        self.init(document: document, input: input, indices: document.translatableSegments.map(\.index), protects: true)
    }

    private init(document: ClipTranslationDocument, input: Input, indices: [Int], protects: Bool) {
        let segments = indices.compactMap { index in
            document.segments.indices.contains(index) && document.segments[index].isTranslatable
                ? document.segments[index] : nil
        }
        let protections: [Int: ClipInlineCodeProtection] =
            input == .plainText
            ? Dictionary(
                segments.map { ($0.index, Self.protection(for: $0, rich: document.isRich, protects: protects)) },
                uniquingKeysWith: { first, _ in first })
            : [:]
        self.document = document
        self.input = input
        self.protections = protections
        self.blocks = segments.map { segment in
            TextBlock(
                id: segment.index, lines: [], alignment: .leading,
                text: protections[segment.index]?.sent ?? segment.markup)
        }
    }

    /// 缓存、显示与整篇重建时的 markup 参数（与 ClipTranslation.usesInlineMarkup 一致）：
    /// 大模型的译文、以及富文本条目的系统译文都是受限 Markdown
    public var storesMarkup: Bool {
        input == .markup || document.isRich
    }

    /// 引擎返回的一块 → 对回的段；不属于本批的块、或还原后为空的译文为 nil
    public func arrival(_ translation: BlockTranslation) -> Arrival? {
        let index = translation.blockID
        guard blocks.contains(where: { $0.id == index }) else { return nil }
        var output = translation.text
        if let protection = protections[index] {
            guard let restored = protection.restore(output) else { return .needsRetry(index: index) }
            output = restored
        }
        let stored = document.storableTranslation(output, at: index, markup: storesMarkup)
        return stored.isEmpty ? nil : .translated(index: index, text: stored)
    }

    /// 只含指定段、不带占位符保护的一批（保护失败后的重译）
    public func retrying(_ indices: [Int]) -> ClipTranslationBatch {
        ClipTranslationBatch(document: document, input: input, indices: indices, protects: false)
    }

    /// 已到达的译文（段序号 → 译文）→ 与文档分段一一对应的数组（未到达为 nil）
    public func translations(_ arrived: [Int: String]) -> [String?] {
        document.segments.map { arrived[$0.index] }
    }

    // MARK: - 内部

    private static func protection(
        for segment: ClipTranslationDocument.Segment, rich: Bool, protects: Bool
    ) -> ClipInlineCodeProtection {
        // 富文本：发送文字取自受限 Markdown 解析出的行内文字（代码为 cN，占位还原时由文档换回代码原文）
        let pieces =
            rich
            ? ClipInlineCodeProtection.pieces(of: ClipInlineMarkup.parse(segment.markup))
            : ClipInlineCodeProtection.pieces(of: segment.plainText)
        return ClipInlineCodeProtection(pieces: pieces, plainText: segment.plainText, markup: rich, protects: protects)
    }
}
