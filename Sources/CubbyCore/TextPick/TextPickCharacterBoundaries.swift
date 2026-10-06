import Foundation

/// 原文的字符（Character）边界。分词器给出的位置经 UTF-8 偏移换回原文，可能落在一个字符的中间：
/// 「(」+ U+0301 在 Swift 里是一个字符，NLTokenizer 却可能从 U+0301 起一个词。
/// 不对齐的话相邻两块会重叠，拼接结果时构造出反向区间而崩溃（docs/TEXT-PICK-DESIGN.md P5）
struct TextPickCharacterBoundaries {
    /// 每个字符的起点，最后加上 endIndex；至少有一项
    private let starts: [String.Index]

    init(_ text: String) {
        starts = Array(text.indices) + [text.endIndex]
    }

    /// 不大于 index 的最近边界
    func roundingDown(_ index: String.Index) -> String.Index {
        starts[lastPosition(atMost: index)]
    }

    /// 不小于 index 的最近边界
    func roundingUp(_ index: String.Index) -> String.Index {
        let position = lastPosition(atMost: index)
        guard starts[position] < index else { return starts[position] }
        return starts[min(position + 1, starts.count - 1)]
    }

    /// 二分查找最后一个不大于 index 的边界
    private func lastPosition(atMost index: String.Index) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= index {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }
}
