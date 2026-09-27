import AppKit
import CubbyCore

/// 首用引导（评审 P1-8）：前 3 次截图会话的 hovering 阶段，在屏幕底部居中显示一行「现在可以做什么」，
/// 第一次按下鼠标（或离开 hovering）时淡出。
///
/// 计数直接读写 `UserDefaults` 的 `screenshotOnboardingHintCount`，**不**放进 `AppSettings`：
/// 它只属于覆盖层、没有设置界面，放进 AppSettings 会与正在修改该文件的其他改动冲突，也不需要迁移。
@MainActor
enum OverlayOnboarding {
    static let defaultsKey = "screenshotOnboardingHintCount"
    /// 显示引导的会话数
    static let sessionLimit = 3

    private enum State {
        /// 新会话尚未决定是否显示（第一次渲染 hovering 时决定并计数）
        case undecided
        case showing
        case dismissed
    }

    private static var state = State.dismissed
    /// 同一轮事件循环内创建的多块屏幕属于同一个会话，只开始一次
    private static var isBeginningSession = false

    /// 画布创建时调用：每块屏幕一个画布，同一轮事件循环内只算一次会话
    static func sessionWillBegin() {
        guard !isBeginningSession else { return }
        isBeginningSession = true
        state = .undecided
        Task { @MainActor in isBeginningSession = false }
    }

    /// 本次渲染是否显示引导：只在 hovering；会话第一次渲染时决定并把计数 +1
    static func isVisible(phase: ScreenshotPhase, defaults: UserDefaults = .standard) -> Bool {
        guard phase == .hovering else {
            state = .dismissed
            return false
        }
        if state == .undecided {
            let count = defaults.integer(forKey: defaultsKey)
            state = count < sessionLimit ? .showing : .dismissed
            if state == .showing {
                defaults.set(count + 1, forKey: defaultsKey)
            }
        }
        return state == .showing
    }

    /// 第一次按下鼠标：本会话不再显示
    static func dismiss() {
        state = .dismissed
    }

    /// 引导文案
    static var message: String {
        String(
            localized: "Drag to select · Click for window · Space clean window · Esc to cancel",
            comment: "First-run hint at the bottom of the screenshot overlay"
        )
    }
}

/// 引导条图层：黑 0.78 胶囊 + 白字，放在画布最上层、屏幕底部居中；隐藏时 0.25 s 淡出
@MainActor
final class OverlayOnboardingLayer {
    let layer = CALayer()
    private var isShown = false

    init() {
        layer.isHidden = true
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = OverlayTokens.onboardingShadowOpacity
        layer.shadowRadius = OverlayTokens.onboardingShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: OverlayTokens.onboardingShadowOffsetY)
    }

    /// 显示时按文案生成胶囊（首次）并放到底部居中；隐藏时淡出
    func update(visible: Bool, space: OverlaySpace) {
        guard visible != isShown else { return }
        isShown = visible
        if visible {
            show(space: space)
        } else {
            fadeOut()
        }
    }

    private func show(space: OverlaySpace) {
        let image = Self.capsuleImage(OverlayOnboarding.message)
        let size = image.size
        let x = space.pixelRounded((space.size.width - size.width) / 2)
        // 图层坐标 y 向上：底边距屏幕底边 onboardingBottomInset
        layer.frame = CGRect(x: x, y: OverlayTokens.onboardingBottomInset, width: size.width, height: size.height)
        layer.contents = image
        layer.contentsScale = space.scale
        layer.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerWidth: size.height / 2,
            cornerHeight: size.height / 2,
            transform: nil
        )
        layer.removeAllAnimations()
        layer.opacity = 1
        layer.isHidden = false
    }

    private func fadeOut() {
        guard !OverlayMotion.isReduced else {
            layer.isHidden = true
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = OverlayTokens.hintFadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 0
        layer.add(fade, forKey: "fadeOut")
    }

    /// 胶囊图片（按点绘制，CALayer 按 contentsScale 取清晰的表示）
    private static func capsuleImage(_ text: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: FontSize.body, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = CGSize(
            width: (textSize.width + OverlayTokens.onboardingHorizontalPadding * 2).rounded(.up),
            height: (textSize.height + OverlayTokens.onboardingVerticalPadding * 2).rounded(.up)
        )
        return NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(OverlayTokens.labelBackgroundAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            let origin = CGPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
    }
}
