import CubbyCore
import SwiftUI

/// 截图翻译的翻译条（原型 docs/prototypes/screenshot-translate.html 的 #tbar）：
/// 语言 ▾｜引擎｜进行中：状态 + Esc 提示；失败：原因 + 操作；完成：原文 | 译文、卷帘对比｜复制译文 + 提示
struct TranslationBar: View {
    let model: TranslationBarModel
    let onAction: (TranslationBarAction) -> Void

    var body: some View {
        HStack(spacing: OverlayTokens.toolbarSpacing) {
            languageMenu
            ToolbarSeparator()
            if let engine = model.engine {
                EngineChip(engine: engine)
                ToolbarSeparator()
            }
            content
        }
        .padding(OverlayTokens.toolbarPadding)
        .fixedSize()
        .coordinateSpace(.named(TranslationBarSpace.name))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(TranslationBarText.toolbarLabel))
    }

    /// 语言选单：选定即写回设置并沿用已识别的块重译
    private var languageMenu: some View {
        Menu {
            ForEach(model.languages) { option in
                Button {
                    onAction(.chooseLanguage(option.code))
                } label: {
                    if option.isSelected {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
                .disabled(option.isDisabled)
            }
        } label: {
            // 一段文字（而不是 HStack）：菜单按钮会把标签里的图片挪到文字前面，箭头要在语言之后
            (Text(model.languagePair + " ") + Text(Image(systemName: "chevron.down")))
                .font(.system(size: FontSize.body, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, TranslationBarMetrics.horizontalPadding)
        .frame(height: OverlayTokens.toolbarButtonSize)
        .help(TranslationBarText.languageMenuHelp)
        .accessibilityLabel(Text(model.languagePair))
        .translationBarItem(.language)
    }

    @ViewBuilder private var content: some View {
        switch model.content {
        case .progress(let status):
            ProgressStatus(status: status)
        case .failure(let message, let actionTitle, let action):
            FailureStatus(message: message)
            if let actionTitle, let action {
                BarTextButton(title: actionTitle, isProminent: true, item: .failureAction) { onAction(action) }
            }
        case .result(let showsTranslation, let isWipeEnabled, let notice):
            ExportVersionSwitch(showsTranslation: showsTranslation) { onAction(.showTranslation($0)) }
            BarTextButton(
                title: TranslationBarText.compare, symbol: "rectangle.split.2x1", isOn: isWipeEnabled,
                help: TranslationBarText.compareHelp, item: .compare
            ) { onAction(.setWipe(!isWipeEnabled)) }
            ToolbarSeparator()
            BarTextButton(
                title: TranslationBarText.copyTranslation, symbol: "doc.on.doc",
                help: TranslationBarText.copyTranslationHelp, item: .copy
            ) { onAction(.copy) }
            if let notice {
                BarHint(text: notice.message)
                BarTextButton(title: notice.actionTitle, item: .noticeAction) { onAction(notice.action) }
            } else {
                BarHint(text: TranslationBarText.holdSpace)
            }
        }
    }
}

/// 翻译条的尺寸（原型 .pill / .chip / .act / .seg）
enum TranslationBarMetrics {
    static let horizontalPadding: CGFloat = 9
    static let itemSpacing: CGFloat = 5
    static let segmentPadding: CGFloat = 2
    static let segmentHeight: CGFloat = 24
    static let segmentRadius: CGFloat = 6
    static let segmentHorizontalPadding: CGFloat = 10
    static let segmentFillOpacity: Double = 0.08
    static let segmentSelectedOpacity: Double = 0.2
    static let spinnerScale: CGFloat = 0.55
    static let hintHorizontalPadding: CGFloat = 5
}

/// 引擎徽标：云端引擎带云图标，本机引擎带电脑图标；悬停说明文字会发往何处
private struct EngineChip: View {
    let engine: TranslationEngineBadge

    var body: some View {
        HStack(spacing: TranslationBarMetrics.itemSpacing) {
            Image(systemName: engine.sendsTextOffDevice ? "cloud" : "laptopcomputer")
                .font(.system(size: FontSize.footnote, weight: .medium))
            Text(engine.name)
                .font(.system(size: FontSize.footnote))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, TranslationBarMetrics.horizontalPadding)
        .frame(height: OverlayTokens.toolbarButtonSize)
        .help(
            engine.sendsTextOffDevice
                ? TranslationBarText.offDevice(engine.name) : TranslationBarText.onDevice(engine.name)
        )
        .accessibilityElement(children: .combine)
        .translationBarItem(.engine)
    }
}

/// 进行中：转圈 + 状态文字（等宽数字）+ 「Esc 取消翻译」
private struct ProgressStatus: View {
    let status: String

    var body: some View {
        HStack(spacing: TranslationBarMetrics.itemSpacing + 2) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(TranslationBarMetrics.spinnerScale)
                .frame(width: FontSize.body, height: FontSize.body)
            Text(status)
                .font(.system(size: FontSize.footnote).monospacedDigit())
                .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(.horizontal, TranslationBarMetrics.horizontalPadding - 1)
        .frame(height: OverlayTokens.toolbarButtonSize)
        .accessibilityElement(children: .combine)
        .translationBarItem(.status)
        BarHint(text: TranslationBarText.escToCancel)
    }
}

/// 失败：橙色警告图标 + 原因
private struct FailureStatus: View {
    let message: String

    var body: some View {
        HStack(spacing: TranslationBarMetrics.itemSpacing + 1) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: FontSize.body, weight: .medium))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: FontSize.footnote))
        }
        .padding(.horizontal, TranslationBarMetrics.horizontalPadding - 3)
        .frame(height: OverlayTokens.toolbarButtonSize)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .translationBarItem(.status)
    }
}

/// 灰色小字提示
private struct BarHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: FontSize.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, TranslationBarMetrics.hintHorizontalPadding)
            .frame(height: OverlayTokens.toolbarButtonSize)
            .translationBarItem(.hint)
    }
}

/// 「原文 | 译文」分段开关（决定导出版本）
private struct ExportVersionSwitch: View {
    let showsTranslation: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: TranslationBarMetrics.segmentPadding) {
            segment(TranslationBarText.original, selected: !showsTranslation, item: .original) { onChange(false) }
            segment(TranslationBarText.translation, selected: showsTranslation, item: .translation) { onChange(true) }
        }
        .padding(TranslationBarMetrics.segmentPadding)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.primary.opacity(TranslationBarMetrics.segmentFillOpacity))
        )
        .help(TranslationBarText.exportVersionHelp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(TranslationBarText.exportVersionLabel))
    }

    private func segment(_ title: String, selected: Bool, item: TranslationBarItem, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.system(size: FontSize.footnote, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, TranslationBarMetrics.segmentHorizontalPadding)
                .frame(height: TranslationBarMetrics.segmentHeight)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: TranslationBarMetrics.segmentRadius, style: .continuous)
                            .fill(Color.primary.opacity(TranslationBarMetrics.segmentSelectedOpacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .translationBarItem(item)
    }
}

/// 文字按钮：可带图标；isOn 为开关的按下态（强调色底）；isProminent 为主操作（实心强调色）
private struct BarTextButton: View {
    let title: String
    var symbol: String?
    var isOn = false
    var isProminent = false
    var help: String?
    let item: TranslationBarItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: TranslationBarMetrics.itemSpacing) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: FontSize.footnote, weight: .medium))
                }
                Text(title)
                    .font(.system(size: FontSize.footnote, weight: isProminent ? .semibold : .regular))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, TranslationBarMetrics.horizontalPadding)
            .frame(height: OverlayTokens.toolbarButtonSize)
            .background { background }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help ?? title)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .translationBarItem(item)
    }

    private var foreground: Color {
        if isProminent { return .white }
        return isOn ? .accentColor : .primary
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        if isProminent {
            shape.fill(Color.accentColor.opacity(isHovered ? OverlayTokens.prominentHoverOpacity : 1))
        } else if isOn {
            shape.fill(Color.accentColor.opacity(OverlayTokens.activeFillOpacity))
        } else if isHovered {
            shape.fill(Color.primary.opacity(OverlayTokens.buttonHoverOpacity))
        }
    }
}

/// 翻译条上可定位的元素（端到端测试按它们的位置点击）
enum TranslationBarItem: Hashable, CustomStringConvertible {
    case language
    case engine
    case status
    case hint
    case failureAction
    case original
    case translation
    case compare
    case copy
    case noticeAction

    var description: String {
        switch self {
        case .language: "language"
        case .engine: "engine"
        case .status: "status"
        case .hint: "hint"
        case .failureAction: "failure action"
        case .original: "original"
        case .translation: "translation"
        case .compare: "compare"
        case .copy: "copy"
        case .noticeAction: "notice action"
        }
    }
}

/// 翻译条的坐标空间名（端到端测试读元素位置用）
enum TranslationBarSpace {
    static let name = "translationBar"
}

extension View {
    /// 调试构建：记下元素在翻译条内的位置，供端到端测试点击；Release 中什么都不做
    func translationBarItem(_ item: TranslationBarItem) -> some View {
        #if DEBUG
        return onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TranslationBarSpace.name))
        } action: { frame in
            TranslationBarDebugFrames.shared.frames[item] = frame
        }
        .onDisappear { TranslationBarDebugFrames.shared.frames[item] = nil }
        #else
        return self
        #endif
    }
}

#if DEBUG
/// 仅调试构建：翻译条各元素在条内的位置（点，左上原点）
@MainActor
final class TranslationBarDebugFrames {
    static let shared = TranslationBarDebugFrames()
    var frames: [TranslationBarItem: CGRect] = [:]
}
#endif
