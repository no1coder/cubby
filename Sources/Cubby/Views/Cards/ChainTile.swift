import SwiftUI
import CubbyCore

/// 敏感值类型的圆形标识（PanelSecurity 设计稿）：以太坊菱形、波场红色 T、比特币橙色 ₿、Solana 三道斜杠、莱特币 Ł、银行卡
struct ChainTile: View {
    let kind: SensitiveKind
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            if kind == .bankCard {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color(red: 0.36, green: 0.42, blue: 0.55).gradient)
            } else {
                Circle().fill(fill)
            }
            glyph
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .ethereum: AnyShapeStyle(Color(red: 0.384, green: 0.494, blue: 0.918))
        case .tron: AnyShapeStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
        case .bitcoin: AnyShapeStyle(Color(red: 0.969, green: 0.576, blue: 0.102))
        case .litecoin: AnyShapeStyle(Color(red: 0.204, green: 0.365, blue: 0.616))
        case .solana:
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.6, green: 0.27, blue: 1), Color(red: 0.08, green: 0.95, blue: 0.58)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        case .bankCard: AnyShapeStyle(Color.gray)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .ethereum: EthereumDiamond().frame(width: size * 0.46, height: size * 0.62)
        case .solana: SolanaBars().frame(width: size * 0.5, height: size * 0.42)
        case .bankCard: Image(systemName: "creditcard").font(.system(size: size * 0.46, weight: .semibold))
        case .tron: letter("T")
        case .bitcoin: letter("\u{20BF}")
        case .litecoin: letter("\u{0141}")
        }
    }

    private func letter(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: size * 0.5, weight: .bold))
    }
}

/// 以太坊的菱形：上半为略淡的四边形，下半为倒三角（设计稿的 SVG）
private struct EthereumDiamond: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            var top = Path()
            top.move(to: CGPoint(x: width / 2, y: 0))
            top.addLine(to: CGPoint(x: width, y: height * 0.5))
            top.addLine(to: CGPoint(x: width / 2, y: height * 0.69))
            top.addLine(to: CGPoint(x: 0, y: height * 0.5))
            top.closeSubpath()
            context.fill(top, with: .color(.white.opacity(0.9)))
            var bottom = Path()
            bottom.move(to: CGPoint(x: width / 2, y: height * 0.75))
            bottom.addLine(to: CGPoint(x: width, y: height * 0.56))
            bottom.addLine(to: CGPoint(x: width / 2, y: height))
            bottom.addLine(to: CGPoint(x: 0, y: height * 0.56))
            bottom.closeSubpath()
            context.fill(bottom, with: .color(.white))
        }
    }
}

/// Solana 的三道斜杠
private struct SolanaBars: View {
    var body: some View {
        Canvas { context, size in
            let barHeight = size.height * 0.22
            let skew = size.width * 0.2
            for index in 0..<3 {
                let y = CGFloat(index) * (size.height - barHeight) / 2
                var bar = Path()
                // 中间一道反向倾斜
                let leftShift = index == 1 ? 0 : skew
                let rightShift = index == 1 ? skew : 0
                bar.move(to: CGPoint(x: leftShift, y: y))
                bar.addLine(to: CGPoint(x: size.width - rightShift, y: y))
                bar.addLine(to: CGPoint(x: size.width - skew + rightShift, y: y + barHeight))
                bar.addLine(to: CGPoint(x: skew - leftShift, y: y + barHeight))
                bar.closeSubpath()
                context.fill(bar, with: .color(.white))
            }
        }
    }
}
