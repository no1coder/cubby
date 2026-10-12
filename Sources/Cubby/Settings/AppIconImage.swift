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

    /// 与正式图标（design/cubby-logo）一致：圆角方形占 80%，从上到下 #4E90FF → #2358F2 → #1431B0 的蓝色渐变 + 白色托盘
    private var placeholder: some View {
        let plate = size * 0.8
        return RoundedRectangle(cornerRadius: plate * Radius.iconRatio, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0x4E / 255, green: 0x90 / 255, blue: 1), location: 0),
                        .init(color: Color(red: 0x23 / 255, green: 0x58 / 255, blue: 0xF2 / 255), location: 0.55),
                        .init(color: Color(red: 0x14 / 255, green: 0x31 / 255, blue: 0xB0 / 255), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Image(systemName: "tray.full.fill")
                    .font(.system(size: plate * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            )
            .frame(width: plate, height: plate)
    }
}
