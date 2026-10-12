import SwiftUI
import CubbyCore

/// 地址守护的配色（设计稿 TamperAlert / PanelSecurity / SettingsSecurity）：深色外观用设计稿的浅色字，浅色外观加深一级
enum SecurityPalette {
    static let red = Color(red: 1, green: 0.271, blue: 0.227)
    static let green = Color(red: 0.188, green: 0.82, blue: 0.345)

    static func redText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 0.541, blue: 0.502) : Color(red: 0.78, green: 0.16, blue: 0.12)
    }

    static func greenText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.373, green: 0.878, blue: 0.486) : Color(red: 0.08, green: 0.5, blue: 0.2)
    }
}

/// 警示卡：红色描边与光晕、盾牌图标、标题与说明、「你复制的 / 现在剪贴板里的」对照、脚注与三个操作
struct TamperAlertView: View {
    let incident: TamperIncident
    let onViewLog: () -> Void
    let onChangedMyself: () -> Void
    let onRestore: () -> Void

    static let width: CGFloat = 620
    /// 描边外的光晕与投影要留出的空间
    static let outerMargin: CGFloat = 40
    private static let cornerRadius: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let copy = TamperAlertCopy(incident: incident)
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 16) {
            header(copy)
            VStack(spacing: 10) {
                originalRow(copy)
                replacementRow(copy)
            }
            Text(TamperAlertCopy.footnote)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(Color.primary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24))
        .frame(width: Self.width)
        .background(shape.fill(.regularMaterial))
        .background(shape.fill(SecurityPalette.red.opacity(colorScheme == .dark ? 0.08 : 0.04)))
        .overlay(shape.strokeBorder(SecurityPalette.red.opacity(0.55), lineWidth: 1))
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius + 6, style: .continuous)
                .fill(SecurityPalette.red.opacity(0.14))
                .padding(-6)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 30, y: 16)
        .padding(Self.outerMargin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TamperAlertCopy.title)
    }

    private func header(_ copy: TamperAlertCopy) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(SecurityPalette.red)
                        .shadow(color: SecurityPalette.red.opacity(0.45), radius: 9, y: 6)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(TamperAlertCopy.title)
                    .font(.system(size: FontSize.display, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                (Text(verbatim: copy.whatHappened + " " + copy.why + " ")
                    .foregroundStyle(Color.primary.opacity(0.75))
                    + Text(verbatim: TamperAlertCopy.checkFirst).fontWeight(.semibold).foregroundStyle(Color.primary))
                    .font(.system(size: FontSize.body))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func originalRow(_ copy: TamperAlertCopy) -> some View {
        let value = incident.tamper.original.value.value
        return ComparisonRow(
            label: TamperAlertCopy.youCopied, meta: copy.originalMeta, trailing: copy.originalCheck,
            tint: SecurityPalette.green, labelColor: SecurityPalette.greenText(colorScheme), trailingColor: nil,
            value: AddressText.attributed(value, style: AddressText.Style(size: 16)))
    }

    private func replacementRow(_ copy: TamperAlertCopy) -> some View {
        let original = incident.tamper.original.value.value
        let replaced = incident.tamper.replacement.value
        let style = AddressText.Style(
            size: 16, highlightBackground: SecurityPalette.red.opacity(0.35),
            highlightForeground: colorScheme == .dark ? .white : nil)
        return ComparisonRow(
            label: TamperAlertCopy.nowInClipboard, meta: copy.replacementMeta, trailing: copy.difference,
            tint: SecurityPalette.red, labelColor: SecurityPalette.redText(colorScheme),
            trailingColor: SecurityPalette.redText(colorScheme),
            value: AddressText.attributed(
                replaced, style: style,
                highlights: Self.differingSpan(original: original, replaced: replaced)))
    }

    /// 从第一个不同的字符到最后一个不同的字符连成一段标红（设计稿）：中间碰巧相同的个别字符不留空隙，更醒目
    private static func differingSpan(original: String, replaced: String) -> [Range<Int>] {
        let ranges = AddressComparison.differingRanges(original: original, replaced: replaced)
        guard let first = ranges.first, let last = ranges.last else { return [] }
        return [first.lowerBound..<last.upperBound]
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(TamperAlertCopy.viewLog, action: onViewLog)
                .buttonStyle(.link)
                .font(.system(size: FontSize.footnote))
            Spacer(minLength: 8)
            Button(TamperAlertCopy.changedMyself, action: onChangedMyself)
                .buttonStyle(AlertButtonStyle(isPrimary: false))
            Button(TamperAlertCopy.restore, action: onRestore)
                .buttonStyle(AlertButtonStyle(isPrimary: true))
        }
    }
}

/// 对照的一行：彩色小标签 + 来源 · 时间 + 右侧说明，下面是分组显示的值
private struct ComparisonRow: View {
    let label: String
    let meta: String
    let trailing: String
    let tint: Color
    let labelColor: Color
    let trailingColor: Color?
    let value: AttributedString

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            // 放不下一行时（较长的语言）右侧说明换到第二行
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    labelAndMeta
                    Spacer(minLength: 8)
                    trailingText
                }
                VStack(alignment: .leading, spacing: 4) {
                    labelAndMeta
                    trailingText
                }
            }
            .font(.system(size: FontSize.caption))
            Text(value)
                .lineSpacing(3)
                .textSelection(.disabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(tint.opacity(0.11)))
        .overlay(shape.strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var labelAndMeta: some View {
        HStack(spacing: 8) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(labelColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule().fill(tint.opacity(0.25)))
            Text(meta)
                .foregroundStyle(Color.primary.opacity(0.65))
        }
        .fixedSize()
    }

    private var trailingText: some View {
        Text(trailing)
            .foregroundStyle(trailingColor ?? Color.primary.opacity(0.65))
            .fixedSize()
    }
}

/// 警示卡的按钮：34pt 高、10pt 圆角；主按钮为实心强调色
struct AlertButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: FontSize.body, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? Color.white : Color.primary.opacity(0.9))
            .padding(.horizontal, isPrimary ? 18 : 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPrimary ? Color.accentColor : Color.primary.opacity(0.1))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}
