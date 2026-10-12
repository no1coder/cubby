import CubbyCore
import SwiftUI

/// 设置 › 通用 › 外观：三张缩略图（跟随系统 / 浅色 / 深色），选中项带 2pt 强调色外环与光晕
struct AppearancePicker: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(spacing: AppearanceThumbnail.spacing) {
            ForEach(AppAppearance.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    AppearanceOptionLabel(appearance: option, isSelected: option == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Appearance"))
    }
}

/// 一个选项：缩略图 + 名称
private struct AppearanceOptionLabel: View {
    let appearance: AppAppearance
    let isSelected: Bool

    var body: some View {
        VStack(spacing: AppearanceThumbnail.labelSpacing) {
            AppearanceThumbnail(appearance: appearance)
                .overlay { if isSelected { ThumbnailSelectionRing(cornerRadius: AppearanceThumbnail.cornerRadius) } }
            Text(appearance.displayName)
                .font(.system(size: FontSize.footnote, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
        }
        .contentShape(Rectangle())
    }
}

/// 缩略图选中外环，与选中卡片一致：2pt 强调色外环，再往外 3pt 的 25% 强调色光晕。
/// 外观与面板位置两组缩略图共用
struct ThumbnailSelectionRing: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(-1)
            RoundedRectangle(cornerRadius: cornerRadius + 3.5, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 3)
                .padding(-3.5)
        }
    }
}

/// 外观缩略图：画一块桌面与一个小面板；「跟随系统」左半浅、右半深。
/// 颜色表示的是外观本身，所以在任何外观下都固定不变
struct AppearanceThumbnail: View {
    static let size = CGSize(width: 104, height: 66)
    static let cornerRadius = Radius.control
    static let spacing: CGFloat = 18
    static let labelSpacing: CGFloat = 7

    private static let panelSize = CGSize(width: 36, height: 46)
    private static let panelTop: CGFloat = 10
    private static let lightDesktop = Color(red: 0.875, green: 0.894, blue: 0.949)
    private static let darkDesktop = Color(red: 0.106, green: 0.125, blue: 0.2)
    private static let lightPanel = Color.white.opacity(0.9)
    private static let darkPanel = Color(red: 0.235, green: 0.243, blue: 0.298).opacity(0.95)

    let appearance: AppAppearance

    var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch appearance {
        case .system:
            HStack(spacing: 0) {
                desktop(Self.lightDesktop, panel: Self.lightPanel, panelLeading: 10)
                desktop(Self.darkDesktop, panel: Self.darkPanel, panelLeading: 6)
            }
        case .light:
            desktop(Self.lightDesktop, panel: Self.lightPanel, panelLeading: nil)
        case .dark:
            desktop(Self.darkDesktop, panel: Self.darkPanel, panelLeading: nil)
        }
    }

    /// panelLeading 为 nil 时小面板水平居中
    private func desktop(_ background: Color, panel: Color, panelLeading: CGFloat?) -> some View {
        background.overlay(alignment: panelLeading == nil ? .top : .topLeading) {
            RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous)
                .fill(panel)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .frame(width: Self.panelSize.width, height: Self.panelSize.height)
                .padding(.top, Self.panelTop)
                .padding(.leading, panelLeading ?? 0)
        }
    }
}
