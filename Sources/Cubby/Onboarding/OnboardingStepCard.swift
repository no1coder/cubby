import AppKit
import SwiftUI

/// 引导页的步骤卡片：图标 + 标题 + 说明 +（可选）权限状态与补充说明，右侧放操作控件。
/// 已完成的步骤在图标右下角显示绿色对勾角标、文字弱化，操作控件隐藏。
struct OnboardingStepCard<Accessory: View>: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// 权限类步骤的实时状态；nil 表示无需授权的步骤
    var status: PermissionState?
    @ViewBuilder let accessory: () -> Accessory

    @Environment(\.colorScheme) private var colorScheme

    private var isDone: Bool { status?.isGranted == true }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: StepCardMetrics.textSpacing) {
                Text(title)
                    .font(.system(size: FontSize.body, weight: .semibold))
                Text(message)
                    .font(.system(size: FontSize.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let status {
                    Label(status.message, systemImage: status.level.symbolName)
                        .font(.system(size: FontSize.caption, weight: .medium))
                        .foregroundStyle(status.level.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = status?.note, !isDone {
                    Text(note)
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 占满剩余宽度，避免与 Spacer 平分导致说明文字过早换行
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isDone ? StepCardMetrics.doneOpacity : 1)
            if !isDone {
                accessory()
                    .fixedSize()
            }
        }
        .padding(.horizontal, StepCardMetrics.horizontalInset)
        .padding(.vertical, StepCardMetrics.verticalInset)
        .background(cardBackground)
        .animation(.easeOut(duration: 0.2), value: isDone)
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: FontSize.title, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: StepCardMetrics.iconSide, height: StepCardMetrics.iconSide)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(tint.gradient)
            )
            .overlay(alignment: .bottomTrailing) {
                if isDone {
                    doneBadge
                        .offset(x: StepCardMetrics.badgeOverhang, y: StepCardMetrics.badgeOverhang)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .accessibilityHidden(true)
    }

    /// 已完成角标：绿色圆底白色对勾，外圈为卡片底色，与图标底板分隔开
    private var doneBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .green)
            .font(.system(size: FontSize.callout, weight: .bold))
            .padding(StepCardMetrics.badgeRingWidth)
            .background(badgeRing)
    }

    /// 卡片底色是半透明的：先铺一层窗口底色再叠卡片底色，外圈才能与卡片融为一体
    private var badgeRing: some View {
        ZStack {
            Circle().fill(Color(nsColor: .windowBackgroundColor))
            Circle().fill(cardFill)
        }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return
            shape
            .fill(cardFill)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.92)
    }
}

/// 步骤卡片的布局常量（泛型类型不能声明静态存储属性，故单独放置）
private enum StepCardMetrics {
    static let iconSide: CGFloat = 36
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 14
    /// 标题、说明、状态之间的间距（4 在 22pt 键帽旁显得局促）
    static let textSpacing: CGFloat = 6
    static let badgeRingWidth: CGFloat = 2
    /// 角标向图标外侧探出的距离
    static let badgeOverhang: CGFloat = 4
    static let doneOpacity: Double = 0.6
}
