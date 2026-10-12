#if DEBUG
import AppKit

/// 演示动图里的「别的应用」窗口：都是 Cubby 自己的窗口，内容虚构，录屏时不会拍到用户真实的应用
@MainActor
enum DemoWindows {
    /// 与 --backdrop 的壁纸同层（排在它前面），低于面板与警示卡
    static let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

    /// 带标题栏的普通窗口外观（不激活应用、不抢焦点）
    static func documentWindow(title: String, frame: CGRect) -> NSPanel {
        let window = NSPanel(
            contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        window.title = title
        window.level = level
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(frame, display: false)
        // 非激活面板的红绿灯画得不像普通窗口：隐藏，只留标题
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        return window
    }

    /// 由屏幕左上原点的矩形（点）换算为 AppKit 窗口 frame（主屏）
    static func appKitFrame(topLeft rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 屏幕左上原点的点 → AppKit 点（主屏）
    static func appKitPoint(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    /// AppKit 点 → 屏幕左上原点的点（主屏；与覆盖层事件的坐标一致）
    static func topLeftPoint(_ point: CGPoint) -> CGPoint {
        appKitPoint(point)
    }
}

/// 粘贴目标：一个虚构的笔记窗口，粘贴时把文字接在末尾并短暂高亮
@MainActor
final class DemoNoteWindow {
    private let window: NSPanel
    private let textView: NSTextView
    private static let font = NSFont.systemFont(ofSize: 15)

    init(title: String, body: String, topLeft rect: CGRect) {
        window = DemoWindows.documentWindow(title: title, frame: DemoWindows.appKitFrame(topLeft: rect))
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = false
        textView = scroll.documentView as? NSTextView ?? NSTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.textStorage?.setAttributedString(Self.attributed(body))
        window.contentView = scroll
        window.orderFrontRegardless()
    }

    /// 在末尾插入文字（粘贴），插入的部分先高亮再淡回
    func paste(_ text: String) async {
        guard let storage = textView.textStorage else { return }
        let range = NSRange(location: storage.length, length: (text as NSString).length)
        storage.append(Self.attributed(text))
        storage.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.35), range: range)
        await DemoClock.pause(0.9)
        storage.removeAttribute(.backgroundColor, range: range)
    }

    func close() {
        window.orderOut(nil)
    }

    private static func attributed(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        return NSAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph])
    }
}

/// 晾衣绳演示用的假菜单栏：盖在屏幕顶部（真实菜单栏不是 Cubby 的窗口，录不进画面），
/// 层级高于收起时的晾衣绳窗口，让绳子看起来是从菜单栏下面拉出来的
@MainActor
final class DemoMenuBar {
    private let window: NSWindow

    init(on screen: NSScreen) {
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let frame = CGRect(
            x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .mainMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = DemoMenuBarView(frame: CGRect(origin: .zero, size: frame.size))
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }
}

/// 半透明深色条 + 左侧虚构的应用菜单 + 右侧时钟
private final class DemoMenuBarView: NSView {
    private static let menus = ["Notes", "File", "Edit", "Format", "View", "Window", "Help"]

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 0.82).setFill()
        bounds.fill()
        let midY = bounds.midY
        var x: CGFloat = 20
        if let apple = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular).applying(.init(paletteColors: [.white])))
        {
            apple.draw(
                in: CGRect(x: x, y: midY - apple.size.height / 2, width: apple.size.width, height: apple.size.height))
            x += apple.size.width + 22
        }
        for (index, title) in Self.menus.enumerated() {
            let font = NSFont.systemFont(ofSize: 13.5, weight: index == 0 ? .bold : .regular)
            x += draw(title, font: font, x: x, midY: midY) + 20
        }
        let clock = "Tue 9:41 AM"
        let font = NSFont.systemFont(ofSize: 13.5)
        let width = (clock as NSString).size(withAttributes: [.font: font]).width
        draw(clock, font: font, x: bounds.maxX - width - 18, midY: midY)
    }

    @discardableResult
    private func draw(_ text: String, font: NSFont, x: CGFloat, midY: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: x, y: midY - size.height / 2), withAttributes: attributes)
        return size.width
    }
}
#endif
