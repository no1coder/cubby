import SwiftUI
import CubbyCore

/// 底栏：条目数量 + 回车目标提示 + 快捷键帮助。
/// 有轻提示（如删除后可撤销）时，提示替换右侧快捷键区域，不遮挡卡片。
/// 宽度不足时按优先级降级：先收窄「↩ 粘贴到」短语，再隐藏「⇧↩」提示，最后隐藏数量。
/// 翻译可用时追加「按住 ⌥ 预览译文」「⌥↩ 翻译后粘贴」（原型的优先级：⇧↩ → 数量 → 按住 ⌥ → ⌥↩ 依次让位）；
/// 翻译卡打开时换成卡片的按键提示（TranslationFooterHints），拆词卡打开时换成拆词的按键提示（TextPickFooterHints）
struct PanelFooter: View {
    let viewModel: PanelViewModel
    let count: Int

    /// 「粘贴到 [图标] App 名」短语的最大宽度：宽松档（中文下 App 名约 90pt），过长时尾部截断
    private static let pasteTargetMaxWidth: CGFloat = 144
    /// 紧凑档：英文等较长的语言在宽松档放不下「⇧↩」提示时改用这一档，两组提示仍能并排
    private static let compactPasteTargetMaxWidth: CGFloat = 120
    private static let appIconSize: CGFloat = 13
    private static let helpButtonSize: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 底栏的一种排布
    private struct Layout: Hashable {
        var showsCount = true
        var showsAlternate = true
        var targetMaxWidth: CGFloat
        /// 翻译：「按住 ⌥ 预览译文」「⌥↩ 翻译后粘贴」
        var showsHold = false
        var showsTranslatePaste = false
    }

    var body: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                if viewModel.isTranslationCardOpen && viewModel.toast == nil {
                    ForEach(TranslationFooterHints.Level.allCases, id: \.self) { level in
                        cardContent(level)
                    }
                } else if viewModel.isTextPickOpen && viewModel.toast == nil {
                    ForEach(TextPickFooterHints.Level.allCases, id: \.self) { level in
                        textPickContent(level)
                    }
                } else {
                    ForEach(layouts, id: \.self) { layout in
                        content(layout)
                    }
                }
            }
            helpButton
        }
        // 数量文字与卡片左缘对齐；帮助按钮与顶栏齿轮按钮的中心在同一条竖线上
        .padding(.leading, PanelMetrics.inset)
        .padding(.trailing, PanelMetrics.inset + (PanelMetrics.controlHeight - Self.helpButtonSize) / 2)
        .frame(height: PanelMetrics.footerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
        .animation(
            Motion.animation(.snappy(duration: Motion.layoutChange), reduceMotion: reduceMotion),
            value: viewModel.toast
        )
    }

    /// 依次尝试的排布（从最完整到最紧凑）
    private var layouts: [Layout] {
        let wide = Self.pasteTargetMaxWidth
        let compact = Self.compactPasteTargetMaxWidth
        guard viewModel.translation != nil else {
            return [
                Layout(targetMaxWidth: wide), Layout(targetMaxWidth: compact),
                Layout(showsAlternate: false, targetMaxWidth: wide),
                Layout(showsCount: false, showsAlternate: false, targetMaxWidth: wide),
            ]
        }
        return [
            Layout(targetMaxWidth: wide, showsHold: true, showsTranslatePaste: true),
            Layout(showsAlternate: false, targetMaxWidth: compact, showsHold: true, showsTranslatePaste: true),
            Layout(
                showsCount: false, showsAlternate: false, targetMaxWidth: compact, showsHold: true,
                showsTranslatePaste: true),
            Layout(showsCount: false, showsAlternate: false, targetMaxWidth: compact, showsTranslatePaste: true),
            Layout(showsCount: false, showsAlternate: false, targetMaxWidth: wide),
        ]
    }

    /// 翻译卡打开时：数量 + 卡片的按键提示
    private func cardContent(_ level: TranslationFooterHints.Level) -> some View {
        HStack(spacing: 10) {
            if level.showsCount {
                countLabel
            }
            Spacer(minLength: 4)
            TranslationFooterHints(target: pastesIntoTarget ? viewModel.target : nil, level: level)
                .transition(.opacity)
        }
    }

    /// 拆词卡打开时：拆词的按键提示（靠右，不显示数量）
    private func textPickContent(_ level: TextPickFooterHints.Level) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 4)
            TextPickFooterHints(target: pastesIntoTarget ? viewModel.target : nil, level: level)
                .transition(.opacity)
                .e2eAnchor("footer.pick")
        }
    }

    private var countLabel: some View {
        Text(countText)
            .font(.system(size: FontSize.caption))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .layoutPriority(1)
    }

    private func content(_ layout: Layout) -> some View {
        let showsCount = layout.showsCount
        let showsAlternate = layout.showsAlternate
        let targetMaxWidth = layout.targetMaxWidth
        return HStack(spacing: 10) {
            // 数量与「⇧↩」提示优先占用理想宽度；空间紧张时由「粘贴到」短语收缩（App 名尾部截断），
            // 保证 ViewThatFits 按理想宽度选中的方案在实际布局中不会截断其他提示
            if showsCount {
                countLabel
            }
            Spacer(minLength: 4)
            if let toast = viewModel.toast {
                InlineToast(toast: toast) { _ = viewModel.undoDelete() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if count > 0 {
                Group {
                    primaryHint(fillsMaxWidth: showsAlternate, maxWidth: targetMaxWidth)
                    if showsAlternate {
                        KeyHint(keys: "⇧↩", label: alternateLabel)
                            .layoutPriority(1)
                    }
                    if layout.showsHold {
                        HoldOptionHint()
                            .layoutPriority(1)
                    }
                    if layout.showsTranslatePaste {
                        KeyHint(keys: "⌥↩", label: TranslationFooterHints.translatePasteLabel)
                            .layoutPriority(1)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// ↩ 是否直接粘贴到目标应用。与「↩」提示同一判断：未授权辅助功能、选择了仅复制或没有目标应用时，
    /// ↩ 与 ⇧↩ 都只复制，⇧↩ 的标签随之改为「复制…」，不再与「↩ 复制」矛盾
    private var pastesIntoTarget: Bool {
        viewModel.canPasteDirectly && viewModel.target != nil
    }

    private var alternateLabel: String {
        let alternate = viewModel.settings.pasteFormat.alternate
        return pastesIntoTarget ? alternate.footerLabel : alternate.copyFooterLabel
    }

    private var countText: String {
        count == viewModel.totalCount
            ? String(localized: "\(count) items", comment: "Footer: number of items in the panel")
            : String(
                localized: "\(count) of \(viewModel.totalCount)",
                comment: "Footer: number of matching items of all items, e.g. “3 of 12”"
            )
    }

    private var helpButton: some View {
        Button {
            viewModel.toggleHelp()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(viewModel.isShowingHelp ? Color.accentColor : .secondary)
                .frame(width: Self.helpButtonSize, height: Self.helpButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Keyboard Shortcuts")
        .accessibilityLabel(Text("Keyboard Shortcuts"))
    }

    /// 明确告诉用户回车会把内容送到哪里。
    /// 与「⇧↩」提示并排时占满最大宽度（两组提示位置稳定）；单独显示时按内容收紧，靠右贴近帮助按钮
    @ViewBuilder
    private func primaryHint(fillsMaxWidth: Bool, maxWidth: CGFloat) -> some View {
        if viewModel.canPasteDirectly, let target = viewModel.target {
            HStack(spacing: 4) {
                KeyCap(text: "↩", prominent: true)
                let phrase = Text(
                    "Paste to \(appIcon(target)) \(appName(target))",
                    comment: "Footer hint for ↩. %1$@ = icon of the target app, %2$@ = name of the target app"
                )
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxWidth, alignment: .leading)
                if fillsMaxWidth {
                    phrase
                } else {
                    phrase.fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            KeyHint(keys: "↩", label: String(localized: "Copy", comment: "Footer hint for ↩ when it only copies"))
        }
    }

    private func appIcon(_ target: PasteTarget) -> Text {
        Text(Image(nsImage: ImageCache.shared.appIcon(bundleID: target.bundleID, pointSize: Self.appIconSize)))
            .baselineOffset(-2.5)
    }

    private func appName(_ target: PasteTarget) -> Text {
        Text(verbatim: target.name)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
    }
}

/// 底栏内的轻提示（删除后可撤销）
private struct InlineToast: View {
    let toast: PanelToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toast.symbolName)
                .font(.system(size: FontSize.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.system(size: FontSize.caption, weight: .medium))
            if toast.action == .undoDelete {
                Button(action: onUndo) {
                    HStack(spacing: 4) {
                        Text("Undo")
                            .font(.system(size: FontSize.caption, weight: .semibold))
                        KeyCap(text: "⌘Z")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}

extension PasteFormat {
    /// 帮助浮层中描述该格式粘贴动作的完整短语
    var pasteActionLabel: String {
        switch self {
        case .original: String(localized: "Paste with formatting", comment: "Shortcut hint for ⇧↩")
        case .plainText: String(localized: "Paste as plain text", comment: "Shortcut hint for ⇧↩")
        }
    }

    /// 仅复制时（↩ 为「复制」）帮助浮层中描述 ⇧↩ 动作的完整短语
    var copyActionLabel: String {
        switch self {
        case .original: String(localized: "Copy with formatting", comment: "Shortcut hint for ⇧↩ when it only copies")
        case .plainText: String(localized: "Copy as plain text", comment: "Shortcut hint for ⇧↩ when it only copies")
        }
    }

    /// 底栏「⇧↩」提示的短标签：英文控制在 12 个字符以内，保证 380pt 面板里与「↩ 粘贴到」并排放得下；
    /// 独立的键让中文可以继续用「纯文本粘贴 / 保留格式粘贴」
    var footerLabel: String {
        switch self {
        case .original:
            String(
                localized: "footer.pasteWithFormatting",
                defaultValue: "Keep format",
                comment: "Footer hint for ⇧↩: paste keeping the formatting. Keep it short (12 characters or fewer)."
            )
        case .plainText:
            String(
                localized: "footer.pastePlainText",
                defaultValue: "Plain text",
                comment: "Footer hint for ⇧↩: paste as plain text. Keep it short (12 characters or fewer)."
            )
        }
    }

    /// 仅复制时底栏「⇧↩」提示的短标签：此时 ↩ 只显示「复制」，底栏空间足够放下稍长的英文
    var copyFooterLabel: String {
        switch self {
        case .original:
            String(
                localized: "footer.copyWithFormatting",
                defaultValue: "Copy with format",
                comment: "Footer hint for ⇧↩ when it only copies: copy keeping the formatting. Keep it short."
            )
        case .plainText:
            String(
                localized: "footer.copyPlainText",
                defaultValue: "Copy plain text",
                comment: "Footer hint for ⇧↩ when it only copies: copy as plain text. Keep it short."
            )
        }
    }
}
