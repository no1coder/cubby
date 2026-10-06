import CubbyCore
import SwiftUI

/// 拆词卡（⌘B，docs/TEXT-PICK-DESIGN.md §3）：详情区的第三种内容，宽 440；
/// 头 56（来源图标 ·「拆词」· 副标题 ·「全选」）/ 词块区（自绘，超出滚动）/ 有选取时的结果条 / 底栏 36（统计 · 复制 · 粘贴）。
/// 不支持的条目显示状态页（40pt 圆形图标 + 13pt 标题），选中项移回可拆的条目时继续
struct TextPickCardView: View {
    let viewModel: PanelViewModel
    let controller: TextPickController
    /// 换条目、进入 / 离开状态页、分词完成时通知窗口调整高度
    let onLayoutChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextPickCardHeader(controller: controller)
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Hairline()
            TextPickCardFooter(controller: controller, viewModel: viewModel)
        }
        .onChange(of: controller.layoutKey) { onLayoutChange() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(TextPickCopy.title))
    }

    @ViewBuilder
    private var content: some View {
        if controller.isUnsupported {
            // 不放进滚动视图：其内部容器视图不接受 first mouse（与翻译卡的状态页一致）
            TranslationStateView(symbol: "nosign", tone: .info, title: TextPickCopy.noText, detail: nil, actions: [])
                .e2eAnchor("card.pick.state")
        } else if controller.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            VStack(spacing: 0) {
                TextPickCanvas(
                    controller: controller, version: controller.documentVersion, selection: controller.selection
                )
                .e2eAnchor("card.pick.canvas")
                if !controller.selection.isEmpty {
                    TextPickResultStrip(result: controller.result, length: controller.resultLength)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// 头部 56：来源图标 · 「拆词」13pt semibold · 副标题 11pt 次要色 · 右侧文字按钮「全选」
private struct TextPickCardHeader: View {
    let controller: TextPickController

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(
                bundleID: controller.item?.source?.bundleID,
                fallbackSymbol: controller.item?.kind.symbolName ?? ClipKind.text.symbolName)
            VStack(alignment: .leading, spacing: 1) {
                Text(TextPickCopy.title)
                    .font(.system(size: FontSize.body, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if !controller.isUnsupported {
                TextPickTextButton(title: TextPickCopy.selectAll) { controller.toggleAll() }
                    .disabled(controller.tokenCount == 0)
                    .e2eAnchor("card.pick.selectAll")
            }
        }
        .padding(.horizontal, TextPickMetrics.barInset)
        .frame(height: TextPickMetrics.headerHeight)
    }

    /// 「42 个词 · 点选或拖过来选取」；超过上限时换成「只显示前 20,000 个字符」（P6）
    private var subtitle: String? {
        guard let document = controller.document else { return nil }
        return TextPickCopy.subtitle(words: document.wordCount, isTruncated: document.isTruncated)
    }
}

/// 结果条：11pt，「」包住结果，最多 2 行、中间省略；右侧字数
private struct TextPickResultStrip: View {
    /// 结果很长时只取首尾各这么多字符显示（中间本来就省略），避免每次渲染都排版上万字
    private static let shownEdge = 240

    let result: String
    let length: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(TextPickCopy.quoted(shown))
                .lineLimit(TextPickMetrics.resultMaxLines)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .e2eAnchor("card.pick.result")
            Text(TextPickCopy.characterCount(length))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .font(.system(size: TextPickMetrics.resultFontSize))
        .padding(.vertical, TextPickMetrics.resultVertical)
        .padding(.horizontal, TextPickMetrics.resultHorizontal)
        .background(
            RoundedRectangle(cornerRadius: TextPickMetrics.resultRadius, style: .continuous)
                .fill(Color.primary.opacity(TextPickMetrics.resultFill))
        )
        .padding(.horizontal, TextPickMetrics.barInset)
        .padding(.bottom, TextPickMetrics.resultBottom)
        .accessibilityElement(children: .combine)
    }

    /// 换行显示为空格（两行的条里不浪费行）；超长时截成首尾两段
    private var shown: String {
        let flat = result.replacingOccurrences(of: "\n", with: " ")
        guard length > Self.shownEdge * 2 else { return flat }
        return String(flat.prefix(Self.shownEdge)) + "\u{2026}" + String(flat.suffix(Self.shownEdge))
    }
}

/// 底栏 36：左「已选 5 个词 · 23 个字符」（无选取时「⌘A 全选」）；右次按钮「复制」、主按钮「粘贴」（无选取时置灰）
private struct TextPickCardFooter: View {
    let controller: TextPickController
    let viewModel: PanelViewModel

    var body: some View {
        let hasSelection = !controller.selection.isEmpty
        HStack(spacing: 8) {
            Group {
                if hasSelection {
                    Text(
                        TextPickCopy.selectionSummary(
                            words: controller.pickedWordCount, characters: controller.resultLength)
                    )
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                } else if controller.tokenCount > 0 {
                    KeyHint(keys: "⌘A", label: TextPickCopy.selectAll)
                }
            }
            .lineLimit(1)
            .layoutPriority(-1)
            Spacer(minLength: 4)
            Button(TextPickCopy.copyButton) { viewModel.copyPickedWords() }
                .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                .disabled(!hasSelection)
                .help(TextPickCopy.copyTooltip)
                .e2eAnchor("card.pick.copy")
            Button(TextPickCopy.pasteButton) { viewModel.pastePickedWords() }
                .buttonStyle(CapsuleButtonStyle())
                .disabled(!hasSelection)
                .help(TextPickCopy.pasteTooltip(app: viewModel.target?.name))
                .e2eAnchor("card.pick.paste")
        }
        .padding(.horizontal, TextPickMetrics.barInset)
        .frame(height: PanelMetrics.footerHeight)
    }
}

/// 头部的文字按钮（12pt，悬停 primary 0.08 底）：详情区窗口不是 key，悬停用 activeAlways 的跟踪视图
private struct TextPickTextButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: FontSize.footnote))
                .padding(.horizontal, TextPickMetrics.textButtonHorizontal)
                .padding(.vertical, TextPickMetrics.textButtonVertical)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(isHovered && isEnabled ? TextPickMetrics.textButtonHover : 0))
                        .background(PointerTracker { isHovered = $0 != nil })
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : TextPickMetrics.disabledOpacity)
        .animation(.easeOut(duration: Motion.fade), value: isHovered)
    }
}
