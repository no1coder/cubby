import CubbyCore
import SwiftUI

/// 设置 › 通用 › 快捷键与面板 › 面板位置：五张缩略图排成一行（鼠标旁 / 菜单栏图标下 / 屏幕中央 / 固定右侧 / 固定底部），
/// 选中项与外观缩略图一样带强调色外环（docs/UI-UPGRADE-PLAN.md 第 3 节）
struct PanelPositionPicker: View {
    @Binding var selection: PanelPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 可见的标题同时作为读屏的分组标题，分组本身不再重复朗读
            Text("Panel position")
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: PanelPositionThumbnail.spacing) {
                ForEach(PanelPosition.allCases, id: \.self) { position in
                    Button {
                        selection = position
                    } label: {
                        PanelPositionOptionLabel(position: position, isSelected: position == selection)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(position.displayName)
                    .accessibilityAddTraits(position == selection ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
        }
    }
}

/// 一个选项：缩略图 + 名称（名称较长，最多两行居中）
private struct PanelPositionOptionLabel: View {
    let position: PanelPosition
    let isSelected: Bool

    var body: some View {
        VStack(spacing: PanelPositionThumbnail.labelSpacing) {
            PanelPositionThumbnail(position: position, isSelected: isSelected)
                .overlay {
                    if isSelected { ThumbnailSelectionRing(cornerRadius: PanelPositionThumbnail.cornerRadius) }
                }
            Text(position.displayName)
                .font(.system(size: FontSize.footnote, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
    }
}

/// 面板位置缩略图：一块小桌面，面板画在它会出现的地方。宽度随设置页均分，高度固定。
/// 桌面颜色随设置窗口的深浅外观（与设计稿一致），表示的是屏幕而不是系统控件
struct PanelPositionThumbnail: View {
    static let height: CGFloat = 54
    static let cornerRadius = Radius.control
    static let spacing: CGFloat = 8
    static let labelSpacing: CGFloat = 6

    /// 浮动面板的小矩形
    private static let floatingPanelSize = CGSize(width: 20, height: 30)
    /// 停靠面板与缩略图边缘的距离（圆角与外框同心）
    private static let dockInset: CGFloat = 3
    private static let sidebarWidth: CGFloat = 18
    private static let shelfHeight: CGFloat = 16
    private static let menuBarHeight: CGFloat = 5

    let position: PanelPosition
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        palette.desktop
            .overlay { content }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch position {
        case .mouse:
            ZStack(alignment: .topLeading) {
                Color.clear
                floatingPanel
                    .offset(x: 34, y: 13)
                Image(systemName: "cursorarrow")
                    .font(.system(size: FontSize.caption2, weight: .semibold))
                    .foregroundStyle(palette.pointer)
                    .offset(x: 24, y: 6)
            }
        case .statusItem:
            ZStack(alignment: .topTrailing) {
                Color.clear
                Rectangle()
                    .fill(palette.menuBar)
                    .frame(height: Self.menuBarHeight)
                    .frame(maxWidth: .infinity)
                // 菜单栏图标与它下方的面板
                Rectangle()
                    .fill(palette.pointer.opacity(0.8))
                    .frame(width: 4, height: 3)
                    .offset(x: -(14 + Self.floatingPanelSize.width / 2 - 2), y: 1)
                floatingPanel
                    .offset(x: -14, y: Self.menuBarHeight + 3)
            }
        case .center:
            floatingPanel
        case .dockRight:
            HStack {
                Spacer(minLength: 0)
                dockedPanel.frame(width: Self.sidebarWidth)
            }
            .padding(Self.dockInset)
        case .dockBottom:
            VStack {
                Spacer(minLength: 0)
                dockedPanel.frame(height: Self.shelfHeight)
            }
            .padding(Self.dockInset)
        }
    }

    private var floatingPanel: some View {
        RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
            .fill(palette.panel(isSelected: isSelected))
            .shadow(color: .black.opacity(palette.shadowOpacity), radius: 2, y: 1)
            .frame(width: Self.floatingPanelSize.width, height: Self.floatingPanelSize.height)
    }

    private var dockedPanel: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius - Self.dockInset, style: .continuous)
            .fill(palette.panel(isSelected: isSelected))
            .shadow(color: .black.opacity(palette.shadowOpacity), radius: 2, y: 1)
    }

    private var palette: Palette {
        colorScheme == .dark ? .dark : .light
    }

    /// 缩略图配色（取自 docs/design/ui-upgrade/src/Settings.dc.html）
    private struct Palette {
        let desktop: Color
        let menuBar: Color
        let pointer: Color
        let panelOpacity: Double
        let selectedPanelOpacity: Double
        let shadowOpacity: Double

        func panel(isSelected: Bool) -> Color {
            Color.white.opacity(isSelected ? selectedPanelOpacity : panelOpacity)
        }

        static let dark = Palette(
            desktop: Color(red: 0.169, green: 0.2, blue: 0.275),
            menuBar: Color.white.opacity(0.18),
            pointer: .white,
            panelOpacity: 0.75,
            selectedPanelOpacity: 0.85,
            shadowOpacity: 0.3
        )

        static let light = Palette(
            desktop: Color(red: 0.875, green: 0.894, blue: 0.949),
            menuBar: Color.white.opacity(0.6),
            pointer: Color(red: 0.11, green: 0.12, blue: 0.16),
            panelOpacity: 0.95,
            selectedPanelOpacity: 1,
            shadowOpacity: 0.12
        )
    }
}
