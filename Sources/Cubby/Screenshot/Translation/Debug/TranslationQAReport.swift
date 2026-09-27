#if DEBUG
import CubbyCore
import Foundation

/// 验收报告：每个场景四张图 + index.html（统计、对比图、逐块明细）
enum TranslationQAReport {
    static func writeImages(_ result: TranslationQARunner.SceneResult, to directory: URL) throws {
        let id = result.scene.id
        try TranslationQAImages.writePNG(result.before, to: directory.appendingPathComponent("\(id)-before.png"))
        try TranslationQAImages.writePNG(result.after, to: directory.appendingPathComponent("\(id)-after.png"))
        if let side = TranslationQAImages.sideBySide(result.before, result.after) {
            try TranslationQAImages.writePNG(side, to: directory.appendingPathComponent("\(id)-side.png"))
        }
        if let debug = TranslationQAImages.debug(result) {
            try TranslationQAImages.writePNG(debug, to: directory.appendingPathComponent("\(id)-debug.png"))
        }
    }

    static func summaryLine(_ result: TranslationQARunner.SceneResult) -> String {
        let translated = result.records.filter { $0.placed != nil }.count
        let notes = result.records.compactMap(\.note).count
        return String(
            format: "QA: %@ blocks=%d translated=%d notes=%d missed=%d recognize=%.0fms place(max)=%.2fms paint=%.2fms",
            result.scene.id, result.records.count, translated, notes, result.missed.count,
            result.recognitionMilliseconds, result.placeMilliseconds.max() ?? 0, result.paintMilliseconds)
    }

    static func writeIndex(_ results: [TranslationQARunner.SceneResult], to directory: URL) throws {
        let rows = results.map(summaryRow).joined()
        let sections = results.map(section).joined()
        let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>Cubby translate QA</title><style>
            body{font:13px -apple-system,system-ui;margin:24px;background:#f5f5f7;color:#1d1d1f}
            table{border-collapse:collapse;margin:8px 0 16px;background:#fff}
            td,th{border:1px solid #d2d2d7;padding:3px 6px;text-align:left;vertical-align:top}
            img{max-width:100%;border:1px solid #d2d2d7;background:#fff}
            section{margin:32px 0} .note{color:#c93400} .skip{color:#86868b}
            </style></head><body><h1>Screenshot translation · visual QA</h1>
            <table><tr><th>scene</th><th>target</th><th>blocks</th><th>translated</th><th>notes</th><th>missed</th>
            <th>recognize ms</th><th>place ms (max)</th><th>paint ms</th></tr>\(rows)</table>\(sections)</body></html>
            """
        try html.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    // MARK: - 内部

    private static func summaryRow(_ result: TranslationQARunner.SceneResult) -> String {
        let translated = result.records.filter { $0.placed != nil }.count
        let notes = result.records.compactMap(\.note).count
        return
            "<tr><td><a href=\"#\(result.scene.id)\">\(escape(result.scene.id))</a></td><td>\(result.scene.target)</td>"
            + "<td>\(result.records.count)</td><td>\(translated)</td><td>\(notes)</td><td>\(result.missed.count)</td>"
            + String(
                format: "<td>%.0f</td><td>%.2f</td><td>%.2f</td></tr>", result.recognitionMilliseconds,
                result.placeMilliseconds.max() ?? 0, result.paintMilliseconds)
    }

    private static func section(_ result: TranslationQARunner.SceneResult) -> String {
        let id = result.scene.id
        let missed =
            result.missed.isEmpty
            ? "" : "<p class=\"note\">Missed: \(result.missed.map(escape).joined(separator: " · "))</p>"
        return """
            <section id="\(id)"><h2>\(escape(result.scene.title)) <small>(\(id))</small></h2>
            <p><a href="\(id)-side.png"><img src="\(id)-side.png"></a></p>\(missed)
            <details><summary>Recognition boxes</summary><img src="\(id)-debug.png"></details>
            <table><tr><th>#</th><th>source</th><th>result</th><th>layout</th></tr>\(result.records.map(blockRow).joined())</table>
            </section>
            """
    }

    private static func blockRow(_ record: TranslationQARunner.BlockRecord) -> String {
        let result: String
        if let skip = record.skip {
            result = "<span class=\"skip\">skip: \(skip.rawValue)</span>"
        } else {
            result = escape(record.translation ?? "")
        }
        let note = record.note.map { " <span class=\"note\">\(escape($0))</span>" } ?? ""
        let layout = record.placed.map(describe) ?? ""
        let heights = record.block.lines.map { String(format: "%.1f", $0.frame.height) }.joined(separator: " ")
        return "<tr><td>\(record.block.id)</td><td>\(escape(record.block.text))<br><small>h \(heights)</small></td>"
            + "<td>\(result)\(note)</td>"
            + "<td>\(layout)</td></tr>"
    }

    private static func describe(_ block: TranslatedBlock) -> String {
        let backdrop: String
        switch block.backdrop {
        case .solid: backdrop = "solid"
        case .plate: backdrop = "plate"
        }
        let color = block.textColor
        return String(
            format: "%@ · %.1fpt%@ · %@ · ink #%02X%02X%02X · %d line(s)", backdrop, block.fontSize,
            block.isBold ? " bold" : "", "\(block.alignment)", Int(color.red * 255), Int(color.green * 255),
            Int(color.blue * 255), block.lines.count)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
#endif
