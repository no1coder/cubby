import CoreGraphics
import Foundation

/// 放不下时的三步（§1.1）：① 向同色空白扩展 → ② 以 0.5 pt 步长缩小字号，最低 75% → ③ 末尾省略号
///
/// 多行块按原文行距折行，高度不超过原文块高 + 向下可扩展的高度；单行块优先一行排完，
/// 一行缩到 75% 仍放不下、且下方同色空白能多排一行时才按 1.3 倍字号的行距折行。
enum TranslationFitter {
    static let shrinkStep: CGFloat = 0.5
    static let minimumScale: CGFloat = 0.75

    struct Request {
        let text: String
        let style: TranslationTypesetter.Style
        let isMultiLine: Bool
        /// 原文可用宽度（点）
        let width: CGFloat
        /// 原文块高（点，首行顶到末行底）
        let height: CGFloat
        /// 原文行框高与行距（点，基准字号下；缩字时等比缩放）
        let lineHeight: CGFloat
        let pitch: CGFloat
        /// 同色空白可扩展的宽度 / 高度（点）；非纯色背景为 0
        let extraWidth: CGFloat
        let extraHeight: CGFloat
    }

    /// 最终字号、各行文字与（随字号等比缩放的）行距
    struct Result: Equatable {
        let style: TranslationTypesetter.Style
        let lines: [String]
        let pitch: CGFloat
    }

    /// 排法：一行排完，或按宽度折行
    enum Mode {
        case oneLine
        case wrapped
    }

    static func fit(_ request: Request) -> Result {
        let base = request.style.fontSize
        let primary: Mode = request.isMultiLine ? .wrapped : .oneLine
        if let lines = attempt(request, primary, size: base, width: request.width, height: request.height) {
            return result(request, size: base, lines: lines)
        }
        let width = request.width + request.extraWidth
        let height = request.height + request.extraHeight
        // 单行块优先一行排完（可缩字）；仍放不下且下方同色空白还能多排一行时才折行
        let canWrap = request.isMultiLine || maxLines(request, size: base, height: height) >= 2
        let modes: [Mode] = request.isMultiLine ? [.wrapped] : (canWrap ? [.oneLine, .wrapped] : [.oneLine])
        for mode in modes {
            for size in sizes(from: base) {
                if let lines = attempt(request, mode, size: size, width: width, height: height) {
                    return result(request, size: size, lines: lines)
                }
            }
        }
        let smallest = sizes(from: base).last ?? base
        let lines = truncatedLines(request, modes.last ?? primary, size: smallest, width: width, height: height)
        return result(request, size: smallest, lines: lines)
    }

    /// 基准字号起（含）以 0.5 pt 递减到 75%
    static func sizes(from base: CGFloat) -> [CGFloat] {
        let floor = base * minimumScale
        return stride(from: base, through: floor - 0.001, by: -shrinkStep).filter { $0 >= floor - 0.001 }
    }

    /// 某字号下能放下时返回各行
    private static func attempt(_ request: Request, _ mode: Mode, size: CGFloat, width: CGFloat, height: CGFloat)
        -> [String]?
    {
        let style = request.style.resized(size)
        switch mode {
        case .oneLine:
            let text = request.text.replacingOccurrences(of: "\n", with: " ")
            return TranslationTypesetter.width(of: text, style: style) <= width + 0.01 ? [text] : nil
        case .wrapped:
            let lines = TranslationTypesetter.breakLines(request.text, style: style, width: width)
            return lines.count <= maxLines(request, size: size, height: height) ? lines : nil
        }
    }

    /// 高度 height 内能放几行：(n − 1) × 行距 + 行框高 ≤ height
    private static func maxLines(_ request: Request, size: CGFloat, height: CGFloat) -> Int {
        let ratio = size / request.style.fontSize
        let pitch = request.pitch * ratio
        let lineHeight = request.lineHeight * ratio
        guard pitch > 0 else { return 1 }
        return max(1, Int(((height - lineHeight) / pitch + 0.001).rounded(.down)) + 1)
    }

    private static func truncatedLines(
        _ request: Request, _ mode: Mode, size: CGFloat, width: CGFloat, height: CGFloat
    ) -> [String] {
        let style = request.style.resized(size)
        guard mode == .wrapped else {
            let text = request.text.replacingOccurrences(of: "\n", with: " ")
            return [TranslationTypesetter.truncated(text, style: style, width: width)]
        }
        let lines = TranslationTypesetter.breakLines(request.text, style: style, width: width)
        let count = maxLines(request, size: size, height: height)
        let kept = Array(lines.prefix(count - 1))
        let rest = TextBlockBuilder.joined(Array(lines.dropFirst(count - 1)))
        return kept + [TranslationTypesetter.truncated(rest, style: style, width: width)]
    }

    private static func result(_ request: Request, size: CGFloat, lines: [String]) -> Result {
        Result(style: request.style.resized(size), lines: lines, pitch: request.pitch * size / request.style.fontSize)
    }
}
