import Foundation

/// 拆词卡上的一块（docs/TEXT-PICK-DESIGN.md P5）：词、标点或受保护的实体（网址 / 邮箱 / 电话）
public struct TextPickToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 系统分词得到的词（含数字、emoji）
        case word
        /// 不属于任何词的非空白字符；同一字符的连续标点合成一块（「...」「——」）
        case punctuation
        /// NSDataDetector 识别出的网址、邮箱、电话号码，整体成一块
        case entity
    }

    /// 在 TextPickDocument.text 中的范围
    public let range: Range<String.Index>
    public let text: String
    public let kind: Kind
    /// 与上一块（首块为文本开头）之间原文里的换行数：> 0 另起一行，≥ 2 为段落（多留段距）
    public let lineBreaksBefore: Int

    public init(range: Range<String.Index>, text: String, kind: Kind, lineBreaksBefore: Int) {
        self.range = range
        self.text = text
        self.kind = kind
        self.lineBreaksBefore = lineBreaksBefore
    }
}

/// 一条文本的拆词结果（纯值）：原文（截到上限）与按顺序排列、互不重叠的词块
public struct TextPickDocument: Equatable, Sendable {
    /// 只拆前这么多个字符（与预览一致，docs/TEXT-PICK-DESIGN.md P6）
    public static let characterLimit = 20_000

    /// 参与拆分的原文：超过上限时只保留前 characterLimit 个字符
    public let text: String
    public let tokens: [TextPickToken]
    /// 原文超过上限、只拆了前一部分
    public let isTruncated: Bool

    public init(text: String, tokens: [TextPickToken], isTruncated: Bool) {
        self.text = text
        self.tokens = tokens
        self.isTruncated = isTruncated
    }

    /// 没有任何词块（空文本或只有空白）
    public var isEmpty: Bool {
        tokens.isEmpty
    }

    /// 词的数量（不含标点；实体算一个词）
    public var wordCount: Int {
        tokens.reduce(0) { $0 + ($1.kind == .punctuation ? 0 : 1) }
    }
}
