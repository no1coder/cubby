import Foundation

/// 代码卡片的语言徽标
public enum CodeLanguage: String, CaseIterable, Sendable {
    case swift
    /// 同时涵盖 TypeScript
    case javascript
    case python
    case json
    case shell
    case html
    case css
    case sql
    case go
    case rust

    /// 徽标文字。都是专有名词，不做本地化
    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .javascript: "JavaScript"
        case .python: "Python"
        case .json: "JSON"
        case .shell: "Shell"
        case .html: "HTML"
        case .css: "CSS"
        case .sql: "SQL"
        case .go: "Go"
        case .rust: "Rust"
        }
    }

    /// 只看开头这么多个字符，超大文本也是线性且有上限的工作量
    static let sampleLength = 2_000

    /// 启发式识别代码语言；拿不准时返回 nil（界面显示通用的 "Code" 徽标）。
    /// 先判断整段是否为 JSON，再对开头样本逐行累计各语言的特征分，取最高分；
    /// 最高分低于门槛或与第二名并列时返回 nil，宁可漏判也不把散文误判成代码
    public static func detect(_ text: String) -> CodeLanguage? {
        let sample = String(text.prefix(sampleLength))
        guard sample.contains(where: { !$0.isWhitespace }) else { return nil }
        if JSONShape.matches(text, sample: sample) { return .json }
        return CodeLanguageScorer.bestMatch(in: sample)
    }
}

/// JSON 判断：首尾是成对的括号，且能被解析（大文本只做便宜的结构检查）
private enum JSONShape {
    /// 超过这个字节数就不完整解析
    static let maxParsedBytes = 64 * 1_024
    /// `[` 之后可以出现的第一个字符
    static let arrayElementStarts = Set("{[\"-0123456789tfn]")

    static func matches(_ text: String, sample: String) -> Bool {
        guard let first = sample.first(where: { !$0.isWhitespace }),
            let last = text.last(where: { !$0.isWhitespace }),
            (first == "{" && last == "}") || (first == "[" && last == "]")
        else { return false }
        guard text.utf8.count <= maxParsedBytes else { return hasJSONOpening(sample) }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// 开括号之后的第一个非空白字符必须符合 JSON 语法：对象接键名或 `}`，数组接任一值或 `]`
    private static func hasJSONOpening(_ sample: String) -> Bool {
        let content = sample.drop(while: \.isWhitespace)
        guard let opening = content.first, let next = content.dropFirst().first(where: { !$0.isWhitespace }) else {
            return false
        }
        return opening == "{" ? (next == "\"" || next == "}") : arrayElementStarts.contains(next)
    }
}

/// 逐行累计各语言的特征分
enum CodeLanguageScorer {
    /// 至少要有两条一般特征或一条很强的特征
    static let minimumScore = 4

    static func bestMatch(in sample: String) -> CodeLanguage? {
        let lines =
            sample
            .split(whereSeparator: \.isNewline)
            .map { CodeLine($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }
        let ranked = CodeLanguageSignals.all
            .map { entry in (entry.language, score(lines, entry.signals)) }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= minimumScore else { return nil }
        let runnerUp = ranked.dropFirst().first?.1 ?? 0
        return best.1 > runnerUp ? best.0 : nil
    }

    private static func score(_ lines: [CodeLine], _ signals: [CodeLanguageSignal]) -> Int {
        lines.reduce(0) { total, line in
            total + signals.reduce(0) { $0 + ($1.matches(line) ? $1.weight : 0) }
        }
    }
}
