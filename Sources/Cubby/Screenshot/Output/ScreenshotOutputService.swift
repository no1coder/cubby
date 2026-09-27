import AppKit
import CubbyCore
import SwiftUI
import os

/// 截图的出口：剪贴板、历史、文件、贴图与 HUD（设计文档 §2.8）。
/// 历史只在未暂停记录时写入；写剪贴板都带自身标记，剪贴板监听不会重复记录；
/// 剪贴板写入失败时仍写入历史（截图不丢），并以警告色提示。
/// 耗时的部分（PNG 编码、写文件、OCR、历史的摘要与落盘）在后台执行；主线程只写剪贴板（TIFF 由 Core 惰性提供）
@MainActor
struct ScreenshotOutputService {
    /// 写入历史的结果
    private enum HistoryResult: Equatable {
        case recorded
        /// 暂停记录、疑似密钥等规则跳过
        case skipped
        /// 超出历史大小限制
        case tooLarge
    }

    private let settings: AppSettings
    private let store: ClipStore
    private let recognizer: TextRecognizer
    private let pins: PinnedImageController
    /// 默认为系统剪贴板；调试时可换成独立的命名剪贴板，避免覆盖用户剪贴板
    private let pasteboard: NSPasteboard
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")

    init(
        settings: AppSettings,
        store: ClipStore,
        recognizer: TextRecognizer,
        pins: PinnedImageController,
        pasteboard: NSPasteboard = .general
    ) {
        self.settings = settings
        self.store = store
        self.recognizer = recognizer
        self.pins = pins
        self.pasteboard = pasteboard
    }

    /// 历史来源：图标取 Cubby 自身（bundle 已安装，能取到图标），名称显示「截图」
    static var screenshotSource: SourceApp {
        SourceApp(
            bundleID: Bundle.main.bundleIdentifier,
            name: String(localized: "Screenshot", comment: "Source name of screenshot items in the history")
        )
    }

    // MARK: - 出口

    func copy(_ export: ScreenshotExport) {
        copyImage(png: export.png, pixelSize: export.pixelSize, anchor: Self.anchor(for: export.selection))
    }

    /// 纯净窗口截图（§9.3）：复制并入历史，不进入标注
    func copyWindow(_ window: WindowImage, anchor: CGPoint) {
        Task {
            // PNG 编码可能要上百毫秒（大窗口），放到后台
            let png = await Task.detached(priority: .userInitiated) {
                ScreenshotExporter.pngData(window.image, scale: window.scale)
            }.value
            guard let png else {
                Self.logger.error("Failed to encode the window screenshot")
                warn(String(localized: "Couldn't copy", comment: "Error when copying an item"), at: anchor)
                return
            }
            let size = CGSize(width: window.image.width, height: window.image.height)
            copyImage(png: png, pixelSize: size, anchor: anchor)
        }
    }

    /// 直接存入默认文件夹（设置里关闭了「每次存储前询问位置」）
    func save(_ export: ScreenshotExport) {
        let anchor = Self.anchor(for: export.selection)
        let png = export.png
        let destination = ScreenshotSaveLocation.destination(preferred: settings.screenshotSaveDirectory)
        let fileName = ScreenshotFileNaming.fileName(date: Date())
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.write(png, fileName: fileName, to: destination)
            }.value
            switch result {
            case .success(let outcome):
                let history = recordImage(png: png, pixelSize: export.pixelSize)
                succeed(
                    Self.savedMessage(for: outcome), note: Self.note(for: history),
                    symbolName: "square.and.arrow.down", at: anchor)
            case .failure(let error):
                Self.logger.error("Failed to save screenshot: \(error.logDescription, privacy: .public)")
                warn(
                    String(localized: "Couldn't save the screenshot", comment: "HUD when saving a screenshot fails"),
                    at: anchor)
            }
        }
    }

    /// 写到存储对话框选定的位置（同名文件已由对话框确认替换）；入历史（暂停记录时除外），记住文件夹
    func save(_ export: ScreenshotExport, to url: URL) {
        let anchor = Self.anchor(for: export.selection)
        Task {
            switch await ScreenshotSaveWriter.write(export.png, to: url, settings: settings) {
            case .success(let written):
                let history = recordImage(png: export.png, pixelSize: export.pixelSize)
                succeed(
                    ScreenshotSaveWriter.savedMessage(for: written), note: Self.note(for: history),
                    symbolName: "square.and.arrow.down", at: anchor)
            case .failure(let error):
                Self.logger.error("Failed to save screenshot: \(error.logDescription, privacy: .public)")
                warn(
                    String(localized: "Couldn't save the screenshot", comment: "HUD when saving a screenshot fails"),
                    at: anchor)
            }
        }
    }

    /// 贴图本身就是反馈，不弹 HUD
    func pin(_ export: ScreenshotExport) {
        pins.pin(export)
        if recordImage(png: export.png, pixelSize: export.pixelSize) == .tooLarge {
            Self.logger.notice("Pinned screenshot too large for history")
        }
    }

    /// OCR 在后台执行；先提示「正在识别」，完成后复制文字并入历史
    func extractText(from image: CGImage, anchor: CGPoint) {
        HUDToast.show(
            String(localized: "Recognizing text…", comment: "HUD while recognizing text in a screenshot"),
            symbolName: "text.viewfinder",
            tint: .accentColor,
            at: anchor
        )
        Task {
            do {
                let text = try await recognizer.recognize(image)
                guard !text.isEmpty else {
                    warn(String(localized: "No text found", comment: "HUD when a screenshot has no text"), at: anchor)
                    return
                }
                deliverText(
                    text, success: String(localized: "Text copied", comment: "HUD after copying recognized text"),
                    symbolName: "checkmark.circle.fill", anchor: anchor)
            } catch {
                Self.logger.error("Text recognition failed: \((error as NSError).code, privacy: .public)")
                warn(
                    String(localized: "Couldn't recognize text", comment: "HUD when text recognition fails"),
                    at: anchor)
            }
        }
    }

    /// 复制一段文字（截图翻译的「复制译文」、开关在译文时的 ⌘T）：与 OCR 相同的剪贴板与历史规则
    /// （暂停记录时不入历史、疑似密钥不入历史），success 为成功提示
    func copyText(_ text: String, success: String, anchor: CGPoint) {
        deliverText(text, success: success, symbolName: "checkmark.circle.fill", anchor: anchor)
    }

    func copyColor(_ text: String, anchor: CGPoint) {
        deliverText(
            text, success: String(localized: "Copied \(text)", comment: "HUD after copying a color. %@ = color value"),
            symbolName: "eyedropper", anchor: anchor)
    }

    // MARK: - 剪贴板与历史

    private func copyImage(png: Data, pixelSize: CGSize, anchor: CGPoint) {
        var copied = true
        do {
            try ScreenshotPasteboard.write(png: png, to: pasteboard)
        } catch {
            Self.logger.error("Failed to write the screenshot to the pasteboard")
            copied = false
        }
        let history = recordImage(png: png, pixelSize: pixelSize)
        report(
            copied: copied, history: history,
            success: String(localized: "Copied to clipboard", comment: "HUD after copying an item"),
            symbolName: "checkmark.circle.fill", anchor: anchor)
    }

    private func deliverText(_ text: String, success: String, symbolName: String, anchor: CGPoint) {
        let copied = ScreenshotPasteboard.write(text: text, to: pasteboard)
        if !copied {
            Self.logger.error("Failed to write text to the pasteboard")
        }
        report(copied: copied, history: recordText(text), success: success, symbolName: symbolName, anchor: anchor)
    }

    /// 剪贴板失败时：入了历史就说明「已存入历史」，否则只说无法复制
    private func report(copied: Bool, history: HistoryResult, success: String, symbolName: String, anchor: CGPoint) {
        guard copied else {
            let message =
                history == .recorded
                ? String(
                    localized: "Couldn't copy to the clipboard. Saved to history.",
                    comment: "HUD when writing a screenshot to the pasteboard fails but it was added to the history")
                : String(localized: "Couldn't copy", comment: "Error when copying an item")
            warn(message, at: anchor)
            return
        }
        succeed(success, note: Self.note(for: history), symbolName: symbolName, at: anchor)
    }

    /// 入历史（后台计算摘要并写入文件，按调用顺序插入）
    private func recordImage(png: Data, pixelSize: CGSize) -> HistoryResult {
        guard !settings.isPaused else { return .skipped }
        guard png.count <= CaptureLimits.maxImageBytes else { return .tooLarge }
        let content = ClipContent.image(png: png, width: Int(pixelSize.width), height: Int(pixelSize.height))
        store.recordInBackground(content, source: Self.screenshotSource)
        return .recorded
    }

    /// 文字（OCR、取色）同样遵守「暂停记录」与「不记录疑似密钥」
    private func recordText(_ text: String) -> HistoryResult {
        let content = ClipContent.text(text)
        guard !settings.isPaused, settings.shouldRecord(content) else { return .skipped }
        guard text.utf8.count <= CaptureLimits.maxTextBytes else { return .tooLarge }
        store.recordInBackground(content, source: Self.screenshotSource)
        return .recorded
    }

    /// 附在成功提示后的说明：超出历史大小限制
    private static func note(for history: HistoryResult) -> String? {
        guard history == .tooLarge else { return nil }
        return String(
            localized: "Too large for history", comment: "HUD note when a screenshot exceeds the history limit")
    }

    // MARK: - 文件

    /// 首选目录不可用或拒绝写入（EACCES / EPERM）时回退桌面
    private nonisolated static func write(
        _ png: Data,
        fileName: String,
        to destination: ScreenshotSaveLocation.Destination
    ) -> Result<ScreenshotFileSaver.Outcome, ScreenshotFileSaver.SaveError> {
        Result { () throws(ScreenshotFileSaver.SaveError) in
            try ScreenshotFileSaver.save(png, to: destination, fallback: ScreenshotFileSaver.desktopDirectory) {
                folder in
                ScreenshotFileNaming.uniqueURL(in: folder, fileName: fileName) {
                    FileManager.default.fileExists(atPath: $0.path)
                }
            }
        }
    }

    private static func savedMessage(for outcome: ScreenshotFileSaver.Outcome) -> String {
        if outcome.usedFallback {
            return String(
                localized: "Saved to Desktop (folder unavailable)",
                comment: "HUD when the screenshot folder is unavailable and the file was saved to the Desktop")
        }
        return ScreenshotSaveWriter.savedMessage(for: outcome.url)
    }

    // MARK: - HUD

    /// HUD 出现在选区中心（用户视线所在处）
    static func anchor(for selection: CGRect) -> CGPoint {
        ScreenTopologyProvider.toAppKit(CGPoint(x: selection.midX, y: selection.midY))
    }

    private func succeed(
        _ message: String,
        note: String? = nil,
        symbolName: String = "checkmark.circle.fill",
        at anchor: CGPoint
    ) {
        let text = note.map { "\(message) · \($0)" } ?? message
        HUDToast.show(
            text, symbolName: note == nil ? symbolName : "exclamationmark.circle.fill",
            tint: note == nil ? .green : .orange, at: anchor)
    }

    private func warn(_ message: String, at anchor: CGPoint) {
        HUDToast.show(message, symbolName: "exclamationmark.triangle.fill", tint: .orange, at: anchor)
    }
}
