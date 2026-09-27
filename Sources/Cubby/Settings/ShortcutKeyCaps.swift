import SwiftUI

/// 设置与引导中使用的键帽：比面板里的 KeyCap 更大、更立体。
/// 圆角与描边与面板 KeyCap 保持一致（Radius.key、0.5pt `primary 0.1`），额外保留底部轻微投影。
struct ShortcutKeyCap: View {
    let symbol: String
    var isDimmed = false

    @Environment(\.colorScheme) private var colorScheme

    private static let minSide: CGFloat = 22
    private static let horizontalInset: CGFloat = 6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        Text(symbol)
            .font(.system(size: FontSize.footnote, weight: .semibold, design: .rounded))
            .foregroundStyle(isDimmed ? .secondary : .primary)
            .padding(.horizontal, Self.horizontalInset)
            .frame(minWidth: Self.minSide, minHeight: Self.minSide)
            .background(
                shape
                    .fill(capFill)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 0, y: 1)
            )
            .overlay(
                shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    private var capFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white
    }
}

/// 一组键帽，例如 ⇧ ⌘ V
struct ShortcutKeyCaps: View {
    let symbols: [String]
    var isDimmed = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                ShortcutKeyCap(symbol: symbol, isDimmed: isDimmed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(symbols.joined())
    }
}
