import AppKit
import SwiftUI
import Translation
import os

/// 「下载语言」（docs/TRANSLATION-DESIGN.md §3.7）：Cubby 自己的小窗口通过 `.translationTask`
/// 调用 `prepareTranslation()`，由系统弹出语言包下载界面。下载与否完全由用户在系统界面中决定。
/// 不知道缺哪个语言对时（理论上不会发生）退回为说明 +「打开系统设置」，用户点「完成」后返回
@available(macOS 26, *)
@MainActor
final class LanguageDownloadWindowController {
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 显示窗口，等到系统下载流程结束（完成或取消）或用户关闭窗口。
    /// 返回是否值得重试：已知语言对时为「现在已安装」，未知时总是 true
    func download(_ pair: LanguagePair?) async -> Bool {
        if let window {
            // 已在进行中：提到前面，与进行中的那次一起等待
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            present(pair)
        }
        await withCheckedContinuation { waiters.append($0) }
        guard let pair else { return true }
        return await LanguageAvailability().status(from: pair.source, to: pair.target) == .installed
    }

    private func present(_ pair: LanguagePair?) {
        let view = LanguageDownloadView(pair: pair) { [weak self] in self?.finish() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "Download Languages", comment: "Language download window title")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
        self.window = window
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 下载流程结束或点了取消：关闭窗口（随后在 windowWillClose 中唤醒等待方）
    private func finish() {
        window?.close()
    }

    private func windowWillClose() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }
}

/// 下载窗口的内容：说明要下载的语言，出现后立即请求系统显示下载界面
@available(macOS 26, *)
private struct LanguageDownloadView: View {
    let pair: LanguagePair?
    let onFinish: @MainActor @Sendable () -> Void

    var body: some View {
        let content = VStack(spacing: 12) {
            Image(systemName: "translate")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text("Download languages to translate on this Mac")
                .font(.headline)
                .multilineTextAlignment(.center)
            if let pair {
                Text(verbatim: "\(name(pair.source)) → \(name(pair.target))")
                    .font(.title3.weight(.medium))
            }
            Text(pair == nil ? manualHint : promptHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Language & Region Settings", action: SystemTranslationSettings.open)
                Button(pair == nil ? "Done" : "Cancel", action: onFinish)
                    .keyboardShortcut(pair == nil ? .defaultAction : .cancelAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 400)
        if let pair {
            // 不在主线程上持有会话：闭包非隔离，会话只在其中使用
            content.translationTask(source: pair.source, target: pair.target) { @Sendable [onFinish] session in
                await Self.prepare(session)
                await onFinish()
            }
        } else {
            content
        }
    }

    private var promptHint: LocalizedStringKey {
        "Follow the system prompt to download the language files. After that, translation works offline and text never leaves this Mac."
    }

    private var manualHint: LocalizedStringKey {
        "Download the languages you need in System Settings › General › Language & Region › Translation Languages, then click Done."
    }

    private func name(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    /// 请求系统显示下载界面；用户取消或出错时只记录错误类型
    nonisolated private static func prepare(_ session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
        } catch {
            Logger(subsystem: "io.github.no1coder.Cubby", category: "Translation")
                .info("Language download ended: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}

/// 系统设置 › 通用 › 语言与地区（「翻译语言」在该页底部）
enum SystemTranslationSettings {
    static let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")

    @MainActor
    static func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
