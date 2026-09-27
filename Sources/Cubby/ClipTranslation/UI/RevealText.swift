import SwiftUI

/// 一段译文到达时的逐字显现（A9：约 150–300 ms，不做逐 token）。
/// 整段一次排版，只按字形顺序渐显，因此显现过程中高度不变、不跳动；减弱动态效果或缓存命中时直接显示
struct RevealText: View {
    let text: AttributedString
    /// false：直接显示（缓存命中、非首次出现）
    let animates: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    /// 显现时长：按字数在 150–300 ms 之间
    static func duration(for text: AttributedString) -> Double {
        let count = Double(text.characters.count)
        return min(max(0.15 + count * 0.002, 0.15), 0.3)
    }

    var body: some View {
        if !animates || reduceMotion {
            // 不做显现时不挂自定义渲染器：外层的 foregroundStyle（对照视图里的次要色原文）照常生效
            Text(text)
        } else if #available(macOS 15, *) {
            Text(text)
                .textRenderer(RevealRenderer(progress: progress))
                .onAppear {
                    withAnimation(.linear(duration: Self.duration(for: text))) { progress = 1 }
                }
        } else {
            Text(text)
        }
    }
}

/// 按字形顺序渐显：progress 0…1，每个字形在 fadeWidth 个字形的区间内淡入
@available(macOS 15, *)
private struct RevealRenderer: TextRenderer, Animatable {
    var progress: Double
    private static let fadeWidth = 6.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard progress < 1 else {
            for line in layout { context.draw(line) }
            return
        }
        let total = Double(layout.reduce(0) { sum, line in sum + line.reduce(0) { $0 + $1.count } })
        let front = progress * (total + Self.fadeWidth)
        var index = 0.0
        for line in layout {
            for run in line {
                for glyph in run {
                    let opacity = min(max((front - index) / Self.fadeWidth, 0), 1)
                    index += 1
                    guard opacity > 0 else { continue }
                    var copy = context
                    copy.opacity = opacity
                    copy.draw(glyph)
                }
            }
        }
    }
}
