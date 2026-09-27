import CoreGraphics
import Foundation

/// 文档识别的一个单词（像素坐标，左上原点）
public struct OCRWord: Equatable, Sendable {
    public let text: String
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// 文档识别的一行（像素坐标，左上原点）及落在其中的单词
public struct OCRLine: Equatable, Sendable {
    public let text: String
    public let box: CGRect
    /// 从左到右
    public let words: [OCRWord]

    public init(text: String, box: CGRect, words: [OCRWord] = []) {
        self.text = text
        self.box = box
        self.words = words.sorted { $0.box.minX < $1.box.minX }
    }

    /// 平移（分片 / 裁剪图坐标 → 整张图坐标）
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> OCRLine {
        OCRLine(
            text: text, box: box.offsetBy(dx: dx, dy: dy),
            words: words.map { OCRWord(text: $0.text, box: $0.box.offsetBy(dx: dx, dy: dy)) })
    }
}

/// 文档识别结果 → 分组的行（§3.2 第 2–5 步中与 Vision 无关的部分，纯函数）
public enum DocumentLineGrouping {
    /// 把一个容器的单词分给各行：单词中心落在行框内（Vision 的单词按段落给出，不按行）
    public static func lines(_ lines: [(text: String, box: CGRect)], words: [OCRWord]) -> [OCRLine] {
        lines.map { line in
            OCRLine(
                text: line.text, box: line.box,
                words: words.filter { line.box.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) })
        }
    }

    /// 含假名（需要以日文优先再识别一次，§3.2 第 3 步）
    public static func containsKana(_ text: String) -> Bool {
        TextScript.containsKana(text)
    }

    /// 同一行可能同时出现在标题、段落、列表项、单元格等多个容器里：每行只归入行数最少（最小）的容器。
    /// 同一行按「文本 + 4 像素网格上的位置」识别；返回的组保持容器原顺序，空组被丢弃
    public static func smallestContainers(_ containers: [[OCRLine]]) -> [[OCRLine]] {
        let order = containers.indices.sorted { containers[$0].count < containers[$1].count }
        var used = Set<String>()
        var chosen = [Int: [OCRLine]]()
        for index in order {
            let fresh = containers[index].filter { !used.contains(key($0)) }
            fresh.forEach { used.insert(key($0)) }
            if !fresh.isEmpty { chosen[index] = fresh }
        }
        return containers.indices.compactMap { chosen[$0] }
    }

    /// 一个分片的全部容器 → 整张图坐标下、中心落在该分片 core 内的行（按最小容器分组，空组丢弃）
    public static func groups(_ containers: [[OCRLine]], from tile: RecognitionTile) -> [[OCRLine]] {
        smallestContainers(containers).compactMap { group in
            let kept = group.map { $0.offsetBy(dx: tile.rect.minX, dy: tile.rect.minY) }.filter {
                tile.core.contains(CGPoint(x: $0.box.midX, y: $0.box.midY))
            }
            return kept.isEmpty ? nil : kept
        }
    }

    /// 行首带列表符号（•、◦、▪、・、1.、a) 等）的行另起一组；破折号与星号只在组的首行也以符号开头时才算列表，
    /// 避免把以破折号开头的续行拆开。符号从文字中去掉，行框收窄到正文第一个单词，使符号像素保留在原图上
    public static func splittingListItems(_ group: [OCRLine]) -> [[OCRLine]] {
        let isList = group.first.map { strippingMarker($0, allowDash: true) != nil } ?? false
        return group.enumerated().reduce(into: [[OCRLine]]()) { groups, element in
            let (index, line) = element
            if let stripped = strippingMarker(line, allowDash: index == 0 || isList) {
                groups.append([stripped])
            } else if groups.isEmpty {
                groups.append([line])
            } else {
                groups[groups.count - 1].append(line)
            }
        }
    }

    /// 去掉行首列表符号；没有符号（或去掉后没有正文）时为 nil
    static func strippingMarker(_ line: OCRLine, allowDash: Bool) -> OCRLine? {
        let text = line.text
        guard let match = marker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else { return nil }
        let symbol = text[range].trimmingCharacters(in: .whitespaces)
        guard allowDash || !dashes.contains(symbol) else { return nil }
        let body = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        let (minX, bodyWords) = bodyStart(
            line, symbol: symbol, markerLength: text.distance(from: text.startIndex, to: range.upperBound))
        let box = CGRect(x: minX, y: line.box.minY, width: max(0, line.box.maxX - minX), height: line.box.height)
        return OCRLine(text: body, box: box, words: bodyWords)
    }

    /// 正文起点：首个单词就是符号时取下一个单词的左缘；符号与正文粘成一个单词（「・iCloud」）时按字符比例切开；
    /// 没有单词框时按整行字符比例估计
    private static func bodyStart(_ line: OCRLine, symbol: String, markerLength: Int) -> (CGFloat, [OCRWord]) {
        guard let first = line.words.first else {
            let fraction = CGFloat(markerLength) / CGFloat(max(line.text.count, 1))
            return (line.box.minX + line.box.width * fraction, [])
        }
        if first.text == symbol {
            let rest = Array(line.words.dropFirst())
            return (rest.first?.box.minX ?? first.box.maxX, rest)
        }
        let fraction = first.text.hasPrefix(symbol) ? CGFloat(symbol.count) / CGFloat(max(first.text.count, 1)) : 0
        return (first.box.minX + first.box.width * fraction, line.words)
    }

    private static let dashes: Set<String> = ["-", "*", "\u{2013}", "\u{2014}"]

    /// 行首列表符号：项目符号（含日文的「・」，后面可以不跟空白），或破折号、星号、1. 1) (1) a. a) 这类编号（后面必须跟空白）
    private static let marker: NSRegularExpression = {
        let bullets =
            "[\u{2022}\u{25E6}\u{25AA}\u{25AB}\u{2023}\u{2043}\u{25CF}\u{25CB}\u{25A0}\u{25A1}"
            + "\u{25C6}\u{25C7}\u{00B7}\u{30FB}\u{FF65}]"
        let dashes = "[\u{2013}\u{2014}*-]"
        let numbers = #"\(?(\d{1,3}|[A-Za-z])[.)]"#
        // 模式是编译期常量，失败即编程错误
        return try! NSRegularExpression(pattern: "^\\s*(\(bullets)\\s*|(\(dashes)|\(numbers))\\s+)")
    }()

    private static func key(_ line: OCRLine) -> String {
        "\(Int(line.box.minX / 4)),\(Int(line.box.minY / 4)),\(line.text)"
    }
}
