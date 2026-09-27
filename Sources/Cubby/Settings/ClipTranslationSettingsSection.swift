import AppKit
import SwiftUI
import CubbyCore

/// 设置 › 翻译 › 剪贴板（docs/CLIP-TRANSLATION-DESIGN.md §7）：复制时自动翻译、在卡片上显示译文、
/// 按粘贴目标应用记住的目标语言（A8）与「清除全部译文」
struct ClipTranslationSettingsSection: View {
    @Bindable var settings: AppSettings
    let store: ClipStore
    @State private var isConfirmingClear = false

    var body: some View {
        Section {
            Toggle(isOn: translatesOnCopy) {
                Text("Translate text when you copy it")
                Text("Only uses system translation on this Mac. Requires the language to be downloaded.")
            }
            Toggle("Show translations on cards", isOn: $settings.showsTranslationOnCards)
            RememberedTargetsView(settings: settings)
            LabeledContent("Saved translations") {
                Button("Clear All Translations…") { isConfirmingClear = true }
                    .disabled(!hasTranslations)
            }
        } header: {
            Text("Clipboard")
        }
        .confirmationDialog(ClearTranslationsCopy.title, isPresented: $isConfirmingClear) {
            Button(ClearTranslationsCopy.confirm, role: .destructive) { store.clearTranslations() }
        } message: {
            Text(ClearTranslationsCopy.message)
        }
    }

    /// 打开自动翻译时一并打开「在卡片上显示译文」（AppSettings.setTranslatesClipsOnCopy）
    private var translatesOnCopy: Binding<Bool> {
        Binding {
            settings.translatesClipsOnCopy
        } set: {
            settings.setTranslatesClipsOnCopy($0)
        }
    }

    private var hasTranslations: Bool {
        store.history.items.contains(where: \.hasTranslations)
    }
}

/// 「粘贴到 <应用> 时总是译为」记住的语言：每个应用一行，可移除。
/// 列表放在定高的框内滚动（最多显示 3 行），设置页整体高度不随应用数增长（同 IgnoredAppsSection）
private struct RememberedTargetsView: View {
    @Bindable var settings: AppSettings

    private static let rowHeight: CGFloat = 32
    private static let maxVisibleRows = 3

    var body: some View {
        let entries = settings.clipTranslationTargets.sortedEntries
        LabeledContent {
            if entries.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
        } label: {
            Text("Target language by app")
            Text("Set from the language menu of the translation card")
        }
        if !entries.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries, id: \.bundleID) { entry in
                        RememberedTargetRow(app: PasteTargetApp(bundleID: entry.bundleID), language: entry.language) {
                            settings.rememberClipTranslationTarget(nil, for: entry.bundleID)
                        }
                        .frame(height: Self.rowHeight)
                    }
                }
            }
            .frame(height: CGFloat(min(entries.count, Self.maxVisibleRows)) * Self.rowHeight)
            .scrollIndicators(entries.count > Self.maxVisibleRows ? .automatic : .never)
            // 设置页整体禁用了滚动（环境值会透传到子树），列表框需显式恢复
            .scrollDisabled(false)
        }
    }
}

private struct RememberedTargetRow: View {
    let app: PasteTargetApp
    let language: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
            Text(verbatim: app.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(verbatim: TranslationLanguageCatalog.localizedName(of: language))
                .foregroundStyle(.secondary)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Forget This App's Language")
            .accessibilityLabel(Text("Forget the language for \(app.name)"))
        }
    }
}

/// 粘贴目标应用：按 bundle id 找到已安装的应用取名称与图标；未安装时显示 bundle id 与通用图标
private struct PasteTargetApp {
    let bundleID: String
    let url: URL?

    init(bundleID: String) {
        self.bundleID = bundleID
        self.url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var name: String {
        guard let url else { return bundleID }
        let displayName = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }

    @MainActor
    var icon: NSImage {
        url.map { ImageCache.shared.fileIcon(path: $0.path(percentEncoded: false)) } ?? ImageCache.shared.genericAppIcon
    }
}

/// 清除全部译文的确认文案
enum ClearTranslationsCopy {
    static var title: String {
        String(localized: "Clear all translations?", comment: "Clear translations confirmation title")
    }

    static var message: String {
        String(
            localized: "Translations saved with your history items will be deleted. Your history isn't affected.",
            comment: "Clear translations confirmation message")
    }

    static var confirm: String {
        String(localized: "Clear Translations", comment: "Clear translations confirmation button")
    }
}
