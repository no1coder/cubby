import Foundation

/// 把 Markdown 解析为 GuideDocument：先用 Foundation 的 AttributedString(markdown:)（.full 语法），
/// 再按 presentationIntent 把连续的片段归为块。纯函数，在后台线程调用。
enum GuideParser {
    static func parse(_ markdown: String) throws -> GuideDocument {
        let source = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        )
        var builder = GuideBlockBuilder()
        for run in source.runs {
            builder.append(
                String(source[run.range].characters),
                intent: run.presentationIntent,
                inline: run.inlinePresentationIntent ?? [],
                link: run.link
            )
        }
        return GuideDocument(blocks: builder.finish())
    }
}

/// 逐个片段累积为块（只在一次解析内部使用）
private struct GuideBlockBuilder {
    /// 软换行在解析时还不知道后一个字符，先占位，成块时再决定是空格还是删除
    private enum Pending {
        case run(GuideRun)
        case softBreak

        var run: GuideRun? {
            if case .run(let run) = self { run } else { nil }
        }
    }

    private var blocks: [GuideBlock] = []
    private var intent: PresentationIntent?
    private var pending: [Pending] = []
    /// 位于 <kbd>…</kbd> 之间：按行内代码处理
    private var insideKeyboardTag = false
    /// 已画过项目符号的列表项（同一项的后续段落不再画）
    private var markedListItems: Set<Int> = []
    private var anchors = GuideAnchors()

    mutating func append(_ text: String, intent: PresentationIntent?, inline: InlinePresentationIntent, link: URL?) {
        if intent != self.intent {
            flush()
            self.intent = intent
        }
        if inline.contains(.inlineHTML) {
            handleHTML(text)
        } else if inline.contains(.softBreak) {
            pending.append(.softBreak)
        } else if inline.contains(.lineBreak) {
            // 行分隔符：同一段内换行，不产生段间距
            pending.append(.run(GuideRun("\u{2028}")))
        } else {
            appendText(text, inline: inline, link: link)
        }
    }

    mutating func finish() -> [GuideBlock] {
        flush()
        return blocks
    }

    // MARK: - 行内

    private mutating func appendText(_ text: String, inline: InlinePresentationIntent, link: URL?) {
        var style: GuideRun.Style = []
        if inline.contains(.stronglyEmphasized) { style.insert(.bold) }
        if inline.contains(.emphasized) { style.insert(.italic) }
        guard inline.contains(.code) || insideKeyboardTag else {
            pending.append(.run(GuideRun(text, style: style, link: link)))
            return
        }
        guard let segments = GuideKeyPattern.segments(of: text) else {
            pending.append(.run(GuideRun(text, style: style.union(.code), link: link)))
            return
        }
        for segment in segments {
            let segmentStyle = segment.isKey ? style.union(.key) : style
            pending.append(.run(GuideRun(segment.text, style: segmentStyle, link: link)))
        }
    }

    /// 只认 <kbd> 与 <br>，其余 HTML 标签丢弃（不显示原始标签）
    private mutating func handleHTML(_ tag: String) {
        switch tag.lowercased().replacingOccurrences(of: " ", with: "") {
        case "<kbd>": insideKeyboardTag = true
        case "</kbd>": insideKeyboardTag = false
        case "<br>", "<br/>": pending.append(.run(GuideRun("\u{2028}")))
        default: break
        }
    }

    // MARK: - 成块

    private mutating func flush() {
        defer { pending = [] }
        let runs = Self.resolve(pending)
        guard let intent, !runs.isEmpty, let kind = kind(for: intent, runs: runs) else { return }
        blocks.append(GuideBlock(kind: kind, runs: kind == .code ? Self.codeRuns(runs) : runs))
    }

    /// 由内向外找第一个决定块类型的组件；nil 表示不显示（分隔线）
    private mutating func kind(for intent: PresentationIntent, runs: [GuideRun]) -> GuideBlock.Kind? {
        let components = intent.components
        for (index, component) in components.enumerated() {
            switch component.kind {
            case .header(let level):
                let title = runs.map(\.text).joined()
                return .heading(anchors.heading(level: level, title: title))
            case .codeBlock: return .code
            case .thematicBreak: return nil
            case .tableCell(let column): return .tableCell(Self.cell(column: column, in: components[(index + 1)...]))
            case .listItem(let ordinal): return listItem(ordinal: ordinal, at: index, in: components)
            case .blockQuote: return .quote(group: component.identity)
            default: continue
            }
        }
        return .paragraph
    }

    private mutating func listItem(ordinal: Int, at index: Int, in components: [PresentationIntent.IntentType])
        -> GuideBlock.Kind
    {
        let item = components[index]
        let depth = min(components.filter { if case .listItem = $0.kind { true } else { false } }.count, 2)
        guard markedListItems.insert(item.identity).inserted else {
            return .listItem(marker: nil, depth: depth)
        }
        let isOrdered = components.indices.contains(index + 1) && components[index + 1].kind == .orderedList
        let marker = isOrdered ? "\(ordinal)." : (depth == 1 ? "•" : "◦")
        return .listItem(marker: marker, depth: depth)
    }

    private static func cell(column: Int, in outer: ArraySlice<PresentationIntent.IntentType>) -> GuideTableCell {
        var row = 0
        var columns = column + 1
        var table = 0
        for component in outer {
            switch component.kind {
            case .tableRow(let index): row = index
            case .table(let definitions):
                columns = definitions.count
                table = component.identity
            default: break
            }
        }
        return GuideTableCell(table: table, row: row, column: column, columns: columns)
    }

    // MARK: - 片段整理

    /// 软换行两侧有中日韩文字时删除（中文断行不该变成空格），否则变为空格；再合并同样式的相邻片段
    private static func resolve(_ pending: [Pending]) -> [GuideRun] {
        var runs: [GuideRun] = []
        for (index, item) in pending.enumerated() {
            let run: GuideRun
            switch item {
            case .run(let value): run = value
            case .softBreak:
                let before = runs.last?.text.last
                let after = pending[(index + 1)...].lazy.compactMap(\.run).first?.text.first
                if isCJK(before) || isCJK(after) { continue }
                run = GuideRun(" ")
            }
            if let last = runs.last, last.canMerge(with: run) {
                runs[runs.count - 1] = last.appending(run)
            } else {
                runs.append(run)
            }
        }
        return runs
    }

    /// 代码块：去掉结尾换行，块内换行改为行分隔符（整块是一个段落）
    private static func codeRuns(_ runs: [GuideRun]) -> [GuideRun] {
        let text = runs.map(\.text).joined()
            .trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: "\n", with: "\u{2028}")
        return [GuideRun(text, style: .code)]
    }

    private static func isCJK(_ character: Character?) -> Bool {
        guard let character else { return false }
        return GuideScript.containsCJK(String(character))
    }
}

/// 生成与 GitHub 一致的标题锚点：小写，去掉标点，空格变连字符，重名依次加 -1、-2
struct GuideAnchors {
    private var used: [String: Int] = [:]

    mutating func heading(level: Int, title: String) -> GuideHeading {
        let base = Self.slug(title)
        let count = used[base, default: 0]
        used[base] = count + 1
        return GuideHeading(level: level, title: title, anchor: count == 0 ? base : "\(base)-\(count)")
    }

    static func slug(_ title: String) -> String {
        var slug = ""
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                slug.unicodeScalars.append(scalar)
            } else if scalar == " " {
                slug.append("-")
            }
        }
        return slug
    }
}
