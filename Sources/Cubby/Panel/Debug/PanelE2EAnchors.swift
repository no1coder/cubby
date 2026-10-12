#if DEBUG
import AppKit
import SwiftUI

/// 面板 E2E 的锚点表：视图在窗口里的位置（窗口内容坐标，左上原点）。
/// 无障碍树在没有辅助客户端时是空的，所以用它来定位按钮与确认视图是否显示；只在 E2E 运行期间启用
@MainActor
final class PanelE2EAnchors {
    static let shared = PanelE2EAnchors()
    /// 只在 `--panel-e2e` 运行时开启，平时的调试构建不记录
    static var isEnabled = false

    private(set) var frames: [String: CGRect] = [:]
    /// 每个锚点由哪个视图实例登记：列表重建时新视图先登记、旧视图后消失，旧视图不能把新登记的删掉
    private var owners: [String: UUID] = [:]

    func set(_ name: String, frame: CGRect, owner: UUID) {
        frames[name] = frame
        owners[name] = owner
    }

    func remove(_ name: String, owner: UUID) {
        guard owners[name] == owner else { return }
        frames[name] = nil
        owners[name] = nil
    }

    func contains(_ name: String) -> Bool {
        frames[name] != nil
    }

    /// 锚点中心在 E2E 全局坐标（主屏左上原点、y 向下）里的位置
    func center(of name: String, in window: NSWindow) -> CGPoint? {
        frame(of: name, in: window).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    /// 锚点在 E2E 全局坐标里的矩形
    func frame(of name: String, in window: NSWindow) -> CGRect? {
        guard let local = frames[name], let content = window.contentView else { return nil }
        // 窗口内容坐标（左上原点）→ 窗口坐标（左下原点）→ 屏幕（AppKit）→ E2E 全局
        let windowRect = CGRect(
            x: local.minX, y: content.bounds.height - local.maxY, width: local.width, height: local.height)
        return ScreenTopologyProvider.toGlobal(window.convertToScreen(windowRect))
    }
}

/// 记录视图位置（.global 即宿主视图的左上原点坐标，宿主视图铺满窗口内容）
struct PanelE2EAnchorModifier: ViewModifier {
    let name: String
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        if PanelE2EAnchors.isEnabled {
            // 出现时与位置变化时都登记：列表重建后新视图的 onGeometryChange 有时不会给出初始值
            content
                .background {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .global)
                        Color.clear
                            .onAppear { PanelE2EAnchors.shared.set(name, frame: frame, owner: owner) }
                            .onChange(of: frame) { PanelE2EAnchors.shared.set(name, frame: frame, owner: owner) }
                    }
                }
                .onDisappear { PanelE2EAnchors.shared.remove(name, owner: owner) }
        } else {
            content
        }
    }
}
#endif
