import Foundation

/// Shell、HTML、CSS、SQL 的特征
extension CodeLanguageSignals {
    static let shell: [CodeLanguageSignal] = [
        .custom(6) { $0.text.hasPrefix("#!") && ($0.text.hasSuffix("sh") || $0.text.contains("sh ")) },
        .prefix(["$ ", "if [", "elif ["], 3),
        .contains(["; then", "; do"], 3),
        .custom(3) { ["fi", "done", "esac", "then", "do"].contains($0.text) },
        .prefix(shellCommands, 2),
        .contains(["| grep", "| xargs", "| sort", "| head", "| tail", "| wc", "| awk", "| sed", "2>&1"], 2),
        .contains(["$(", "$HOME", "$PATH", "$1"], 2),
        .custom(2, isShellExport),
        .contains(["${"], 1),
    ]

    static let html: [CodeLanguageSignal] = [
        .upperPrefix(["<!DOCTYPE"], 6),
        .prefix(["<html"], 5),
        .contains(htmlTags, 2),
        .contains(["</", " class=\"", " href=\"", " src=\"", " id=\""], 2),
        .custom(1) { $0.text.hasPrefix("<") && $0.text.hasSuffix(">") },
    ]

    static let css: [CodeLanguageSignal] = [
        .prefix(["@media", "@import", "@keyframes", "@font-face", "@supports"], 4),
        .contains(["!important"], 3),
        .custom(2, isCSSSelector),
        .custom(2, isCSSDeclaration),
        .contains(["var(--"], 2),
        .contains(["px;", "px ", "rem;", "em;", "vh;", "vw;", "%;", ": #"], 1),
    ]

    /// 大写关键字额外加分：`SELECT … FROM` 是 SQL 的典型写法，小写的 select/from 也常见于英文句子
    static let sql: [CodeLanguageSignal] = [
        .upperPrefix(["INSERT INTO", "CREATE TABLE", "DELETE FROM", "ALTER TABLE", "DROP TABLE", "CREATE INDEX"], 4),
        .custom(4) { $0.upper.hasPrefix("UPDATE ") && $0.upper.contains(" SET ") },
        .upperPrefix(["SELECT "], 2),
        .prefix(["SELECT "], 1),
        .custom(1) { $0.upper.hasPrefix("FROM ") || $0.upper.contains(" FROM ") },
        .custom(1) { $0.text.hasPrefix("FROM ") || $0.text.contains(" FROM ") },
        .custom(1) { $0.upper.hasPrefix("WHERE ") || $0.upper.contains(" WHERE ") },
        .custom(1) { $0.text.hasPrefix("WHERE ") || $0.text.contains(" WHERE ") },
        .upperContains(sqlClauses, 1),
        .contains(sqlClauses, 1),
    ]

    private static let shellCommands = [
        "cd ", "brew ", "git ", "npm ", "npx ", "yarn ", "pnpm ", "sudo ", "curl ", "wget ", "echo ", "mkdir ",
        "rm ", "cp ", "mv ", "ls ", "chmod ", "chown ", "apt ", "apt-get ", "pip ", "pip3 ", "docker ", "kubectl ",
        "make ", "cat ", "grep ", "source ", "ssh ", "tar ", "swift ", "xcodebuild ", "touch ", "set -",
    ]

    private static let htmlTags = [
        "<div", "<span", "<p>", "<a ", "<head", "<body", "<script", "<meta", "<link", "<ul", "<li", "<img",
        "<table", "<tr", "<td", "<form", "<input", "<button", "<section", "<h1", "<h2", "<h3", "<br", "<template",
    ]

    private static let sqlClauses = [
        "ORDER BY", "GROUP BY", " JOIN ", "VALUES (", "VALUES(", "PRIMARY KEY", "NOT NULL", "VARCHAR", "INTEGER",
        "LIMIT ",
    ]

    /// `export NAME=value`（与 JS 的 `export const` 区分）
    private static let isShellExport: @Sendable (CodeLine) -> Bool = { line in
        guard line.text.hasPrefix("export ") else { return false }
        return line.text.dropFirst(7).prefix { !$0.isWhitespace }.contains("=")
    }

    /// 写在 CSS 选择器开头会被误认的代码关键字（`struct Point {`、`impl Point {`、`} else {` 等）
    private static let codeKeywords: Set<Substring> = [
        "if", "else", "for", "while", "switch", "do", "try", "catch", "func", "function", "fn", "struct", "class",
        "enum", "impl", "interface", "type", "export", "const", "let", "var", "protocol", "extension", "pub", "def",
        "match", "loop", "mod", "trait", "return", "case", "default", "public", "private", "static", "init", "guard",
        "repeat", "defer", "unsafe", "async", "namespace", "package", "object", "actor", "go", "select",
    ]

    /// 选择器行：以 `{` 结尾，`.#*:@[` 或小写字母开头，不含赋值和语句符号，开头也不是代码关键字
    private static let isCSSSelector: @Sendable (CodeLine) -> Bool = { line in
        let text = line.text
        guard text.hasSuffix("{"), let first = text.first, ".#*:@[".contains(first) || first.isLowercase else {
            return false
        }
        guard !text.contains("="), !text.contains(";") else { return false }
        guard first == "@" || !text.contains("(") else { return false }
        let head = text.prefix { $0.isLetter }
        return !codeKeywords.contains(head)
    }

    /// 声明：`name: value;`，属性名只含小写字母和连字符；允许写在同一行的 `{ … }` 里
    private static let isCSSDeclaration: @Sendable (CodeLine) -> Bool = { line in
        let text = line.text
        guard let colon = text.firstIndex(of: ":"), text[colon...].contains(";") else { return false }
        let name = text[..<colon].split(separator: "{").last?.trimmingCharacters(in: .whitespaces) ?? ""
        return !name.isEmpty && name.allSatisfy { ("a"..."z").contains($0) || $0 == "-" }
    }
}
