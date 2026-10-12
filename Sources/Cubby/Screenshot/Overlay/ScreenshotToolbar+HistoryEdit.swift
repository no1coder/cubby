import CubbyCore
import SwiftUI

/// 晾衣绳放大编辑的工具栏（docs/UI-UPGRADE-PLAN.md §5 `ClotheslineEdit`）：
/// 8 工具｜6 色｜撤销｜提取文字（翻译）贴图 存储｜「复制」「完成并晾回」
///
/// 没有指针按钮：再点一次当前工具回到指针（与工具键相同），此时可以单击选中、拖动标注。
extension ScreenshotToolbar {
    /// 设计稿的六色（紫与黑仍可用数字键 6 / 7 或样式条选）
    static let historyEditColors: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .white]

    func historyEditContent(_ edit: ScreenshotToolbarModel.HistoryEdit) -> some View {
        HStack(spacing: OverlayTokens.toolbarSpacing) {
            ForEach(ScreenshotTool.allCases.filter { $0 != .pointer }, id: \.self) { tool in
                ToolbarIconButton(
                    symbol: tool.symbolName,
                    tooltip: ToolbarText.tooltip(for: tool),
                    label: tool.displayName,
                    isActive: model.tool == tool,
                    activeNamespace: activeTool
                ) { onAction(.selectTool(tool)) }
            }
            ToolbarSeparator()
            ForEach(Self.historyEditColors, id: \.self) { color in
                ColorSwatchButton(
                    color: color,
                    digit: (AnnotationColor.allCases.firstIndex(of: color) ?? 0) + 1,
                    isSelected: edit.color == color
                ) { onAction(.selectColor(color)) }
            }
            ToolbarSeparator()
            ToolbarIconButton(
                symbol: "arrow.uturn.backward",
                tooltip: String(localized: "Undo (⌘Z)", comment: "Screenshot toolbar tooltip"),
                label: String(localized: "Undo", comment: "Screenshot toolbar button accessibility label"),
                isEnabled: model.canUndo
            ) { onAction(.undo) }
            outputButtons
            ToolbarSeparator()
            ToolbarTextButton(
                title: String(localized: "Copy", comment: "Clothesline image editor toolbar button"),
                tooltip: String(
                    localized: "Copy Annotated Image (⌘C)", comment: "Clothesline image editor toolbar tooltip")
            ) { onAction(.outcome(.copy)) }
            ToolbarTextButton(
                title: String(localized: "Done & Hang Back", comment: "Clothesline image editor toolbar button"),
                tooltip: String(
                    localized: "Save as a new history item and hang it back (↩)",
                    comment: "Clothesline image editor toolbar tooltip"),
                isProminent: true
            ) { onAction(.outcome(.hangBack)) }
        }
    }
}

/// 文字按钮（28 pt 高）：次要为浅色底，主要为实心强调色 + 白字
struct ToolbarTextButton: View {
    let title: String
    let tooltip: String
    var isProminent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: FontSize.body, weight: .semibold))
                .foregroundStyle(isProminent ? Color.white : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: OverlayTokens.toolbarButtonSize)
                .background { background }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return Group {
            if isProminent {
                shape.fill(Color.accentColor.opacity(isHovered ? OverlayTokens.prominentHoverOpacity : 1))
            } else {
                shape.fill(
                    Color.primary.opacity(
                        isHovered ? HistoryEditTokens.textButtonHoverOpacity : HistoryEditTokens.textButtonFillOpacity))
            }
        }
    }
}
