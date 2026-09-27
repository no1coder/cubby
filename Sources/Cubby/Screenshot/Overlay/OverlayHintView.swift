import AppKit

/// 覆盖层内的小提示 HUD（例如「Press Esc again to discard」）：约 1.5 秒后淡出
///
/// 放在覆盖层窗口内部而不是独立窗口：与冻结帧同层，不会被其他窗口挡住，也不抢焦点。
final class OverlayHintView: OverlayPassthroughView {
    private let label = NSTextField(labelWithString: "")
    private var generation = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(OverlayTokens.hintBackgroundAlpha).cgColor
        layer?.cornerCurve = .continuous
        label.font = NSFont.systemFont(ofSize: FontSize.body, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 以 center（视图坐标）为中心显示 message，随后自动淡出
    func show(_ message: String, centeredAt center: CGPoint, within bounds: CGRect) {
        label.stringValue = message
        let textSize = label.intrinsicContentSize
        let size = CGSize(
            width: (textSize.width + OverlayTokens.hintHorizontalPadding).rounded(.up),
            height: (textSize.height + OverlayTokens.hintVerticalPadding).rounded(.up)
        )
        var origin = CGPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        frame = CGRect(origin: origin, size: size)
        label.frame = CGRect(x: 0, y: (size.height - textSize.height) / 2, width: size.width, height: textSize.height)
        layer?.cornerRadius = size.height / 2
        // 上一次的淡出可能还在进行：先停掉，否则会继续淡到 0
        layer?.removeAllAnimations()
        alphaValue = 1
        isHidden = false

        generation += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: OverlayTokens.hintDisplayDuration)
            guard let self, current == self.generation else { return }
            self.fadeOut(generation: current)
        }
    }

    private func fadeOut(generation current: Int) {
        guard !OverlayMotion.isReduced else {
            isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = OverlayTokens.hintFadeDuration
                self.animator().alphaValue = 0
            },
            completionHandler: {
                Task { @MainActor [weak self] in
                    guard let self, current == self.generation else { return }
                    self.isHidden = true
                }
            }
        )
    }
}

#if DEBUG
extension OverlayHintView {
    /// 仅调试构建（e2e）：可见时的提示文本
    var debugMessage: String? {
        isHidden ? nil : label.stringValue
    }
}
#endif
