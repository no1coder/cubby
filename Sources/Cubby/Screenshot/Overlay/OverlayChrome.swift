import AppKit
import SwiftUI

/// 覆盖层内的玻璃容器（工具栏、样式条）：SwiftUI 内容 + 材质 + 出现动效
///
/// macOS 26：`PanelChrome.makeContainer(for:cornerRadius: Radius.card)`（Liquid Glass，已处理 key 窗口的直角投影）；
/// 更早系统：`NSVisualEffectView(.hudWindow, withinWindow)`——覆盖层窗口不透明，behindWindow 会透出窗口背后的
/// 实时桌面而不是冻结帧，因此只能在窗口内混合（§2.6）。
@MainActor
final class OverlayGlassPanel<Content: View>: NSView {
    private let hosting: FirstMouseHostingView<Content>
    private let container: NSView
    private(set) var isShown = false
    /// fittingSize 需要一次 SwiftUI 布局，内容不变时复用
    private var cachedSize: CGSize?

    init(rootView: Content) {
        hosting = FirstMouseHostingView(rootView: rootView)
        container = Self.makeContainer(for: OverlayGlassUnderlay(content: hosting))
        super.init(frame: .zero)
        wantsLayer = true
        container.frame = bounds
        container.autoresizingMask = [.width, .height]
        addSubview(container)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 内容的理想尺寸（取整到点）
    var fittingContentSize: CGSize {
        if let cachedSize {
            return cachedSize
        }
        let size = hosting.fittingSize
        let rounded = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        cachedSize = rounded
        return rounded
    }

    func update(rootView: Content) {
        hosting.rootView = rootView
        cachedSize = nil
    }

    /// 显示 / 隐藏；从隐藏变为显示时 0.12 s 淡入并轻微放大（减弱动态效果时直接出现）
    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        isHidden = !shown
        guard shown, !OverlayMotion.isReduced, let layer else { return }
        layer.add(Self.appearAnimation(size: bounds.size), forKey: "appear")
    }

    // MARK: - 私有

    private static func makeContainer(for content: NSView) -> NSView {
        if #available(macOS 26, *) {
            return PanelChrome.makeContainer(for: content, cornerRadius: Radius.card)
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Radius.card
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    /// 透明度 0 → 1 + 以中心为锚点 0.96 → 1 的缩放（AppKit 图层锚点在左下角，需平移补偿）
    private static func appearAnimation(size: CGSize) -> CAAnimation {
        let scale = OverlayTokens.toolbarAppearScale
        var start = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        start = CATransform3DScale(start, scale, scale, 1)
        start = CATransform3DTranslate(start, -size.width / 2, -size.height / 2, 0)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.duration = OverlayTokens.toolbarAppearDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return group
    }
}

/// 玻璃与内容之间的一层窗口背景色（35%）：工具栏常压在网页、代码、棋盘格这类高对比内容上，
/// 纯玻璃会把底下的明暗透上来，图标可读性下降；垫一层底色后仍保留玻璃质感
final class OverlayGlassUnderlay: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    /// 在视图自己的外观下解析动态颜色（深浅色切换时 AppKit 会再次调用）
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor =
                NSColor.windowBackgroundColor.withAlphaComponent(OverlayTokens.glassUnderlayOpacity).cgColor
        }
    }
}

/// 覆盖层上不接收鼠标的装饰视图（放大镜、标签、提示）：点击穿透到画布
class OverlayPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
}
