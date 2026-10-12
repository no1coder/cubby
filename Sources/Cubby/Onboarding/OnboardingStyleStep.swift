import SwiftUI
import CubbyCore

/// 第 3 步「选择样子」（画板 Onboarding）：三张大卡片选面板排布，选中即写入 settings.panelPosition；
/// 下方外观分段控件绑定 settings.appearance，立即作用于所有窗口（AppDelegate 监听并应用）。
/// 键盘：Tab 在卡片间移动焦点，空格选中焦点卡片，← → 直接选中相邻的卡片
struct OnboardingStyleStep: View {
    private static let cardSpacing: CGFloat = 16
    /// 设计稿：卡片区与外观行间距 22，「外观」与分段控件间距 12
    private static let appearanceTopSpacing: CGFloat = 22
    private static let appearanceLabelSpacing: CGFloat = 12

    @Bindable var settings: AppSettings
    @FocusState private var focusedLayout: PanelLayout?

    private var selectedLayout: PanelLayout { settings.panelPosition.layout }

    var body: some View {
        VStack(spacing: 26) {
            OnboardingStepHeader(
                title: String(
                    localized: "Where do you want your clipboard to appear?",
                    comment: "Onboarding: title of the style step"
                ),
                subtitle: String(
                    localized: "You can switch any time from the panel's top bar or Settings › General.",
                    comment: "Onboarding: subtitle of the style step"
                )
            )
            VStack(spacing: Self.appearanceTopSpacing) {
                cards
                appearance
            }
        }
        .onAppear { focusedLayout = selectedLayout }
    }

    private var cards: some View {
        HStack(spacing: Self.cardSpacing) {
            ForEach(PanelLayout.allCases, id: \.self) { layout in
                OnboardingStyleCard(
                    layout: layout,
                    isSelected: layout == selectedLayout,
                    isFocused: focusedLayout == layout,
                    onSelect: { select(layout) }
                )
                .focused($focusedLayout, equals: layout)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onKeyPress(.leftArrow) { moveSelection(by: -1) }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Panel position"))
    }

    private var appearance: some View {
        HStack(spacing: Self.appearanceLabelSpacing) {
            Text("Appearance")
                .font(.system(size: FontSize.body))
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - 选择

    /// 选中即生效：浮动沿用用户选过的浮动位置（鼠标旁 / 菜单栏图标下 / 屏幕中央）
    private func select(_ layout: PanelLayout) {
        let position = layout.position(floatingFallback: settings.floatingPanelPosition)
        if settings.panelPosition != position { settings.panelPosition = position }
        focusedLayout = layout
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        let layouts = PanelLayout.allCases
        guard let index = layouts.firstIndex(of: selectedLayout) else { return .ignored }
        let target = min(max(index + delta, 0), layouts.count - 1)
        select(layouts[target])
        return .handled
    }
}
