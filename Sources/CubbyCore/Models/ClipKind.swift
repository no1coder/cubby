import Foundation

/// 剪贴板条目的内容类型
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case link
    case color
    case image
    case file

    /// 单个条目的类型名（单数），用于预览标签与图片搜索
    public var displayName: String {
        switch self {
        case .text: String(localized: "Text", comment: "Kind of a single clipboard item")
        case .link: String(localized: "Link", comment: "Kind of a single clipboard item")
        case .color: String(localized: "Color", comment: "Kind of a single clipboard item")
        case .image: String(localized: "Image", comment: "Kind of a single clipboard item")
        case .file: String(localized: "File", comment: "Kind of a single clipboard item")
        }
    }

    /// SF Symbols 图标名
    public var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }
}
