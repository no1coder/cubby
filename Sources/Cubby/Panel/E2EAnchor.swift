import SwiftUI

extension View {
    /// 面板 E2E 的定位锚点：调试构建在 E2E 运行期间记录该视图在窗口中的位置（点击按钮、拖动分隔线、确认视图已显示），
    /// 正式构建中原样返回
    @ViewBuilder
    func e2eAnchor(_ name: String) -> some View {
        #if DEBUG
        modifier(PanelE2EAnchorModifier(name: name))
        #else
        self
        #endif
    }
}
