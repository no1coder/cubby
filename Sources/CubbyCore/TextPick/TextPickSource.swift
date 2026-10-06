import Foundation

/// 条目能拆的文字（docs/TEXT-PICK-DESIGN.md P4）：文本（含富文本、代码，按纯文本拆）与已识别出文字的图片
/// （拆 recognizedText）；链接、颜色、文件、没有文字的图片与只有空白（含零宽字符）的文本不支持
public enum TextPickSource: Equatable, Sendable {
    case text(String)
    case unsupported

    public init(item: ClipItem) {
        let candidate: String? =
            switch (item.payload, item.kind) {
            case (.text, .link), (.text, .color): nil
            case (.text(let text), _): text
            case (.image, _): item.recognizedText
            case (.files, _): nil
            }
        guard let candidate, candidate.contains(where: { !TextPickTokenizer.isBlank($0) }) else {
            self = .unsupported
            return
        }
        self = .text(candidate)
    }

    /// 可拆的文字；不支持时为 nil
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}
