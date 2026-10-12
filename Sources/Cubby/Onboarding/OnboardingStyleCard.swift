import SwiftUI
import CubbyCore

extension PanelLayout {
    /// 引导「选择样子」卡片上的名称
    var onboardingTitle: String {
        switch self {
        case .floating: String(localized: "Floating Panel", comment: "Onboarding style card: panel layout name")
        case .sidebar:
            String(localized: "Docked to the Right Edge", comment: "Onboarding style card: panel layout name")
        case .shelf: String(localized: "Docked to the Bottom Edge", comment: "Onboarding style card: panel layout name")
        }
    }

    /// 引导「选择样子」卡片上的说明
    var onboardingDetail: String {
        switch self {
        case .floating:
            String(
                localized: "Appears next to the pointer, gone once you're done.",
                comment: "Onboarding style card: floating panel description")
        case .sidebar:
            String(
                localized: "A full-height sidebar shows more at once.",
                comment: "Onboarding style card: right-edge sidebar description")
        case .shelf:
            String(
                localized: "Cards side by side, great for images and large screens.",
                comment: "Onboarding style card: bottom-edge shelf description")
        }
    }
}

/// 「选择样子」的一张大卡片：缩略图 + 名称 + 说明。选中时强调色淡底、2pt 外环与 4pt 光晕；
/// 获得键盘焦点但未选中时显示一圈淡强调色描边。读屏读作带「已选中」状态的按钮
struct OnboardingStyleCard: View {
    /// 设计稿：内边距 12、元素间距 12、圆角 16、缩略图高 210
    private static let padding: CGFloat = 12
    private static let spacing: CGFloat = 12
    private static let cornerRadius: CGFloat = 16

    let layout: PanelLayout
    let isSelected: Bool
    let isFocused: Bool
    let onSelect: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Self.spacing) {
            OnboardingStyleThumbnail(layout: layout)
            Text(layout.onboardingTitle)
                .font(.system(size: FontSize.callout, weight: .semibold))
            Text(layout.onboardingDetail)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.padding)
        // 三张卡片等高：父视图按最高的一张固定高度，这里撑满
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
        .overlay { border(shape) }
        .contentShape(shape)
        .focusable()
        .focusEffectDisabled()
        .onTapGesture(perform: onSelect)
        .onKeyPress(.space) {
            onSelect()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.onboardingTitle)
        .accessibilityHint(layout.onboardingDetail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        if isSelected {
            ZStack {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
                RoundedRectangle(cornerRadius: Self.cornerRadius + 4, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .padding(-4)
            }
        } else if isFocused {
            shape.strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
        } else {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }
}

/// 卡片里的缩略图：一块桌面，面板画在它会出现的位置（浮动面板旁有指针）。
/// 桌面颜色随窗口深浅外观（深色取设计稿 #26315a，浅色与设置里的位置缩略图一致）
private struct OnboardingStyleThumbnail: View {
    private static let height: CGFloat = 210
    private static let cornerRadius: CGFloat = 10
    private static let inset: CGFloat = 6
    private static let floatingSize = CGSize(width: 84, height: 136)
    private static let sidebarWidth: CGFloat = 48
    private static let shelfHeight: CGFloat = 40

    let layout: PanelLayout

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        desktop
            .overlay { GeometryReader { proxy in content(in: proxy.size) } }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var isDark: Bool { colorScheme == .dark }

    private var desktop: Color {
        isDark ? Color(red: 0.149, green: 0.192, blue: 0.353) : Color(red: 0.875, green: 0.894, blue: 0.949)
    }

    private var panelFill: Color { Color.white.opacity(isDark ? 0.85 : 0.95) }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch layout {
        case .floating:
            // 设计稿：面板左缘在中线左侧 30、顶部 36；指针在 30% 宽处、顶部 30
            ZStack(alignment: .topLeading) {
                Color.clear
                panel(cornerRadius: 9)
                    .frame(width: Self.floatingSize.width, height: Self.floatingSize.height)
                    .offset(x: size.width / 2 - 30, y: 36)
                Image(systemName: "cursorarrow")
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .foregroundStyle(isDark ? Color.white : Color(red: 0.11, green: 0.12, blue: 0.16))
                    .offset(x: size.width * 0.3, y: 26)
            }
        case .sidebar:
            HStack {
                Spacer(minLength: 0)
                panel(cornerRadius: 8).frame(width: Self.sidebarWidth)
            }
            .padding(Self.inset)
        case .shelf:
            VStack {
                Spacer(minLength: 0)
                panel(cornerRadius: 8).frame(height: Self.shelfHeight)
            }
            .padding(Self.inset)
        }
    }

    private func panel(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(panelFill)
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.15), radius: 8, y: 6)
    }
}
