import AppKit
import SwiftUI
import CubbyCore

/// 设置 › 历史
struct HistorySettingsPane: View {
    @Bindable var settings: AppSettings
    let store: ClipStore

    @State private var diskUsage: Int64?
    @State private var isConfirmingClear = false

    /// 历史频繁变化时合并统计，避免反复遍历目录
    private static let usageDebounce: Duration = .milliseconds(400)

    private var favoriteCount: Int {
        store.history.items.lazy.filter(\.isFavorite).count
    }

    private var clearableCount: Int {
        store.history.items.count - favoriteCount
    }

    var body: some View {
        Form {
            Section {
                Picker("Keep up to", selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimitOptions, id: \.self) { limit in
                        Text("\(limit) items").tag(limit)
                    }
                }
            } footer: {
                Text("When the limit is reached, the oldest items are removed. Favorites don't count toward the limit.")
                    .foregroundStyle(.secondary)
            }

            Section {
                // 关闭时由 ImageTextIndexer 停止识别并清除已保存的文字
                Toggle(isOn: $settings.indexesImageText) {
                    Text("Search text in images")
                    Text("Text is recognized on this Mac and never uploaded")
                }
            }

            Section {
                LabeledContent("Items", value: itemSummary)
                LabeledContent("Storage used") {
                    if let diskUsage {
                        Text(DirectorySize.formatted(diskUsage))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                LabeledContent {
                    Button("Show in Finder", action: revealDataDirectory)
                } label: {
                    Text("Data folder")
                    Text(dataDirectoryPath)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Section {
                LabeledContent {
                    Button("Clear…", role: .destructive) { isConfirmingClear = true }
                        .disabled(clearableCount == 0)
                } label: {
                    Text("Clear history")
                    Text("Favorites are kept")
                }
            }
        }
        .formStyle(.grouped)
        .task(id: store.revision) { await refreshDiskUsage() }
        .confirmationDialog(ClearHistoryCopy.title, isPresented: $isConfirmingClear) {
            Button(ClearHistoryCopy.confirm, role: .destructive) { store.clearHistory() }
        } message: {
            Text(ClearHistoryCopy.message)
        }
    }

    private var itemSummary: String {
        let total = store.history.items.count
        return favoriteCount > 0
            ? String(localized: "\(total) items (\(favoriteCount) favorites)", comment: "Number of items in history")
            : String(localized: "\(total) items", comment: "Number of items in history")
    }

    private var dataDirectoryPath: String {
        (AppPaths.root.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    private func refreshDiskUsage() async {
        // 首次展示立即统计；之后等写盘告一段落再统计
        if diskUsage != nil {
            try? await Task.sleep(for: Self.usageDebounce)
            guard !Task.isCancelled else { return }
        }
        let bytes = await DirectorySize.bytes(at: AppPaths.root)
        guard !Task.isCancelled else { return }
        diskUsage = bytes
    }

    private func revealDataDirectory() {
        let root = AppPaths.root
        if FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([root])
        } else {
            // 尚未产生任何数据时打开上级目录
            NSWorkspace.shared.open(root.deletingLastPathComponent())
        }
    }
}
