#if DEBUG
import AppKit
import SwiftUI

/// 设计稿走查的背景（`--backdrop`）：在面板之下、其他应用的窗口之上铺一张与设计稿相近的壁纸，
/// 截取面板所在区域时只会拍到 Cubby 自己的窗口，又能看出玻璃的通透程度
@MainActor
enum DesignBackdrop {
    static let argument = "--backdrop"

    private static var windows: [NSWindow] = []

    static func showIfRequested() {
        guard CommandLine.arguments.contains(argument) else { return }
        windows = NSScreen.screens.map(makeWindow)
        windows.forEach { $0.orderFrontRegardless() }
    }

    private static func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // 高于普通窗口、低于面板（.floating）
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: Wallpaper())
        window.setFrame(screen.frame, display: false)
        return window
    }
}

/// 设计稿的壁纸：深色为深蓝底 + 左上蓝紫、右侧橙棕、底部青色的大块柔光；浅色为浅灰蓝底 + 淡彩柔光
private struct Wallpaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                (isDark ? Color(red: 0.05, green: 0.07, blue: 0.13) : Color(red: 0.91, green: 0.92, blue: 0.96))
                glow(
                    isDark ? Color(red: 0.2, green: 0.25, blue: 0.75) : Color(red: 0.62, green: 0.68, blue: 1),
                    at: CGPoint(x: size.width * 0.15, y: size.height * 0.25), radius: size.width * 0.45)
                glow(
                    isDark ? Color(red: 0.55, green: 0.28, blue: 0.18) : Color(red: 1, green: 0.78, blue: 0.66),
                    at: CGPoint(x: size.width * 0.88, y: size.height * 0.45), radius: size.width * 0.4)
                glow(
                    isDark ? Color(red: 0.05, green: 0.35, blue: 0.38) : Color(red: 0.7, green: 0.9, blue: 0.9),
                    at: CGPoint(x: size.width * 0.5, y: size.height * 1.05), radius: size.width * 0.35)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, at center: CGPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(0.85), color.opacity(0)], center: .center, startRadius: 0, endRadius: radius
        )
        .frame(width: radius * 2, height: radius * 2)
        .position(center)
    }
}
#endif
