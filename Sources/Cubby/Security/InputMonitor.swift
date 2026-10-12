import AppKit
import CoreGraphics
import os

/// 可选的「输入监控」（docs/UI-UPGRADE-PLAN.md §6.2）：只在地址守护开启且已获授权时安装 listen-only 的 CGEventTap，
/// 只判断「按下了 ⌘C 或 ⌘X」（按字符判断，兼容各种键盘布局），判断完立即丢弃，不记录、不保存、不记日志任何按键内容。
/// 从不自动请求权限：只有设置里的「去授权」按钮才会调用 CGRequestListenEventAccess
@MainActor
final class InputMonitor {
    /// 拷贝与剪切的字符（不区分大小写，⇧⌘C 也算）
    nonisolated static let copyCharacters: Set<String> = ["c", "x"]
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")

    /// 看到 ⌘C / ⌘X
    var onCopyKeystroke: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Security")

    var isRunning: Bool { tap != nil }

    /// 只查询，不触发系统询问
    static var isAuthorized: Bool {
        CGPreflightListenEventAccess()
    }

    /// 设置里的「去授权」：向系统申请（首次会让 Cubby 出现在列表里），并打开系统设置 › 隐私与安全性 › 输入监控
    static func requestAccess() {
        _ = CGRequestListenEventAccess()
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }

    /// 按开关与授权状态安装或移除监听；返回是否在运行
    @discardableResult
    func update(enabled: Bool) -> Bool {
        if enabled, Self.isAuthorized {
            start()
        } else {
            stop()
        }
        return isRunning
    }

    private func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: inputMonitorCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            logger.error("Could not install the keyboard listener")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    /// 回调里只拿到「是不是 ⌘C / ⌘X」，按键本身不离开回调
    fileprivate func handle(type: CGEventType, isCopy: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown where isCopy:
            onCopyKeystroke?()
        default:
            break
        }
    }
}

/// 事件回调（运行在主线程的运行循环上）：listen-only，事件原样放行
private func inputMonitorCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    // 只看带 ⌘ 的按键对应的字符是不是 c / x；其他按键连字符都不取
    let isCopy =
        type == .keyDown && event.flags.contains(.maskCommand)
        && NSEvent(cgEvent: event)?.charactersIgnoringModifiers.map {
            InputMonitor.copyCharacters.contains($0.lowercased())
        } == true
    let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handle(type: type, isCopy: isCopy)
    }
    return Unmanaged.passUnretained(event)
}
