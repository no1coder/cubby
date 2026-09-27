import AppKit
import SwiftUI

/// 翻译卡布局常量（原型数值，设计文档 A10）
enum TranslationCardMetrics {
    static let headerHeight: CGFloat = 56
    static let toolbarHeight: CGFloat = 40
    /// 卡片最小高度（最大与主面板等高）
    static let minHeight: CGFloat = 236
    /// 头部 + 工具条 + 底栏 + 两条 0.5pt 分割线
    static var chromeHeight: CGFloat {
        headerHeight + toolbarHeight + PanelMetrics.footerHeight + 1
    }
    /// 状态页（失败、不支持、密钥）的最小内容高度
    static let stateMinHeight: CGFloat = 176
    /// 正文内边距（上、左右、下）
    static let bodyTop: CGFloat = 14
    static let bodyHorizontal: CGFloat = 16
    static let bodyBottom: CGFloat = 16
    /// 卡片上译文行的强调色竖条宽度（A10）
    static let lineBarWidth: CGFloat = 2
}

/// 翻译界面的配色（与原型一致；链接、云端隐私行在深色外观下用浅一档的强调色，浅色外观下用深一档，保证对比度）
enum TranslationPalette {
    static let link = adaptive(
        dark: NSColor(srgbRed: 0.30, green: 0.64, blue: 1.0, alpha: 1),
        light: NSColor(srgbRed: 0.0, green: 0.40, blue: 0.85, alpha: 1))
    static let cloud = adaptive(
        dark: NSColor(srgbRed: 0.62, green: 0.78, blue: 1.0, alpha: 1),
        light: NSColor(srgbRed: 0.0, green: 0.36, blue: 0.78, alpha: 1))
    static let warning = Color.orange
    static let lock = Color(red: 1.0, green: 0.41, blue: 0.38)
    static let ok = Color.green

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}

/// 行内小转圈（10pt）
struct TranslationSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

/// 从左向右扫过的高光（等待中的骨架条、行内进度、图片识别中）；减弱动态效果时静止
struct ShimmerSweep: View {
    var tint: Color = .white.opacity(0.12)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [.clear, tint, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geometry.size.width * 0.6)
                .offset(x: geometry.size.width * phase)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.6 }
        }
    }
}

/// 骨架条：译文未到达时占位
struct SkeletonLine: View {
    let widthFraction: CGFloat

    /// 原型的六种宽度，循环使用
    static let fractions: [CGFloat] = [0.94, 0.86, 0.97, 0.72, 0.90, 0.60]

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(ShimmerSweep())
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: geometry.size.width * widthFraction)
        }
        .frame(height: 10)
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }
}

/// 流式输出时的插入点（2 × 14 强调色竖条，闪烁）
struct StreamingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    visible.toggle()
                }
            }
    }
}

/// 在不可成为 key 的预览面板里跟踪指针（SwiftUI 的悬停依赖窗口状态，这里用 activeAlways 的跟踪区域）。
/// 报告的位置以本视图左上角为原点
struct PointerTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                    owner: self))
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }

        /// 只跟踪指针，不拦截点击
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        #if DEBUG
        /// 面板 E2E：合成的鼠标移动不会触发跟踪区域，脚本直接报告指针位置（窗口坐标；nil 表示移出）
        func debugMove(toWindowPoint point: CGPoint?) {
            onMove?(point.map { convert($0, from: nil) })
        }
        #endif
    }
}
