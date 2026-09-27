import AppKit
import SwiftUI
import CubbyCore

/// 设置 › 通用 › 截图：截图快捷键（可关闭）、存储时是否询问位置、默认保存位置
struct ScreenshotSettingsSection: View {
    @Bindable var settings: AppSettings
    let onShortcutRecordingChange: (Bool) -> Void

    var body: some View {
        Section {
            LabeledContent("Screenshot shortcut") {
                ScreenshotShortcutRecorder(settings: settings, onRecordingChange: onShortcutRecordingChange)
            }
            LabeledContent {
                // 与同组快捷键录制器的按钮（small）保持同一尺寸
                HStack(spacing: 8) {
                    if settings.screenshotSaveDirectory != nil {
                        Button("Reset") { settings.screenshotSaveDirectory = nil }
                    }
                    Button("Choose Folder…", action: chooseFolder)
                }
                .controlSize(.small)
            } label: {
                Text("Save screenshots to")
                Text(verbatim: locationDescription)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(folderBehavior)
            }
            Toggle(isOn: $settings.asksWhereToSaveScreenshots) {
                Text("Ask where to save each time")
                Text("Choose the folder and file name in a save dialog when you save a screenshot.")
            }
        } header: {
            Text("Screenshots")
        }
    }

    /// 文件夹这一行的说明随「每次询问」变化：询问时它是对话框的起始位置，否则是直接存入的位置
    private var folderBehavior: String {
        settings.asksWhereToSaveScreenshots
            ? String(
                localized: "The save dialog opens the last folder you used.",
                comment: "Screenshot settings: folder row note when asking where to save each time")
            : String(
                localized: "Screenshots are saved here without asking.",
                comment: "Screenshot settings: folder row note when saving directly")
    }

    /// 「与系统截图相同 · ~/Desktop」或自定义目录（~ 缩写，避免在界面上露出完整的用户目录）
    private var locationDescription: String {
        guard let custom = settings.screenshotSaveDirectory else {
            let system = ScreenshotSaveLocation.resolved(preferred: nil).path
            let title = String(
                localized: "Same as macOS screenshots",
                comment: "Screenshot save location option: follow the macOS screenshot folder"
            )
            return "\(title) · \((system as NSString).abbreviatingWithTildeInPath)"
        }
        return (custom.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ScreenshotSaveLocation.resolved(preferred: settings.screenshotSaveDirectory)
        panel.prompt = String(localized: "Choose", comment: "Confirm button of the screenshot folder picker")
        let apply: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            settings.screenshotSaveDirectory = url
        }
        // 以设置窗口的表单形式弹出；找不到窗口时退回独立面板
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            panel.begin(completionHandler: apply)
        }
    }
}

/// 截图快捷键录制器（设置与首次引导共用）：可以关闭，不能与面板快捷键相同
struct ScreenshotShortcutRecorder: View {
    @Bindable var settings: AppSettings
    /// 是否显示「关闭」按钮（引导页空间有限，只在设置中提供）
    var allowsTurningOff = true
    let onRecordingChange: (Bool) -> Void

    var body: some View {
        ShortcutRecorder(
            optionalHotKey: $settings.screenshotHotKey,
            defaultHotKey: .screenshotDefault,
            allowsClearing: allowsTurningOff,
            reservations: [
                .init(hotKey: settings.hotKey, message: ShortcutReservationCopy.panel)
            ],
            onRecordingChange: onRecordingChange
        )
    }
}

/// 录制器拒绝「与另一个全局快捷键相同」时的原因
enum ShortcutReservationCopy {
    static var panel: String {
        String(localized: "Already used to open the panel", comment: "Shortcut recorder error")
    }

    static var screenshots: String {
        String(localized: "Already used for screenshots", comment: "Shortcut recorder error")
    }
}
