import AppKit
import SwiftUI

/// 应用图标。以 .app 运行时使用 NSApp.applicationIconImage；
/// 开发时直接运行可执行文件没有图标，退化为同风格的 SF Symbol 图标。
struct AppIconImage: View {
    let size: CGFloat

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var body: some View {
        Group {
            if isRunningFromAppBundle {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 与正式图标一致：圆角方形占 80%，紫蓝渐变 + 白色剪贴板
    private var placeholder: some View {
        let plate = size * 0.8
        return RoundedRectangle(cornerRadius: plate * Radius.iconRatio, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.36, blue: 0.98), Color(red: 0.23, green: 0.45, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: plate * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            )
            .frame(width: plate, height: plate)
    }
}
