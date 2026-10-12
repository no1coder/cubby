import CubbyCore
import SwiftUI

/// 顶栏布局按钮：浮动 → 固定右侧 → 固定底部 → 浮动（回到上次选的浮动位置）。
/// 停靠时按下状态显示当前排布（侧栏 / 横条的图标），浮动时显示下一步「固定右侧」
struct LayoutButton: View {
    let layout: PanelLayout
    let action: () -> Void

    var body: some View {
        HeaderIconButton(
            systemName: layout == .shelf ? "rectangle.bottomthird.inset.filled" : "sidebar.right",
            label: String(
                localized: "Switch Layout", comment: "Panel header button that cycles floating, right and bottom"),
            help: Text(verbatim: help),
            isActive: layout != .floating,
            action: action
        )
    }

    private var help: String {
        switch layout {
        case .floating:
            String(localized: "Switch layout (now: floating)", comment: "Tooltip of the panel layout button")
        case .sidebar:
            String(localized: "Switch layout (now: docked right)", comment: "Tooltip of the panel layout button")
        case .shelf:
            String(localized: "Switch layout (now: docked bottom)", comment: "Tooltip of the panel layout button")
        }
    }
}
