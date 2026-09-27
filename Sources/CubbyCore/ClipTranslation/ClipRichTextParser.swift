import Foundation

/// 从富文本条目的格式（public.html / public.rtf）解析段落结构（docs/CLIP-TRANSLATION-DESIGN.md §0.1 A2）。
/// 纯函数、不依赖 WebKit，可在任意线程调用：HTML 用 Foundation 的 XMLDocument（libxml2 的 HTML 解析）整理成 DOM，
/// RTF 用 NSAttributedString 的 RTF 读取器
public enum ClipRichTextParser {
    public static let htmlType = "public.html"
    public static let rtfType = "public.rtf"
    /// 有序列表起始序号的上限（HTML 的 start、RTF 的 levelstartat 都来自不受信数据）
    static let maxListOrdinal = 1_000_000

    /// 优先 HTML（语义完整：标题、列表、代码），解析失败或没有文字时用 RTF；都不可用时为 nil
    public static func document(from formats: [String: Data]) -> ClipRichDocument? {
        let candidates: [() -> ClipRichDocument?] = [
            { formats[htmlType].flatMap(html) },
            { formats[rtfType].flatMap(rtf) },
        ]
        return candidates.lazy.compactMap { $0() }.first { !$0.paragraphs.isEmpty }
    }

    // MARK: - HTML

    /// libxml2 的 HTML 解析器不认 HTML5 的 `<meta charset>`，没有声明时按 Latin-1 读：UTF-8 内容一律补上 http-equiv 声明
    private static let utf8Declaration = #"<meta http-equiv="Content-Type" content="text/html; charset=utf-8">"#

    static func html(_ data: Data) -> ClipRichDocument? {
        let source = String(data: data, encoding: .utf8).map { Data((utf8Declaration + $0).utf8) } ?? data
        guard let document = try? XMLDocument(data: source, options: [.documentTidyHTML]),
            let root = document.rootElement()
        else { return nil }
        let tokens = HTMLTokenizer().tokens(of: root, context: .root, depth: 0)
        return ClipRichDocument(paragraphs: paragraphs(from: tokens))
    }

    /// 把「段落边界 + 行内文字」序列按边界切成段落；普通段落折叠空白（HTML 规则），预排版保留原样
    static func paragraphs(from tokens: [HTMLToken]) -> [ClipRichParagraph] {
        let state = tokens.reduce(
            into: (done: [ClipRichParagraph](), style: ClipParagraphStyle.body, runs: [ClipRichRun]())
        ) { state, token in
            switch token {
            case .boundary(let style):
                state.done.append(finished(style: state.style, runs: state.runs))
                state = (state.done, style, [])
            case .text(let run):
                state.runs.append(run)
            }
        }
        return (state.done + [finished(style: state.style, runs: state.runs)]).filter { !$0.runs.isEmpty }
    }

    private static func finished(style: ClipParagraphStyle, runs: [ClipRichRun]) -> ClipRichParagraph {
        guard style != .preformatted else {
            let text = runs.map(\.text).joined()
            return ClipRichParagraph(
                style: style, runs: [ClipRichRun(text.hasSuffix("\n") ? String(text.dropLast()) : text)])
        }
        return ClipRichParagraph(style: style, runs: collapsingWhitespace(runs))
    }

    /// HTML 空白规则：连续空白（不含不换行空格）折叠为一个空格，留在空白原来所在的那段文字里；段首段尾的空白去掉
    static func collapsingWhitespace(_ runs: [ClipRichRun]) -> [ClipRichRun] {
        let collapsed = runs.reduce(into: (runs: [ClipRichRun](), afterSpace: true)) { state, run in
            let text = run.text.reduce(into: "") { output, character in
                guard isCollapsible(character) else {
                    output.append(character)
                    state.afterSpace = false
                    return
                }
                if !state.afterSpace { output.append(" ") }
                state.afterSpace = true
            }
            state.runs.append(run.withText(text))
        }.runs.filter { !$0.text.isEmpty }
        guard let last = collapsed.last, last.text.hasSuffix(" ") else { return collapsed }
        return collapsed.dropLast() + [last.withText(String(last.text.dropLast()))]
    }

    private static func isCollapsible(_ character: Character) -> Bool {
        character.isWhitespace && character != "\u{00A0}"
    }
}

/// HTML 扁平化后的记号：段落边界（其后文字的段落样式）或一段行内文字
enum HTMLToken: Equatable {
    case boundary(ClipParagraphStyle)
    case text(ClipRichRun)
}

/// 递归遍历 DOM，产出记号序列（纯函数）
struct HTMLTokenizer {
    /// 遍历时的继承状态
    struct Context: Equatable {
        var block: ClipParagraphStyle
        var bold: Bool
        var link: URL?
        var code: Bool
        /// 列表嵌套层数
        var listLevel: Int

        static let root = Context(block: .body, bold: false, link: nil, code: false, listLevel: 0)
    }

    /// 超过该深度的内容视为异常输入，不再展开
    static let maxDepth = 128

    private static let skipped: Set<String> = [
        "head", "script", "style", "title", "meta", "noscript", "template", "svg", "math", "img", "button", "input",
        "select", "textarea", "iframe", "object",
    ]
    private static let blocks: Set<String> = [
        "p", "div", "li", "ul", "ol", "pre", "blockquote", "section", "article", "header", "footer", "nav", "aside",
        "main", "figure", "figcaption", "table", "thead", "tbody", "tfoot", "tr", "td", "th", "dl", "dt", "dd", "hr",
        "address", "details", "summary", "center", "form", "fieldset", "legend", "h1", "h2", "h3", "h4", "h5", "h6",
    ]
    private static let codeTags: Set<String> = ["code", "kbd", "samp", "tt"]
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    func tokens(of node: XMLNode, context: Context, depth: Int) -> [HTMLToken] {
        guard depth < Self.maxDepth else { return [] }
        switch node.kind {
        case .text:
            return [
                .text(
                    ClipRichRun(node.stringValue ?? "", isBold: context.bold, link: context.link, isCode: context.code))
            ]
        case .element:
            guard let element = node as? XMLElement, let name = element.name?.lowercased() else { return [] }
            return tokens(ofElement: element, name: name, context: context, depth: depth)
        default:
            return []
        }
    }

    private func tokens(ofElement element: XMLElement, name: String, context: Context, depth: Int) -> [HTMLToken] {
        guard !Self.skipped.contains(name) else { return [] }
        if name == "br" {
            return context.block == .preformatted ? [.text(ClipRichRun("\n"))] : [.boundary(context.block)]
        }
        let inner = self.context(for: element, name: name, parent: context)
        let children = element.children ?? []
        let content: [HTMLToken]
        if name == "ol" || name == "ul" {
            content = listTokens(
                children, ordered: name == "ol", start: Self.start(of: element), context: inner, depth: depth)
        } else {
            content = children.flatMap { tokens(of: $0, context: inner, depth: depth + 1) }
        }
        guard Self.blocks.contains(name) else { return content }
        return [.boundary(inner.block)] + content + [.boundary(context.block)]
    }

    /// 列表的直接子项：li 按位置编号（有序列表从 start 起）
    private func listTokens(
        _ children: [XMLNode], ordered: Bool, start: Int, context: Context, depth: Int
    ) -> [HTMLToken] {
        let items = children.reduce(into: (tokens: [HTMLToken](), count: 0)) { state, child in
            var itemContext = context
            if (child as? XMLElement)?.name?.lowercased() == "li" {
                itemContext.block = .listItem(ordinal: ordered ? start + state.count : nil, level: context.listLevel)
                state.count += 1
            }
            state.tokens += tokens(of: child, context: itemContext, depth: depth + 1)
        }
        return items.tokens
    }

    /// 元素给子节点带来的继承状态
    private func context(for element: XMLElement, name: String, parent: Context) -> Context {
        var context = parent
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            context.block = .heading(level: Int(name.dropFirst()) ?? 1)
        case "pre":
            context.block = .preformatted
        case "ul", "ol":
            context.listLevel += 1
        case "a":
            context.link = Self.link(of: element) ?? parent.link
        default:
            break
        }
        if Self.codeTags.contains(name) { context.code = true }
        context.bold = Self.isBold(element, name: name, inherited: parent.bold)
        return context
    }

    /// b / strong 加粗（Google 文档会用 `<b style="font-weight:normal">` 包住全文，按样式取消）；样式里的粗细优先
    private static func isBold(_ element: XMLElement, name: String, inherited: Bool) -> Bool {
        let style = element.attribute(forName: "style")?.stringValue?.lowercased().replacingOccurrences(
            of: " ", with: "")
        if let weight = style.flatMap(fontWeight) { return weight }
        return name == "b" || name == "strong" || inherited
    }

    private static func fontWeight(in style: String) -> Bool? {
        guard let range = style.range(of: "font-weight:") else { return nil }
        let value = style[range.upperBound...].prefix { $0 != ";" }
        if value.hasPrefix("bold") { return true }
        if value.hasPrefix("normal") || value.hasPrefix("lighter") { return false }
        return Int(value).map { $0 >= 600 }
    }

    private static func link(of element: XMLElement) -> URL? {
        guard let href = element.attribute(forName: "href")?.stringValue?.trimmingCharacters(in: .whitespaces),
            let url = URL(string: href), let scheme = url.scheme?.lowercased(), linkSchemes.contains(scheme)
        else { return nil }
        return url
    }

    /// 有序列表的起始序号，夹在 0…maxListOrdinal（不受信的超大值会让序号相加溢出）
    private static func start(of element: XMLElement) -> Int {
        let value = element.attribute(forName: "start")?.stringValue.flatMap { Int($0) } ?? 1
        return min(max(value, 0), ClipRichTextParser.maxListOrdinal)
    }
}
