import CubbyCore
import SwiftUI

/// 工具栏按钮触发的动作；覆盖层控制器把它翻译成 `ScreenshotEvent`
enum ScreenshotToolbarAction: Equatable {
    case selectTool(ScreenshotTool)
    case undo
    case redo
    case outcome(ScreenshotOutcome)
    /// 截图翻译（⇧⌘T）
    case translate
}

/// 工具栏的显示状态（值类型，变化时才刷新 SwiftUI）
struct ScreenshotToolbarModel: Equatable {
    /// 「翻译」按钮的状态；nil = 不显示（macOS 26 以前或没有提供翻译）
    enum Translate: Equatable {
        /// 还没有译文
        case idle
        /// 进行中或失败（按钮高亮）
        case active
        /// 已有结果：高亮，tooltip 说明再按切换原文 / 译文
        case showing(translation: Bool)
    }

    var tool: ScreenshotTool
    var canUndo: Bool
    var canRedo: Bool
    var translate: Translate?
}

/// 截图工具栏（§2.6）：指针 + 8 工具｜撤销 重做｜提取文字（翻译）贴图 保存｜取消 完成
struct ScreenshotToolbar: View {
    let model: ScreenshotToolbarModel
    let onAction: (ScreenshotToolbarAction) -> Void

    /// 激活底块在工具按钮之间滑动（matchedGeometryEffect）
    @Namespace private var activeTool

    var body: some View {
        HStack(spacing: OverlayTokens.toolbarSpacing) {
            ForEach(ScreenshotTool.allCases, id: \.self) { tool in
                ToolbarIconButton(
                    symbol: tool.symbolName,
                    tooltip: ToolbarText.tooltip(for: tool),
                    label: tool.displayName,
                    isActive: model.tool == tool,
                    activeNamespace: activeTool
                ) { onAction(.selectTool(tool)) }
            }
            ToolbarSeparator()
            ToolbarIconButton(
                symbol: "arrow.uturn.backward",
                tooltip: String(localized: "Undo (⌘Z)", comment: "Screenshot toolbar tooltip"),
                label: String(localized: "Undo", comment: "Screenshot toolbar button accessibility label"),
                isEnabled: model.canUndo
            ) { onAction(.undo) }
            ToolbarIconButton(
                symbol: "arrow.uturn.forward",
                tooltip: String(localized: "Redo (⇧⌘Z)", comment: "Screenshot toolbar tooltip"),
                label: String(localized: "Redo", comment: "Screenshot toolbar button accessibility label"),
                isEnabled: model.canRedo
            ) { onAction(.redo) }
            ToolbarSeparator()
            outputButtons
            ToolbarSeparator()
            endButtons
        }
        .padding(OverlayTokens.toolbarPadding)
        .fixedSize()
        .animation(OverlayMotion.slideAnimation, value: model.tool)
    }

    @ViewBuilder private var outputButtons: some View {
        ToolbarIconButton(
            symbol: "text.viewfinder",
            tooltip: String(localized: "Extract Text (⌘T)", comment: "Screenshot toolbar tooltip"),
            label: String(localized: "Extract Text", comment: "Screenshot toolbar button accessibility label")
        ) { onAction(.outcome(.extractText)) }
        if let translate = model.translate {
            ToolbarIconButton(
                symbol: "translate",
                tooltip: Self.tooltip(for: translate),
                label: TranslationBarText.toolbarLabel,
                isActive: translate != .idle
            ) { onAction(.translate) }
        }
        ToolbarIconButton(
            symbol: "pin",
            tooltip: String(localized: "Pin to Screen (⌘P)", comment: "Screenshot toolbar tooltip"),
            label: String(localized: "Pin to Screen", comment: "Screenshot toolbar button accessibility label")
        ) { onAction(.outcome(.pin)) }
        ToolbarIconButton(
            symbol: "square.and.arrow.down",
            tooltip: String(localized: "Save (⌘S)", comment: "Screenshot toolbar tooltip"),
            label: String(localized: "Save", comment: "Screenshot toolbar button accessibility label")
        ) { onAction(.outcome(.save)) }
    }

    /// 已有译文时再按是切换原文 / 译文
    private static func tooltip(for state: ScreenshotToolbarModel.Translate) -> String {
        switch state {
        case .showing(let translation):
            translation ? TranslationBarText.toolbarShowOriginal : TranslationBarText.toolbarShowTranslation
        case .idle, .active:
            TranslationBarText.toolbarTranslate
        }
    }

    @ViewBuilder private var endButtons: some View {
        ToolbarIconButton(
            symbol: "xmark",
            tooltip: String(localized: "Cancel (Esc)", comment: "Screenshot toolbar tooltip"),
            label: String(localized: "Cancel", comment: "Screenshot toolbar button accessibility label"),
            tint: .secondary
        ) { onAction(.outcome(.cancel)) }
        ToolbarIconButton(
            symbol: "checkmark",
            tooltip: String(localized: "Done (↩)", comment: "Screenshot toolbar tooltip"),
            label: String(localized: "Done", comment: "Screenshot toolbar button accessibility label"),
            isProminent: true
        ) { onAction(.outcome(.copy)) }
    }
}

/// 工具 tooltip（附录 A 的原样 key）
enum ToolbarText {
    static func tooltip(for tool: ScreenshotTool) -> String {
        switch tool {
        case .pointer: String(localized: "Pointer (V)", comment: "Screenshot toolbar tooltip")
        case .rectangle: String(localized: "Rectangle (R)", comment: "Screenshot toolbar tooltip")
        case .ellipse: String(localized: "Ellipse (O)", comment: "Screenshot toolbar tooltip")
        case .arrow: String(localized: "Arrow (A)", comment: "Screenshot toolbar tooltip")
        case .pen: String(localized: "Pen (P)", comment: "Screenshot toolbar tooltip")
        case .highlighter: String(localized: "Highlighter (H)", comment: "Screenshot toolbar tooltip")
        case .mosaic: String(localized: "Mosaic (M)", comment: "Screenshot toolbar tooltip")
        case .text: String(localized: "Text (T)", comment: "Screenshot toolbar tooltip")
        case .number: String(localized: "Number (N)", comment: "Screenshot toolbar tooltip")
        }
    }
}

/// 28 × 28 图标按钮：悬停 `primary 0.08` 底；激活强调色底 + 强调色图标（底块在按钮间滑动）；
/// 主操作（完成）为实心强调色 + 白色图标；禁用时变淡
struct ToolbarIconButton: View {
    let symbol: String
    let tooltip: String
    let label: String
    var isActive = false
    var isEnabled = true
    var tint: Color = .primary
    var isProminent = false
    var activeNamespace: Namespace.ID?
    let action: () -> Void

    @State private var isHovered = false

    private static let symbolLocale = Locale(identifier: "en_US")

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: FontSize.callout, weight: isProminent ? .semibold : .medium))
                // 部分符号（如 textformat）有按语言本地化的字形，中文系统会显示「格式」二字；
                // 工具栏是图标语言，统一用拉丁字形
                .environment(\.locale, Self.symbolLocale)
                .foregroundStyle(foreground)
                .frame(width: OverlayTokens.toolbarButtonSize, height: OverlayTokens.toolbarButtonSize)
                .background { background }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var foreground: Color {
        if !isEnabled { return Color.secondary.opacity(OverlayTokens.disabledIconOpacity) }
        if isProminent { return .white }
        return isActive ? .accentColor : tint
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        ZStack {
            if isProminent {
                shape.fill(Color.accentColor.opacity(isHovered ? OverlayTokens.prominentHoverOpacity : 1))
            } else if isHovered && isEnabled && !isActive {
                shape.fill(Color.primary.opacity(OverlayTokens.buttonHoverOpacity))
            }
            if isActive {
                if let activeNamespace {
                    shape.fill(Color.accentColor.opacity(OverlayTokens.activeFillOpacity))
                        .matchedGeometryEffect(id: "active", in: activeNamespace)
                } else {
                    shape.fill(Color.accentColor.opacity(OverlayTokens.activeFillOpacity))
                }
            }
        }
    }
}

/// 分组之间的 1 pt `primary 0.15` 竖线
struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(OverlayTokens.toolbarSeparatorOpacity))
            .frame(width: 1, height: OverlayTokens.toolbarSeparatorHeight)
            .padding(.horizontal, OverlayTokens.toolbarSpacing)
            .accessibilityHidden(true)
    }
}
