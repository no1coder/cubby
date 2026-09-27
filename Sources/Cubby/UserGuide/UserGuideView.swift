import SwiftUI

/// 使用说明窗口的内容：左侧搜索框与目录，右侧正文
struct UserGuideView: View {
    @Bindable var model: UserGuideModel

    private static let sidebarMinWidth: CGFloat = 190
    private static let sidebarIdealWidth: CGFloat = 230
    private static let sidebarMaxWidth: CGFloat = 320

    var body: some View {
        // 侧栏始终显示：搜索框在侧栏里，⌘F 必须能找到它
        NavigationSplitView(columnVisibility: .constant(.all)) {
            GuideSidebar(model: model)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarMinWidth, ideal: Self.sidebarIdealWidth, max: Self.sidebarMaxWidth)
        } detail: {
            GuideDetail(model: model)
        }
    }
}

/// 侧栏：搜索框 + 目录（二级标题，三级标题缩进）。当前节随正文滚动高亮
private struct GuideSidebar: View {
    @Bindable var model: UserGuideModel

    private static let nestedIndent: CGFloat = 12

    var body: some View {
        // 搜索框在列表上方而不是浮在列表上：目录滚动时不会从半透明的搜索框下面透出来
        VStack(spacing: 0) {
            GuideSearchField(
                text: $model.query,
                focusRequest: model.searchFocusRequest,
                onSubmit: { model.revealNextMatch() }
            )
            .padding(.horizontal, PanelMetrics.inset)
            .padding(.vertical, PanelMetrics.cardSpacing)
            contents
        }
    }

    private var contents: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(model.visibleContents) { entry in
                    row(entry)
                        .tag(entry.id)
                        .id(entry.id)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if model.hasNoResults {
                    Text("No results for “\(model.query)”")
                        .font(.system(size: FontSize.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(PanelMetrics.inset)
                }
            }
            .onChange(of: model.currentEntryID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    /// 点击已高亮的一项也要跳回该节开头：行内容自己处理点击，列表选中只跟随当前节
    private var selection: Binding<GuideContentsEntry.ID?> {
        Binding(
            get: { model.currentEntryID },
            set: { id in
                if let id { model.select(id) }
            }
        )
    }

    private func row(_ entry: GuideContentsEntry) -> some View {
        Text(entry.title)
            .font(.system(size: FontSize.body, weight: entry.level == 2 ? .medium : .regular))
            .foregroundStyle(entry.level == 2 ? .primary : .secondary)
            .lineLimit(2)
            .padding(.leading, entry.level == 2 ? 0 : Self.nestedIndent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.select(entry.id) }
    }
}

/// 正文区：载入中显示进度，失败时说明原因
private struct GuideDetail: View {
    let model: UserGuideModel

    var body: some View {
        GuideDocumentView(controller: model.document)
            .overlay {
                switch model.phase {
                case .idle, .loading:
                    ProgressView()
                        .controlSize(.small)
                case .failed:
                    ContentUnavailableView(
                        "The user guide couldn't be loaded.",
                        systemImage: "book.closed",
                        description: Text("Reinstall Cubby to restore it.")
                    )
                case .ready:
                    EmptyView()
                }
            }
    }
}

/// 把正文的 NSScrollView 放进 SwiftUI（视图由 GuideTextController 持有，只创建一次）
private struct GuideDocumentView: NSViewRepresentable {
    let controller: GuideTextController

    func makeNSView(context: Context) -> NSScrollView {
        controller.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
