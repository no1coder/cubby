import Observation
import SwiftUI
import os
import CubbyCore

/// 周期性读取权限状态，供视图实时展示（用户在系统设置中授权后自动更新）
@MainActor
@Observable
final class PermissionMonitor {
    private(set) var accessibility = PermissionState.accessibility
    /// 辅助功能授权是否因签名变化而失效（决定是否显示修复引导）
    private(set) var isAccessibilityStale = AccessibilityAuthorization.status == .stale
    private(set) var pasteboard = PermissionState.pasteboard
    private(set) var screenRecording = PermissionState.screenRecording
    /// 正在等待剪贴板权限的系统询问结果（按钮暂时禁用）
    private(set) var isRequestingPasteboard = false

    /// 上一次点击剪贴板权限按钮时剪贴板为空（系统没有询问）
    @ObservationIgnored private var clipboardWasEmpty = false
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Permissions")

    private static let refreshInterval: Duration = .seconds(1.5)

    func refresh() {
        let accessibilityStatus = AccessibilityAuthorization.status
        let newAccessibility = PermissionState.accessibility(accessibilityStatus)
        if newAccessibility != accessibility { accessibility = newAccessibility }
        let isStale = accessibilityStatus == .stale
        if isStale != isAccessibilityStale { isAccessibilityStale = isStale }
        let pasteboardStatus = PasteboardAccess.status
        if pasteboardStatus != .notDetermined { clipboardWasEmpty = false }
        let newPasteboard = PermissionState.pasteboard(pasteboardStatus, clipboardWasEmpty: clipboardWasEmpty)
        if newPasteboard != pasteboard { pasteboard = newPasteboard }
        let newScreenRecording = PermissionState.screenRecording
        if newScreenRecording != screenRecording { screenRecording = newScreenRecording }
    }

    /// 在视图的 .task 中调用，视图消失时随任务取消而停止
    func run() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// 剪贴板权限按钮：尚未询问过时读取一次剪贴板让系统当场询问，否则打开系统设置；
    /// 完成后立即重新检测，不必等下一次轮询
    func requestPasteboardAccess() async {
        guard !isRequestingPasteboard else { return }
        isRequestingPasteboard = true
        let outcome = await PasteboardAccess.performButtonAction()
        isRequestingPasteboard = false
        logger.info("Clipboard access button: \(String(describing: outcome), privacy: .public)")
        clipboardWasEmpty = outcome == .nothingToRead
        refresh()
    }
}
