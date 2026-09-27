import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CubbyCore

/// 忽略的应用：不记录这些应用中复制的内容。
/// 列表放在定高的框内滚动，保证设置页整体高度固定、页面本身不滚动（见 SettingsHostingController 说明）。
struct IgnoredAppsSection: View {
    @Bindable var settings: AppSettings

    private static let rowHeight: CGFloat = 44
    private static let maxVisibleRows = 3

    var body: some View {
        let allApps = settings.ignoredBundleIDs.map(InstalledApp.init(bundleID:))
        let apps = allApps.filter(Self.isVisible)
        Section {
            if apps.isEmpty {
                Text("No ignored apps")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(apps.enumerated()), id: \.element.bundleID) { index, app in
                            if index > 0 { Divider() }
                            IgnoredAppRow(app: app) {
                                settings.removeIgnoredApp(bundleID: app.bundleID)
                            }
                            .frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(height: CGFloat(min(apps.count, Self.maxVisibleRows)) * Self.rowHeight)
                .scrollIndicators(apps.count > Self.maxVisibleRows ? .automatic : .never)
                // 设置页整体禁用了滚动（环境值会透传到子树），列表框需显式恢复
                .scrollDisabled(false)
            }
            HStack {
                Spacer()
                Button("Add App…", action: pickApplications)
            }
        } header: {
            Text("Ignored Apps")
        } footer: {
            Text(Self.footerText(hiddenDefaultCount: allApps.count - apps.count))
                .foregroundStyle(.secondary)
        }
    }

    /// 已安装的应用 + 用户自行添加的应用；未安装的默认密码管理器只在说明中汇总，减少干扰
    private static func isVisible(_ app: InstalledApp) -> Bool {
        app.url != nil || !AppSettings.defaultIgnoredBundleIDs.contains(app.bundleID)
    }

    private static func footerText(hiddenDefaultCount: Int) -> String {
        guard hiddenDefaultCount > 0 else {
            return String(localized: "Anything you copy in these apps isn't recorded.", comment: "Ignored apps footer")
        }
        return String(
            localized: """
                Anything you copy in these apps isn't recorded. \
                \(hiddenDefaultCount) password managers that aren't installed are also ignored by default.
                """,
            comment: "Ignored apps footer. %lld = number of default password managers that aren't installed"
        )
    }

    private func pickApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = String(
            localized: "Choose apps whose copied content shouldn't be recorded",
            comment: "Open panel message"
        )
        panel.prompt = String(localized: "Ignore", comment: "Open panel button: ignore the chosen apps")

        let addSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            panel.urls
                .compactMap { Bundle(url: $0)?.bundleIdentifier }
                .forEach { settings.addIgnoredApp(bundleID: $0) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: addSelection)
        } else {
            addSelection(panel.runModal())
        }
    }
}

/// 通过 bundle ID 解析出的应用信息（未安装时只有 bundle ID）
private struct InstalledApp {
    /// 默认忽略列表中的应用名称，未安装时也能显示可读的名字
    private static let knownNames: [String: String] = [
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "com.apple.keychainaccess": String(localized: "Keychain Access", comment: "Name of the Apple app"),
        "com.apple.Passwords": String(localized: "Passwords", comment: "Name of the Apple app"),
        "org.keepassxc.keepassxc": "KeePassXC",
    ]

    let bundleID: String
    let url: URL?

    init(bundleID: String) {
        self.bundleID = bundleID
        self.url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var name: String {
        guard let url else { return Self.knownNames[bundleID] ?? bundleID }
        let displayName = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }

    /// 副标题：已安装的应用只显示名称（bundle ID 偏开发者视角）；未安装时说明原因
    var detail: String? {
        guard url == nil else { return nil }
        return name == bundleID
            ? String(localized: "Not installed", comment: "Ignored app that isn't installed")
            : String(
                localized: "\(bundleID) · Not installed",
                comment: "Ignored app that isn't installed. %@ = bundle ID"
            )
    }

    @MainActor
    var icon: NSImage? {
        url.map { ImageCache.shared.fileIcon(path: $0.path(percentEncoded: false)) }
    }
}

private struct IgnoredAppRow: View {
    let app: InstalledApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                Image(nsImage: ImageCache.shared.genericAppIcon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .opacity(0.5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                if let detail = app.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: FontSize.callout))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Stop Ignoring")
            .accessibilityLabel("Remove \(app.name)")
        }
    }
}
