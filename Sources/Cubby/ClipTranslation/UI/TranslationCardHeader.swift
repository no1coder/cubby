import CubbyCore
import SwiftUI

/// 翻译卡头部（56pt，原型 tcHeadHTML）：来源图标 ·「翻译」· 语言胶囊「英语（自动检测）→ 简体中文」+ ⇄ 对调，
/// 下方隐私行（A6）；右侧引擎徽标（A6）
struct TranslationCardHeader: View {
    let card: TranslationCard
    let item: ClipItem
    let controller: TranslationCardController
    let openSettings: () -> Void

    @State private var pillAnchor: NSView?
    @State private var engineAnchor: NSView?

    /// 引擎简称不超过这么多字符时显示在徽标上（「系统翻译」「DeepSeek」「openrouter」）；更长的
    /// （英文「System Translation」）只显示图标，把宽度让给语言胶囊，完整名称与文字去向在悬停说明里
    private static let engineNameMaxLength = 10

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(bundleID: item.source?.bundleID, fallbackSymbol: item.kind.symbolName)
            Text(TranslationCopy.cardTitle)
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                if !isUnsupported {
                    HStack(spacing: 2) {
                        languagePill
                        swapButton
                    }
                }
                privacyLine
            }
            .padding(.leading, 2)
            .layoutPriority(1)
            Spacer(minLength: 4)
            if let plan = card.plan {
                engineChip(plan)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: TranslationCardMetrics.headerHeight)
    }

    private var isUnsupported: Bool {
        if case .unsupported = card.phase { return true }
        return false
    }

    // MARK: - 语言

    private var languagePill: some View {
        let languages = card.displayedLanguages
        return Button {
            guard let pillAnchor else { return }
            TranslationMenus.popUp(TranslationMenus.languageMenu(for: card, controller: controller), below: pillAnchor)
        } label: {
            HStack(spacing: 4) {
                // 放不下时先去掉「（自动检测）」，再只留目标语言
                ViewThatFits(in: .horizontal) {
                    pillText(source: languages.source, target: languages.target, showsSuffix: true)
                    pillText(source: languages.source, target: languages.target, showsSuffix: false)
                    pillText(source: nil, target: languages.target, showsSuffix: false)
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: FontSize.caption2 - 2, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .frame(height: 24)
            .background(HoverFill(cornerRadius: 7, base: 0.07, hover: 0.13))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(MenuAnchor { pillAnchor = $0 })
        .help(TranslationCopy.targetLanguageTooltip)
        .e2eAnchor("card.pill")
    }

    private func pillText(source: String?, target: String?, showsSuffix: Bool) -> Text {
        let from = Text(source.map(TranslationCopy.languageName) ?? TranslationCopy.autoDetect)
        let arrow = Text(verbatim: " → ")
        let to = Text(target.map(TranslationCopy.languageName) ?? TranslationCopy.autoDetect)
        let head =
            card.isReversed || source == nil || !showsSuffix
            ? from
            : from
                + Text(TranslationCopy.autoDetectedSuffix)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
        return (head + arrow + to).font(.system(size: FontSize.footnote, weight: .semibold))
    }

    private var swapButton: some View {
        Button {
            controller.swap()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: FontSize.footnote, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(HoverFill(cornerRadius: 7, base: 0, hover: 0.1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!card.canSwap)
        .opacity(card.canSwap ? 1 : 0.35)
        .help(swapTooltip)
        .accessibilityLabel(Text(swapTooltip))
        .e2eAnchor("card.swap")
    }

    private var swapTooltip: String {
        TranslationCopy.swapTooltip(
            isImage: card.isImage, canSwap: card.canSwap, blockedBySecret: card.isSwapBlockedBySecret)
    }

    // MARK: - 隐私行

    private var privacyLine: some View {
        let privacy = TranslationCopy.privacy(for: card)
        return HStack(spacing: 4) {
            Image(systemName: privacy.isLocked || !privacy.isCloud ? "lock.fill" : "cloud.fill")
                .font(.system(size: FontSize.caption2 - 2))
            Text(privacy.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: FontSize.caption2))
        .foregroundStyle(privacy.isCloud ? AnyShapeStyle(TranslationPalette.cloud) : AnyShapeStyle(.secondary))
        .padding(.leading, 3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 引擎

    private func engineLabel(_ plan: ClipTranslationPlan, showsName: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: plan.sendsTextOffDevice ? "cloud" : "laptopcomputer")
                .font(.system(size: FontSize.footnote))
            if showsName {
                Text(plan.engineShortName)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: FontSize.caption2 - 3, weight: .bold))
        }
        .fixedSize()
    }

    private func engineChip(_ plan: ClipTranslationPlan) -> some View {
        Button {
            guard let engineAnchor else { return }
            let menu = TranslationMenus.engineMenu(for: plan, openSettings: openSettings)
            TranslationMenus.popUp(menu, below: engineAnchor)
        } label: {
            engineLabel(plan, showsName: plan.engineShortName.count <= Self.engineNameMaxLength)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .frame(height: 26)
                .background(HoverFill(cornerRadius: Radius.control, base: 0, hover: 0.08))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor { engineAnchor = $0 })
        .help(TranslationCopy.engineTooltip(plan))
        .e2eAnchor("card.engine")
    }
}

/// 悬停时加深的底板（预览面板不可成为 key：用 PointerTracker 而不是 onHover）
struct HoverFill: View {
    let cornerRadius: CGFloat
    let base: Double
    let hover: Double

    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(isHovered ? hover : base))
            .background(PointerTracker { isHovered = $0 != nil })
            .animation(.easeOut(duration: Motion.fade), value: isHovered)
    }
}
