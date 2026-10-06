import AppKit
import os
import SwiftUI
import CubbyCore

/// 粘贴流程（docs/CLIP-TRANSLATION-DESIGN.md §4）：先「写入」剪贴板，再「投递」——无动画隐藏面板 → 120 ms →
/// 校验前台仍是目标应用 → 发送 ⌘V。条目与译文共用投递段；目标剪贴板可注入（E2E 用命名剪贴板）
@MainActor
final class PanelPaster {
    /// 结果提示
    struct HUDMessage {
        let text: String
        var symbolName = "checkmark.circle.fill"
        var tint: Color = .green
        /// nil = HUDToast 的默认时长
        var duration: Duration?
    }

    /// 等待面板关闭、焦点回到目标应用后再发送 ⌘V
    private static let pasteDelay: Duration = .milliseconds(120)
    /// 译文粘贴后的 HUD 停留时长（A7）
    static let translationHUDDuration: Duration = .milliseconds(2600)

    let pasteboard: NSPasteboard
    private let store: ClipStore
    private let settings: AppSettings
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Panel")

    init(store: ClipStore, settings: AppSettings, pasteboard: NSPasteboard) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
    }

    // MARK: - 写入

    /// 写入条目（按粘贴方式选格式）；失败时返回给用户看的原因
    func write(_ item: ClipItem, mode: PasteMode) -> String? {
        let format = mode == .alternate ? settings.pasteFormat.alternate : settings.pasteFormat
        let formats = format == .original ? store.formats(for: item) : [:]
        do {
            try PasteboardWriter.write(item, imageURL: store.imageURL(for: item), formats: formats, to: pasteboard)
            return nil
        } catch {
            logger.error("Failed to write to the pasteboard: \(String(describing: error), privacy: .public)")
            return Self.message(for: error)
        }
    }

    /// 写入译文：图片写译后 PNG；富文本条目按「默认粘贴格式」写 RTF / HTML + 纯文本；⇧↩ 只写纯文本。返回是否写入
    func write(_ request: TranslationPasteRequest) -> Bool {
        let result = request.result
        do {
            if let imageURL = result.imageURL {
                try PasteboardWriter.write(pngAt: imageURL, to: pasteboard)
            } else if let rich = result.richText, writesRichText(request.style) {
                try PasteboardWriter.write(richText: rich, plainText: result.plainText, to: pasteboard)
            } else {
                try PasteboardWriter.write(text: result.plainText, to: pasteboard)
            }
            return true
        } catch {
            logger.error("Failed to write a translation: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// 写入纯文本（拆词结果，docs/TEXT-PICK-DESIGN.md P10）：带本应用的写入标记，监听器跳过，不记录为新条目。返回是否写入
    func write(plainText: String) -> Bool {
        do {
            try PasteboardWriter.write(text: plainText, to: pasteboard)
            return true
        } catch {
            logger.error("Failed to write picked words: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// ↩ 按「默认粘贴格式」：保留格式时写富文本；⇧↩ 总是纯文本（A2）
    func writesRichText(_ style: TranslationPasteStyle) -> Bool {
        style == .standard && settings.pasteFormat == .original
    }

    // MARK: - 投递

    /// 投递段：提升原条目 → 无动画隐藏 → 直接粘贴或提示已复制。
    /// - Parameters:
    ///   - copyOnly: 只复制（⌘↩）
    ///   - copied: 没有粘贴（关闭了直接粘贴、没有目标应用）时的提示
    ///   - pasted: 已发送 ⌘V 之后的提示（条目粘贴不提示；译文粘贴注明引擎，A7）
    func deliver(
        promoting id: UUID, copyOnly: Bool, target: PasteTarget?, anchor: CGPoint,
        copied: HUDMessage, pasted: HUDMessage?, hidePanel: () -> Void
    ) {
        store.promote(id: id)
        hidePanel()

        guard !copyOnly, settings.pasteDirectly else {
            show(copied, at: anchor)
            return
        }
        guard PasteService.isTrusted else {
            PasteService.requestTrust()
            HUDToast.show(
                String(localized: "Copied · Allow Accessibility to paste directly", comment: "HUD after copying"),
                symbolName: "hand.raised.fill",
                tint: .orange,
                at: anchor
            )
            return
        }
        guard let target else {
            show(copied, at: anchor)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.pasteDelay)
            // 焦点已不在目标应用（例如期间切换了窗口）时不发送按键，避免误粘贴
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID else {
                HUDToast.show(
                    String(localized: "Target app changed, copied instead", comment: "HUD when the target lost focus"),
                    symbolName: "exclamationmark.circle.fill",
                    tint: .orange,
                    at: anchor
                )
                return
            }
            PasteService.sendPasteShortcut()
            if let pasted { Self.show(pasted, at: anchor) }
        }
    }

    private func show(_ message: HUDMessage, at anchor: CGPoint) {
        Self.show(message, at: anchor)
    }

    private static func show(_ message: HUDMessage, at anchor: CGPoint) {
        HUDToast.show(
            message.text, symbolName: message.symbolName, tint: message.tint,
            duration: message.duration ?? HUDToast.defaultDuration, at: anchor)
    }

    // MARK: - 文案

    static var copiedMessage: HUDMessage {
        HUDMessage(text: String(localized: "Copied to clipboard", comment: "HUD after copying an item"))
    }

    /// 译文的 HUD：注明引擎，云端带云图标（A7）
    static func translationMessage(_ request: TranslationPasteRequest, pasted: Bool, plainText: Bool) -> HUDMessage {
        let result = request.result
        return HUDMessage(
            text: TranslationCopy.pastedHUD(result, plainText: plainText, pasted: pasted),
            symbolName: result.isOnDevice ? "laptopcomputer" : "cloud.fill",
            tint: result.isOnDevice ? .green : .accentColor,
            duration: translationHUDDuration)
    }

    private static func message(for error: Error) -> String {
        switch error as? PasteboardWriteError {
        case .filesMissing: String(localized: "File no longer exists", comment: "Error when copying a file item")
        case .imageUnavailable: String(localized: "Image file is missing", comment: "Error when copying an image item")
        case .writeRejected, nil: String(localized: "Couldn't copy", comment: "Error when copying an item")
        }
    }
}
