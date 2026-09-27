import CoreGraphics
import Foundation

/// 文字识别结果的阅读顺序（Vision 适配在 App 层 TextRecognizer）：
/// 从上到下分行，同一行内从左到右以空格连接，行与行以换行连接
public enum TextReadingOrder {
    /// 一段识别结果；box 为 Vision 的归一化坐标（左下原点，y 向上）
    public struct Fragment: Equatable, Sendable {
        public let text: String
        public let box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// 按阅读顺序拼成整段文本；没有文字时为空串
    public static func text(_ fragments: [Fragment]) -> String {
        lines(fragments).joined(separator: "\n")
    }

    /// 判定同一行：片段的垂直中心落在该行首个片段的上下边界之内（容忍轻微倾斜与字号差异）
    public static func lines(_ fragments: [Fragment]) -> [String] {
        let cleaned = fragments.compactMap { fragment -> Fragment? in
            let text = fragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Fragment(text: text, box: fragment.box)
        }
        let rows = cleaned.sorted { $0.box.midY > $1.box.midY }.reduce(into: [[Fragment]]()) { rows, fragment in
            if let anchor = rows.last?.first, anchor.box.minY...anchor.box.maxY ~= fragment.box.midY {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }
}
