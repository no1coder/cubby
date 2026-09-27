import AppKit

/// 面板外观容器：macOS 26 使用 Liquid Glass，更早系统回退为毛玻璃
@MainActor
enum PanelChrome {
    static var cornerRadius: CGFloat {
        Radius.panel
    }

    /// 将 SwiftUI 宿主视图包进带圆角的玻璃 / 毛玻璃容器；圆角默认为面板圆角（截图工具栏等传 Radius.card）
    static func makeContainer(for content: NSView, cornerRadius: CGFloat = PanelChrome.cornerRadius) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = content
            return roundedClip(glass, cornerRadius: cornerRadius)
        }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        // 面板所属应用不在前台，强制保持激活外观
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }

    /// 圆角裁剪容器：玻璃所在窗口成为 key 时，玻璃会在圆角外再画一层投影，
    /// 无边框窗口会把它截成直角，系统窗口阴影也随之变成矩形（角上露出直角描边）。
    /// 裁掉圆角外的一切绘制；玻璃的圆角是圆弧而非连续曲线，裁剪曲线须与之一致，否则会削掉玻璃边缘。
    private static func roundedClip(_ view: NSView, cornerRadius: CGFloat) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .circular
        container.layer?.masksToBounds = true
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    /// 可拉伸的圆角蒙版
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
