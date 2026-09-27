import AppKit
import CubbyCore
import SwiftUI

/// 悬停目标标签的内容：应用图标 + 名称 + 像素尺寸，重叠时的层级与提示
struct HoverInfoModel: Equatable {
    /// 应用图标（整屏或未知应用时为 nil，改用 symbol）
    var icon: NSImage?
    /// 图标的身份（进程号 / 屏幕 id），用于比较是否变化
    var iconIdentity: Int
    var symbolName: String
    var title: String?
    var sizeText: String
    /// 「2 / 4」：当前层（1 起）与总层数；只有可切换时才有值
    var depth: (index: Int, count: Int)?
    /// 第二行淡色提示
    var hint: String?
    /// 纯净窗口模式：强调色底
    var isWindowCapture: Bool

    static func == (lhs: HoverInfoModel, rhs: HoverInfoModel) -> Bool {
        lhs.iconIdentity == rhs.iconIdentity && lhs.symbolName == rhs.symbolName && lhs.title == rhs.title
            && lhs.sizeText == rhs.sizeText && lhs.depth?.index == rhs.depth?.index
            && lhs.depth?.count == rhs.depth?.count && lhs.hint == rhs.hint
            && lhs.isWindowCapture == rhs.isWindowCapture
    }
}

/// 悬停窗口 / 整屏的信息标签（PM 重点）：例如「[Safari 图标] Safari  1440 × 900  2 / 4」+「Tab ⇥ to cycle」
struct HoverInfoLabel: View {
    let model: HoverInfoModel

    var body: some View {
        VStack(alignment: .leading, spacing: OverlayTokens.hoverLineSpacing) {
            HStack(spacing: OverlayTokens.hoverItemSpacing) {
                iconView
                if let title = model.title {
                    Text(verbatim: title)
                        .font(.system(size: FontSize.caption, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: OverlayTokens.hoverTitleMaxWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(verbatim: model.sizeText)
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .monospacedDigit()
                    .opacity(model.title == nil ? 1 : 0.85)
                if let depth = model.depth {
                    Text(verbatim: "\(depth.index) / \(depth.count)")
                        .font(.system(size: FontSize.caption2, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, OverlayTokens.depthBadgeHorizontalPadding)
                        .padding(.vertical, OverlayTokens.depthBadgeVerticalPadding)
                        .background(Capsule().fill(Color.white.opacity(OverlayTokens.depthBadgeOpacity)))
                }
            }
            if let hint = model.hint {
                // 强调色底（窗口模式）上用更实的白与更大的字，保证对比度
                Text(verbatim: hint)
                    .font(
                        .system(
                            size: model.isWindowCapture ? FontSize.caption : FontSize.caption2,
                            weight: model.isWindowCapture ? .semibold : .medium
                        )
                    )
                    .opacity(
                        model.isWindowCapture ? OverlayTokens.hoverHintOpacityOnAccent : OverlayTokens.hoverHintOpacity
                    )
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, OverlayTokens.labelHorizontalPadding)
        .padding(
            .vertical,
            model.hint == nil ? OverlayTokens.labelVerticalPadding : OverlayTokens.hoverTwoLineVerticalPadding
        )
        .background(background)
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var iconView: some View {
        if let icon = model.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: OverlayTokens.hoverIconSize, height: OverlayTokens.hoverIconSize)
        } else {
            Image(systemName: model.symbolName)
                .font(.system(size: FontSize.caption, weight: .semibold))
                .frame(width: OverlayTokens.hoverIconSize, height: OverlayTokens.hoverIconSize)
        }
    }

    private var background: some View {
        let shape = RoundedRectangle(
            cornerRadius: model.hint == nil ? OverlayTokens.hoverCapsuleRadius : Radius.control, style: .continuous)
        let fill =
            model.isWindowCapture
            ? Color.accentColor.opacity(OverlayTokens.hoverAccentFillOpacity)
            : Color.black.opacity(OverlayTokens.labelBackgroundAlpha)
        return shape.fill(fill)
    }
}

/// 标签内容的来源：应用名与图标按进程号缓存（NSRunningApplication 查询有开销）
@MainActor
final class HoverInfoProvider {
    private struct AppInfo {
        let name: String?
        let icon: NSImage?
    }

    private var cache: [pid_t: AppInfo] = [:]

    /// hovering 阶段的标签内容；非 hovering 或无目标时为 nil
    func model(for session: ScreenshotSession, topology: ScreenTopology) -> HoverInfoModel? {
        guard session.phase == .hovering, let hover = session.hover else { return nil }
        let sizeText = SizeLabelPlacement.text(for: hover.selectionRect, scale: hover.screen.scale)
        // 候选的最后一项是整屏兜底，不算一层窗口
        let windowCount = max(WindowHitTester.candidates(at: session.cursor, in: topology).count - 1, 0)
        switch hover {
        case .window(let window, _):
            let app = appInfo(for: window.ownerPID)
            let depth = Self.depth(session.hoverDepth, windowCount: windowCount)
            return HoverInfoModel(
                icon: app.icon,
                iconIdentity: Int(window.ownerPID),
                symbolName: session.isWindowCaptureMode ? "camera.fill" : "macwindow",
                title: app.name,
                sizeText: sizeText,
                depth: session.isWindowCaptureMode ? nil : depth,
                hint: Self.windowHint(windowCapture: session.isWindowCaptureMode, overlapping: depth != nil),
                isWindowCapture: session.isWindowCaptureMode
            )
        case .screen(let screen):
            // 整屏不显示层级徽章；从窗口逐层切到整屏时提示 Tab 可以继续切换
            return HoverInfoModel(
                icon: nil,
                iconIdentity: -Int(screen.id) - 1,
                symbolName: "display",
                title: OverlayScreens.nsScreen(for: screen)?.localizedName,
                sizeText: sizeText,
                depth: nil,
                hint: windowCount > 0 ? Self.cycleHint : nil,
                isWindowCapture: false
            )
        }
    }

    /// 光标下有 ≥ 2 个窗口重叠时显示「第几层 / 共几层」（只数窗口）
    private static func depth(_ depth: Int, windowCount: Int) -> (index: Int, count: Int)? {
        guard windowCount > 1 else { return nil }
        return (min(depth, windowCount - 1) + 1, windowCount)
    }

    /// 窗口目标的第二行常驻提示：空格进入纯净窗口（招牌能力要被看见），重叠时再加 Tab 切层
    private static func windowHint(windowCapture: Bool, overlapping: Bool) -> String {
        if windowCapture {
            return String(
                localized: "Click to capture · ⌥ no shadow · Space to exit",
                comment: "Screenshot window capture mode hint under the window label"
            )
        }
        if overlapping {
            return String(
                localized: "Tab ⇥ cycle · Space clean window",
                comment:
                    "Screenshot hover hint when windows overlap: Tab cycles layers, Space captures the clean window"
            )
        }
        return String(
            localized: "Space for clean window",
            comment: "Screenshot hover hint: press Space to capture the window without what covers it"
        )
    }

    private static var cycleHint: String {
        String(localized: "Tab ⇥ to cycle", comment: "Screenshot hint: press Tab to cycle overlapping windows")
    }

    private func appInfo(for pid: pid_t) -> AppInfo {
        if let cached = cache[pid] {
            return cached
        }
        let app = NSRunningApplication(processIdentifier: pid)
        let info = AppInfo(name: app?.localizedName, icon: app?.icon)
        cache[pid] = info
        return info
    }
}
