#if DEBUG
import AppKit
import SwiftUI

/// 演示动图里的按键提示（例如「⌘⇧V」「↩」）：画面下方的小胶囊，只是显示，不产生任何按键
@MainActor
final class DemoKeyCaption {
    private let window: NSPanel
    private let model = Model()
    private var hideTask: Task<Void, Never>?

    @Observable
    @MainActor
    fileprivate final class Model {
        var keys = ""
        var label = ""
    }

    /// - Parameter center: 胶囊中心（AppKit 屏幕坐标）
    init(center: CGPoint) {
        window = NSPanel(
            contentRect: CGRect(x: center.x - 160, y: center.y - 24, width: 320, height: 48),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: CaptionView(model: model))
        window.alphaValue = 0
    }

    /// 显示 keys（加粗）与说明，seconds 秒后淡出
    func show(_ keys: String, _ label: String = "", for seconds: Double = 1.2) {
        model.keys = keys
        model.label = label
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            await DemoClock.pause(seconds)
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.25
                    self.window.animator().alphaValue = 0
                }, completionHandler: nil)
        }
    }

    private struct CaptionView: View {
        let model: Model

        var body: some View {
            HStack(spacing: 8) {
                Text(verbatim: model.keys)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                if !model.label.isEmpty {
                    Text(verbatim: model.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.72)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
