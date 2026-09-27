import Foundation

/// 使用说明的文档模型：Markdown 解析后的块序列（不可变值类型，可在后台线程生成后交给主线程）
struct GuideDocument: Sendable, Equatable {
    let blocks: [GuideBlock]
}

/// 块：标题、段落、列表项、引用、代码块或表格单元格，各自带一串行内片段
struct GuideBlock: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case heading(GuideHeading)
        case paragraph
        /// 列表项。marker 为 nil 表示同一项的后续段落；depth 从 1 开始，最多 2
        case listItem(marker: String?, depth: Int)
        /// 引用块；group 相同的段落属于同一个引用
        case quote(group: Int)
        case code
        case tableCell(GuideTableCell)
    }

    let kind: Kind
    let runs: [GuideRun]
}

/// 标题。anchor 与 GitHub 生成的锚点一致，文内的 [文字](#anchor) 链接据此跳转
struct GuideHeading: Sendable, Equatable {
    let level: Int
    let title: String
    let anchor: String
}

/// 表格单元格的位置；row 为 0 是表头
struct GuideTableCell: Sendable, Equatable {
    /// 所属表格（同一表格的单元格排进同一个 NSTextTable）
    let table: Int
    let row: Int
    let column: Int
    let columns: Int

    var isHeader: Bool {
        row == 0
    }
}

/// 行内片段：文字 + 样式 + 可选链接
struct GuideRun: Sendable, Equatable {
    struct Style: OptionSet, Sendable, Hashable {
        let rawValue: Int

        static let bold = Style(rawValue: 1 << 0)
        static let italic = Style(rawValue: 1 << 1)
        /// 普通行内代码：等宽字体
        static let code = Style(rawValue: 1 << 2)
        /// 按键或快捷键（⌘T、esc、↩）：画成键帽
        static let key = Style(rawValue: 1 << 3)
    }

    let text: String
    let style: Style
    let link: URL?

    init(_ text: String, style: Style = [], link: URL? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }

    /// 样式与链接相同的相邻片段可以合并
    func canMerge(with other: GuideRun) -> Bool {
        style == other.style && link == other.link && !style.contains(.key)
    }

    func appending(_ other: GuideRun) -> GuideRun {
        GuideRun(text + other.text, style: style, link: link)
    }
}

/// 中日韩文字判断：软换行两侧是中文时不补空格；含中文的行内代码不用等宽字体
enum GuideScript {
    private static let cjkRanges: [ClosedRange<UInt32>] = [0x2E80...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF]

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            cjkRanges.contains { $0.contains(scalar.value) }
        }
    }
}
