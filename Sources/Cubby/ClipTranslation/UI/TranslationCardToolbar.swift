import CubbyCore
import SwiftUI

/// 翻译卡工具条（40pt，原型 tcBarHTML）：「译文 / 对照 / 原文」分段控件 + 右侧状态
struct TranslationCardToolbar: View {
    let card: TranslationCard
    let controller: TranslationCardController

    var body: some View {
        HStack(spacing: 8) {
            segmentedControl
                .fixedSize()
            Spacer(minLength: 4)
            status
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: TranslationCardMetrics.toolbarHeight)
    }

    private static let trackShape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)

    private var isDisabled: Bool {
        if case .unsupported = card.phase { return true }
        return false
    }

    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(TranslationViewMode.allCases, id: \.self) { mode in
                segment(mode)
            }
        }
        .padding(2)
        .background(Self.trackShape.fill(Color.primary.opacity(0.08)))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TranslationCopy.modePickerLabel)
    }

    private func segment(_ mode: TranslationViewMode) -> some View {
        let isSelected = card.mode == mode
        return Button {
            controller.setMode(mode)
        } label: {
            Text(TranslationCopy.modeTitle(mode))
                .font(.system(size: FontSize.footnote, weight: isSelected ? .semibold : .regular))
                .fixedSize()
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.2 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode == .sideBySide ? TranslationCopy.sideBySideTooltip(isImage: card.isImage) : "")
        .e2eAnchor("card.mode.\(mode.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var status: some View {
        if card.isPeeking {
            keyCapPhrase(TranslationCopy.peekingBefore, TranslationCopy.peekingAfter)
        } else {
            switch card.phase {
            case .holding:
                spinning(TranslationCopy.holdingStatus)
            case .waiting:
                spinning(TranslationCopy.waitingStatus(card))
            case .streaming:
                spinning(
                    card.isImage
                        ? TranslationCopy.imageProgress(card.content.imageBlocks.count) : TranslationCopy.translating)
            case .done:
                doneStatus
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var doneStatus: some View {
        if card.mode == .original {
            EmptyView()
        } else if card.isImage && card.mode == .sideBySide {
            Text(TranslationCopy.dragDivider)
        } else {
            keyCapPhrase(TranslationCopy.holdOptionBefore, TranslationCopy.holdOptionAfter)
        }
    }

    private func spinning(_ text: String) -> some View {
        HStack(spacing: 6) {
            TranslationSpinner()
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    /// 「按住 [⌥] 看原文」
    private func keyCapPhrase(_ before: String, _ after: String) -> some View {
        HStack(spacing: 5) {
            Text(before)
            KeyCap(text: "⌥")
            Text(after)
        }
        .accessibilityElement(children: .combine)
    }
}
