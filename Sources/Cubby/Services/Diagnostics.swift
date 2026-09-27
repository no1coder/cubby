import AppKit
import Carbon.HIToolbox
import CubbyCore

/// 诊断信息：用于 Issue 反馈的纯文本环境摘要。**绝不包含任何剪贴板内容**。
@MainActor
enum Diagnostics {
    static func report(settings: AppSettings, store: ClipStore, dataSize: Int64?) -> String {
        let info = Bundle.main.infoDictionary
        let version =
            info?["CFBundleShortVersionString"] as? String
            ?? String(localized: "Development build", comment: "Version text when running without an app bundle")
        let build = info?["CFBundleVersion"] as? String ?? "-"
        let favorites = store.history.items.filter(\.isFavorite).count
        let unknown = String(localized: "Unknown", comment: "Diagnostics: unknown value")
        let architecture = machineArchitecture ?? unknown
        let signature =
            SigningInfo.current()?.summary
            ?? String(localized: "Unsigned", comment: "Diagnostics: code signature")
        let size = dataSize.map(DirectorySize.formatted) ?? unknown
        let languages = Locale.preferredLanguages.prefix(3).joined(separator: ", ")

        // 每行是「标签: 值」；布尔值与枚举原始值保持英文，便于维护者直接比对
        let lines = [
            "Cubby \(version) (\(build))",
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "-")",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            isTranslated
                ? String(localized: "Chip: \(architecture) (Rosetta)", comment: "Diagnostics line")
                : String(localized: "Chip: \(architecture)", comment: "Diagnostics line"),
            String(localized: "Install location: \(InstallLocation.description)", comment: "Diagnostics line"),
            String(localized: "Signature: \(signature)", comment: "Diagnostics line"),
            String(localized: "Clipboard access: \(PasteboardAccess.status.rawValue)", comment: "Diagnostics line"),
            String(
                localized: "Accessibility: \(AccessibilityAuthorization.status.rawValue)",
                comment: "Diagnostics line"
            ),
            String(
                localized: "Screen recording: \(ScreenRecordingAuthorization.status.rawValue)",
                comment: "Diagnostics line"
            ),
            String(
                localized: """
                    History items: \(store.history.items.count), favorites: \(favorites), \
                    limit: \(settings.historyLimit)
                    """,
                comment: "Diagnostics line"
            ),
            String(localized: "Data size: \(size)", comment: "Diagnostics line"),
            String(
                localized: """
                    Data format version: \(HistoryMigrator.currentVersion), \
                    load issue: \(describe(store.loadIssue))
                    """,
                comment: "Diagnostics line"
            ),
            String(
                localized: """
                    Shortcut: \(settings.hotKey.displayName), \
                    panel position: \(settings.panelPosition.rawValue)
                    """,
                comment: "Diagnostics line"
            ),
            String(
                localized: """
                    Paste directly: \(String(settings.pasteDirectly)), \
                    default paste format: \(settings.pasteFormat.rawValue)
                    """,
                comment: "Diagnostics line"
            ),
            String(
                localized: """
                    Recording paused: \(String(settings.isPaused)), \
                    skip likely secrets: \(String(settings.ignoresSecrets)), \
                    ignored apps: \(settings.ignoredBundleIDs.count)
                    """,
                comment: "Diagnostics line"
            ),
            String(
                localized: "Automatic update check: \(String(settings.checksForUpdatesAutomatically))",
                comment: "Diagnostics line"
            ),
            screenshotLine(settings: settings),
            String(
                localized: "Secure input: \(IsSecureEventInputEnabled() ? "on" : "off")",
                comment: "Diagnostics line. The value stays in English: on / off"
            ),
            String(localized: "System languages: \(languages)", comment: "Diagnostics line"),
        ]
        return lines.joined(separator: "\n")
    }

    /// 截图快捷键与保存位置；保存位置只写「系统默认 / 自定义」，不写路径（可能暴露私人文件夹名）
    private static func screenshotLine(settings: AppSettings) -> String {
        let shortcut = settings.screenshotHotKey?.displayName ?? "off"
        let location = settings.screenshotSaveDirectory == nil ? "system default" : "custom"
        return String(
            localized: "Screenshot shortcut: \(shortcut), save location: \(location)",
            comment: "Diagnostics line. Values stay in English: off / system default / custom"
        )
    }

    /// 复制到剪贴板并带上自身写入标记，避免被记录进历史
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
    }

    private static func describe(_ issue: ClipStore.LoadIssue?) -> String {
        switch issue {
        case nil:
            String(localized: "None", comment: "Diagnostics: no history load issue")
        case .restoredFromCorruption:
            String(localized: "History file was damaged and backed up", comment: "Diagnostics: history load issue")
        case .newerVersion(let version):
            String(
                localized: "Created by a newer version (v\(version)), read-only",
                comment: "Diagnostics: history load issue"
            )
        case .unreadable:
            String(localized: "Unreadable, read-only", comment: "Diagnostics: history load issue")
        }
    }

    /// 机型架构标识（如 arm64）；读取失败时为 nil
    private static var machineArchitecture: String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        // 去掉结尾的 NUL 后按 UTF-8 解码
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let machine = String(decoding: bytes, as: UTF8.self)
        return machine.isEmpty ? nil : machine
    }

    /// 是否以 Rosetta 转译运行
    private static var isTranslated: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }
}
