import Foundation

/// 把大模型的增量文本还原为逐块译文（docs/TRANSLATION-DESIGN.md §3.6「流式解析」）。
///
/// 期望的输出是 JSON Lines `{"id":n,"text":"…"}`；为容忍模型不守规矩，还接受：
/// 代码块围栏与前后杂讯（不含对象的行直接跳过）、JSON 数组（整行或每行一个元素）、
/// 跨多行排版的对象、`<think>…</think>` 推理段（整段忽略）。
/// id 必须属于本次请求且未出现过；译文去掉控制与格式字符，长度上限为 `4 × 原文 + 200`（Unicode 标量）。
/// 全程线性：每个字符只切分、扫描常数次
public struct TranslationLineParser: Sendable {
    /// 跨行对象最多攒这么多行，超过即丢弃（避免杂讯里的 { 吞掉后续内容）
    static let maxPendingLines = 16
    /// 未换行的缓冲上限（UTF-8 字节），超过即丢弃
    static let maxBufferBytes = 64 * 1024

    /// id → 原文长度（Unicode 标量）
    private let sourceLengths: [Int: Int]
    private var delivered: Set<Int> = []
    private var buffer = ""
    private var pending: [String] = []
    /// 已攒各行的花括号扫描状态（逐行累积，不重复扫描）
    private var pendingScanner = BraceScanner()
    private var isThinking = false

    public init(blocks: [TextBlock]) {
        sourceLengths = Dictionary(
            blocks.map { ($0.id, $0.text.unicodeScalars.count) }, uniquingKeysWith: { first, _ in first })
    }

    /// 已交付的块数
    public var deliveredCount: Int {
        delivered.count
    }

    /// 喂入一段增量文本，返回其中新完成的译文
    public mutating func consume(_ fragment: String) -> [BlockTranslation] {
        buffer += fragment
        var results: [BlockTranslation] = []
        var lineStart = buffer.startIndex
        while let newline = buffer[lineStart...].firstIndex(where: Self.isLineBreak) {
            results += process(String(buffer[lineStart..<newline]))
            lineStart = buffer.index(after: newline)
        }
        buffer = String(buffer[lineStart...])
        if buffer.utf8.count > Self.maxBufferBytes { buffer = "" }
        return results
    }

    /// 流结束：处理最后一行（没有换行结尾时）；仍未闭合的跨行对象丢弃
    public mutating func finish() -> [BlockTranslation] {
        let rest = buffer
        buffer = ""
        let results = rest.isEmpty ? [] : process(rest)
        resetPending()
        return results
    }

    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n" || character == "\r"
    }

    private mutating func process(_ raw: String) -> [BlockTranslation] {
        let line = removingThinking(raw).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return [] }
        let startsObject = line.drop(while: { $0 == "[" || $0 == " " }).first == "{"
        if !pending.isEmpty {
            // 新的一行本身就是完整对象：之前攒的多半是杂讯，丢弃
            if startsObject, Self.braceDepth(line) == 0 {
                resetPending()
                return parse(line)
            }
            pending.append(line)
            pendingScanner.scan("\n")
            pendingScanner.scan(line)
            guard pendingScanner.depth <= 0 else {
                if pending.count >= Self.maxPendingLines { resetPending() }
                return []
            }
            let joined = pending.joined(separator: "\n")
            resetPending()
            return parse(joined)
        }
        if startsObject {
            var scanner = BraceScanner()
            scanner.scan(line)
            if scanner.depth > 0 {
                pending = [line]
                pendingScanner = scanner
                return []
            }
        }
        return parse(line)
    }

    private mutating func resetPending() {
        pending = []
        pendingScanner = BraceScanner()
    }

    /// 去掉 <think>…</think> 段（可能跨行，状态保存在 isThinking）
    private mutating func removingThinking(_ line: String) -> String {
        var rest = Substring(line)
        var output = ""
        while true {
            if isThinking {
                guard let end = rest.range(of: "</think>") else { return output }
                rest = rest[end.upperBound...]
                isThinking = false
            } else {
                guard let start = rest.range(of: "<think>") else { return output + rest }
                output += rest[..<start.lowerBound]
                rest = rest[start.upperBound...]
                isThinking = true
            }
        }
    }

    /// 取第一个 { 到最后一个 } 之间的内容：先按单个对象解析，失败再按「逗号分隔的多个对象」解析
    private mutating func parse(_ text: String) -> [BlockTranslation] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return [] }
        let json = String(text[start...end])
        let decoder = JSONDecoder()
        if let item = try? decoder.decode(Item.self, from: Data(json.utf8)) {
            return accept([item])
        }
        let items = (try? decoder.decode([LenientItem].self, from: Data("[\(json)]".utf8))) ?? []
        return accept(items.compactMap(\.item))
    }

    private mutating func accept(_ items: [Item]) -> [BlockTranslation] {
        items.compactMap { item in
            guard let length = sourceLengths[item.id], !delivered.contains(item.id) else { return nil }
            let text = Self.sanitize(item.text, limit: 4 * length + 200)
            guard !text.isEmpty else { return nil }
            delivered.insert(item.id)
            return BlockTranslation(blockID: item.id, text: text)
        }
    }

    /// 字符串之外的花括号深度（{ 加一，} 减一）
    static func braceDepth(_ text: String) -> Int {
        var scanner = BraceScanner()
        scanner.scan(text)
        return scanner.depth
    }

    /// 译文只作为纯文本绘制：换行、制表符与行 / 段分隔符改为空格；去掉其他控制字符与全部格式字符
    /// （零宽字符、双向文本覆盖、软连字符等）；按 Unicode 标量截断到上限（叠加组合符号无法绕过）
    static func sanitize(_ text: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .lineSeparator, .paragraphSeparator:
                scalars.append(" ")
            case .control:
                if scalar == "\n" || scalar == "\r" || scalar == "\t" { scalars.append(" ") }
            case .format:
                continue
            default:
                scalars.append(scalar)
            }
        }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.unicodeScalars.count > limit else { return cleaned }
        return String(String.UnicodeScalarView(cleaned.unicodeScalars.prefix(limit)))
    }

    /// 数组中的一项：无效的项跳过，不影响同一行的其他项
    private struct LenientItem: Decodable {
        let item: Item?

        init(from decoder: any Decoder) throws {
            item = try? Item(from: decoder)
        }
    }

    /// 一行译文；id 容忍写成数字字符串
    private struct Item: Decodable {
        let id: Int
        let text: String

        enum CodingKeys: String, CodingKey {
            case id
            case text
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decode(Int.self, forKey: .id) {
                id = number
            } else if let parsed = Int(try container.decode(String.self, forKey: .id)) {
                id = parsed
            } else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "id")
            }
            text = try container.decode(String.self, forKey: .text)
        }
    }
}

/// 字符串之外的花括号深度扫描，可分段喂入（跨行对象逐行累积）
struct BraceScanner: Sendable {
    private(set) var depth = 0
    private var inString = false
    private var escaped = false

    mutating func scan(_ text: String) {
        for byte in text.utf8 {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
            }
        }
    }
}
