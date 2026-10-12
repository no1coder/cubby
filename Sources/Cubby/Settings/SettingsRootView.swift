import SwiftUI

/// 设置窗口当前的分页
@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsPane = .general {
        didSet { if selection != oldValue { onChange(selection) } }
    }

    @ObservationIgnored var onChange: (SettingsPane) -> Void = { _ in }
}

/// 设置窗口的内容：左侧原生侧边栏（图标 + 名称），右侧页标题 + 页面（页面自带的分组 Form 负责滚动）
struct SettingsRootView: View {
    let panes: [SettingsPane]
    @Bindable var navigation: SettingsNavigation
    let page: (SettingsPane) -> AnyView

    static let sidebarWidth: CGFloat = 220
    /// 页标题与内容的左边距（与分组 Form 的内容对齐）
    private static let titleInset = EdgeInsets(top: 18, leading: 28, bottom: 4, trailing: 28)

    var body: some View {
        NavigationSplitView {
            List(panes, id: \.self, selection: selectionBinding) { pane in
                Label(pane.title, systemImage: pane.symbolName)
            }
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
            // 红绿灯在侧边栏顶部，列表从它下方开始
            .safeAreaPadding(.top, 12)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(navigation.selection.title)
                    .font(.system(size: FontSize.title, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(Self.titleInset)
                page(navigation.selection)
                    .id(navigation.selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(.container, edges: .top)
            .modifier(HidesToolbarTitle())
            .toolbar(.hidden, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// 侧边栏不允许取消选中
    private var selectionBinding: Binding<SettingsPane?> {
        Binding(get: { navigation.selection }, set: { if let pane = $0 { navigation.selection = pane } })
    }
}

/// 页标题画在内容里；标题栏不显示窗口标题（切换分页时 SwiftUI 会把它放进工具栏）。macOS 15 起才能移除
private struct HidesToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
