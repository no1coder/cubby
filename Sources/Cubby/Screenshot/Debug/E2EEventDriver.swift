#if DEBUG
import AppKit
import CubbyCore

/// 端到端测试的合成输入（设计文档 §3.4.5 的事件路径）：构造 NSEvent，经 `NSApp.postEvent(_:atStart:)` 投递，
/// 与真实输入一样依次经过本地监听器（`OverlayKeyboard`）与窗口派发（hitTest → 视图 → `OverlayInteraction`）。
///
/// - 坐标一律为全局点（主屏左上原点、y 向下），驱动器换算到目标窗口的坐标；
/// - 每次投递后再投递一个「哨兵」事件并等它出队：此时前面的事件都已派发完毕，会话与视图已更新；
/// - 屏蔽层：运行期间丢弃本应用收到的真实鼠标 / 键盘事件（用户碰到鼠标不会干扰脚本），合成事件靠时间戳识别。
@MainActor
final class E2EEventDriver {
    enum DriverError: Error, CustomStringConvertible {
        case noWindow(CGPoint)
        case noKeyWindow
        case noTextView
        case eventCreationFailed(String)
        case queueTimedOut

        var description: String {
            switch self {
            case .noWindow(let point): "no Cubby window under global point (\(point.x), \(point.y))"
            case .noKeyWindow: "no key window to receive keyboard events"
            case .noTextView: "the first responder is not a text view"
            case .eventCreationFailed(let what): "could not create \(what) event"
            case .queueTimedOut: "the event queue did not drain in time"
            }
        }
    }

    /// 当前按住的修饰键（之后的鼠标 / 按键事件都带上）
    private(set) var modifiers: NSEvent.ModifierFlags = []
    /// 被屏蔽的真实事件数（汇总时打印）
    private(set) var blockedRealEvents = 0
    /// 别的应用抢走 key 后，发送按键前重新让覆盖层成为 key 的次数（汇总时打印）
    private(set) var refocusCount = 0
    /// 最近成为 key 的本应用窗口
    private weak var lastKeyWindow: NSWindow?
    private var keyObserver: (any NSObjectProtocol)?

    /// 已投递、尚未经过屏蔽层的合成事件时间戳（纳秒）。postEvent 以纳秒整数保存时间戳，
    /// 合成时间戳取整微秒，出队后按纳秒比较即可精确识别
    private var pending: Set<Int64> = []
    private var lastTimestamp: TimeInterval = 0
    private var eventNumber = 0
    private var monitor: Any?
    private var sentinelSerial = 0
    private var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    /// 按下鼠标时的窗口：拖动与松开都发给它（与真实的鼠标捕获一致）
    private var captureWindow: NSWindow?
    /// 最近一次按键按下时的窗口：松开发给它
    private weak var lastKeyDownWindow: NSWindow?
    /// 合成的空格正按住
    private var spaceHeld = false
    /// 最近一次鼠标事件的位置（全局点）
    private var lastPoint: CGPoint?

    private static let sentinelSubtype: Int16 = 0x2E2E
    /// 拖动路径插值的步长（点）
    private static let dragStep: CGFloat = 12
    private static let queueTimeout: Duration = .seconds(3)
    private static let shieldedTypes: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
        .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel, .keyDown, .keyUp,
        .flagsChanged, .magnify, .applicationDefined,
    ]

    // MARK: - 生命周期

    /// 屏蔽层必须先于覆盖层的键盘监听安装（本地监听器按安装顺序调用）
    func install() {
        guard monitor == nil else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated { self?.lastKeyWindow = window }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: Self.shieldedTypes) { [weak self] event in
            guard let self else { return event }
            return self.screen(event)
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
        keyObserver = nil
        for (serial, _) in waiters {
            resume(serial, arrived: false)
        }
    }

    /// 屏蔽层：放行合成事件与非本驱动的应用自定义事件，吞掉哨兵与真实输入
    private func screen(_ event: NSEvent) -> NSEvent? {
        if event.type == .applicationDefined {
            guard event.subtype.rawValue == Self.sentinelSubtype else { return event }
            resume(event.data1, arrived: true)
            return nil
        }
        if pending.remove(Self.nanoseconds(event.timestamp)) != nil {
            return event
        }
        blockedRealEvents += 1
        return nil
    }

    // MARK: - 鼠标

    func move(to point: CGPoint) async throws {
        try await mouse(.mouseMoved, at: point, clickCount: 0)
    }

    func click(at point: CGPoint, count: Int = 1) async throws {
        for index in 1...max(count, 1) {
            try await mouse(.leftMouseDown, at: point, clickCount: index)
            try await mouse(.leftMouseUp, at: point, clickCount: index)
        }
    }

    func rightClick(at point: CGPoint) async throws {
        try await mouse(.rightMouseDown, at: point, clickCount: 1)
        try await mouse(.rightMouseUp, at: point, clickCount: 1)
    }

    /// 在第一个点按下，经过其余各点（按步长插值）拖动，在最后一个点松开
    func drag(through points: [CGPoint]) async throws {
        guard let start = points.first else { return }
        try await mouse(.leftMouseDown, at: start, clickCount: 1)
        var previous = start
        for target in points.dropFirst() {
            for point in Self.interpolate(from: previous, to: target) {
                try await mouse(.leftMouseDragged, at: point, clickCount: 1)
            }
            previous = target
        }
        try await mouse(.leftMouseUp, at: previous, clickCount: 1)
    }

    func mouseDown(at point: CGPoint) async throws {
        try await mouse(.leftMouseDown, at: point, clickCount: 1)
    }

    /// 按住左键从上一个位置拖到 point（按步长插值）
    func mouseDragged(to point: CGPoint) async throws {
        for step in Self.interpolate(from: lastPoint ?? point, to: point) {
            try await mouse(.leftMouseDragged, at: step, clickCount: 1)
        }
    }

    func mouseUp(at point: CGPoint) async throws {
        try await mouse(.leftMouseUp, at: point, clickCount: 1)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, clickCount: Int) async throws {
        let isPress = type == .leftMouseDown || type == .rightMouseDown
        let isRelease = type == .leftMouseUp || type == .rightMouseUp
        let isDrag = type == .leftMouseDragged || isRelease
        guard let window = (isDrag ? captureWindow : nil) ?? Self.window(at: point) else {
            throw DriverError.noWindow(point)
        }
        if NSApp.keyWindow == nil, window === lastKeyWindow {
            try await refocus(window)
        }
        let location = window.convertPoint(fromScreen: ScreenTopologyProvider.toAppKit(point))
        eventNumber += 1
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: modifiers, timestamp: nextTimestamp(),
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                clickCount: clickCount, pressure: isPress || type == .leftMouseDragged ? 1 : 0)
        else { throw DriverError.eventCreationFailed("mouse") }
        if isPress {
            captureWindow = window
        } else if isRelease {
            captureWindow = nil
        }
        lastPoint = point
        try await post(event)
    }

    // MARK: - 滚轮

    /// precise = 触控板 / 妙控鼠标（像素增量、hasPreciseScrollingDeltas）；否则为行式滚轮。
    /// momentum = 惯性阶段的事件（覆盖层应忽略）
    func scroll(deltaY: Int32, precise: Bool, momentum: Bool = false, at point: CGPoint) async throws {
        guard let window = Self.window(at: point),
            let event = E2EScrollEvent.make(
                deltaY: deltaY, precise: precise, momentum: momentum, at: point, in: window,
                flags: modifiers, timestamp: nextTimestamp())
        else { throw DriverError.eventCreationFailed("scroll") }
        try await post(event)
    }

    // MARK: - 键盘

    /// 按下并松开一个键；extraFlags 与当前按住的修饰键合并（例如 ⌘S 传 .command）
    func press(_ key: E2EKey, flags extraFlags: NSEvent.ModifierFlags = [], window: NSWindow? = nil) async throws {
        try await keyEvent(.keyDown, key, flags: extraFlags, window: window)
        try await keyEvent(.keyUp, key, flags: extraFlags, window: window)
    }

    func keyDown(_ key: E2EKey, window: NSWindow? = nil) async throws {
        try await keyEvent(.keyDown, key, flags: [], window: window)
    }

    func keyUp(_ key: E2EKey, window: NSWindow? = nil) async throws {
        try await keyEvent(.keyUp, key, flags: [], window: window)
    }

    /// 逐字符键入（ASCII）：大写字母带 ⇧
    func type(_ text: String) async throws {
        for character in text {
            let shifted = character.isUppercase ? NSEvent.ModifierFlags.shift : []
            try await press(.character(character), flags: shifted)
        }
    }

    /// 修饰键变化：每个变化的键发一次 flagsChanged（与真实键盘一致），事件的 modifierFlags 为变化后的全集。
    /// window 为 nil 时发给 key 窗口；传入其他窗口可模拟「松开时焦点已在别处」
    func setModifiers(_ target: NSEvent.ModifierFlags, window: NSWindow? = nil) async throws {
        let keys: [NSEvent.ModifierFlags] = [.shift, .option, .control, .command]
        for flag in keys where modifiers.contains(flag) != target.contains(flag) {
            modifiers.formSymmetricDifference(flag)
            // 没有 key 窗口（例如点击已结束会话）：这次变化落在别处，只更新驱动器的状态
            let target: NSWindow? = if let window { window } else { try await keyTarget() }
            guard let receiver = target else { continue }
            guard
                let event = NSEvent.keyEvent(
                    with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: nextTimestamp(),
                    windowNumber: receiver.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: E2EKey.modifierKeyCode(for: flag))
            else { throw DriverError.eventCreationFailed("flagsChanged") }
            try await post(event)
        }
    }

    /// 驱动器不再认为有键按住，但不发送任何事件：模拟「松开发生在别的应用里」
    func forgetModifiers() {
        modifiers = []
        spaceHeld = false
    }

    private func keyEvent(
        _ type: NSEvent.EventType, _ key: E2EKey, flags extraFlags: NSEvent.ModifierFlags, window: NSWindow?
    ) async throws {
        // 按下可能结束会话（↩ 完成）：松开照常发给按下时的窗口，与真实键盘一致
        let preferred = window ?? (type == .keyUp ? lastKeyDownWindow : nil)
        let target: NSWindow? = if let preferred { preferred } else { try await keyTarget() }
        guard let receiver = target else { throw DriverError.noKeyWindow }
        if type == .keyDown {
            lastKeyDownWindow = receiver
        }
        if key.keyCode == E2EKey.space.keyCode {
            spaceHeld = type == .keyDown
        }
        let flags = modifiers.union(extraFlags).union(key.intrinsicFlags)
        let characters = flags.contains(.shift) ? key.characters.uppercased() : key.characters
        guard
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: nextTimestamp(),
                windowNumber: receiver.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key.keyCode)
        else { throw DriverError.eventCreationFailed("key \(key)") }
        try await post(event)
    }

    /// 接收按键的窗口：本应用的 key 窗口。没有时（启动测试的前台应用偶尔会把 key 抢回去），
    /// 像用户点回覆盖层一样让上一个 key 窗口重新成为 key；仍没有则为 nil
    private func keyTarget() async throws -> NSWindow? {
        if let window = NSApp.keyWindow {
            return window
        }
        guard let window = lastKeyWindow, window.isVisible, window.canBecomeKey else { return nil }
        try await refocus(window)
        return window
    }

    /// 让窗口重新成为 key，并补发仍按住的修饰键与空格：覆盖层重新成为 key 时会按系统键盘状态重置，
    /// 而合成的按住状态不在系统状态里
    private func refocus(_ window: NSWindow) async throws {
        window.makeKey()
        refocusCount += 1
        if let held = [NSEvent.ModifierFlags.shift, .option, .control, .command].first(where: modifiers.contains),
            let event = NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: nextTimestamp(),
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: E2EKey.modifierKeyCode(for: held))
        {
            try await post(event)
        }
        if spaceHeld,
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: nextTimestamp(),
                windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                isARepeat: false, keyCode: E2EKey.space.keyCode)
        {
            try await post(event)
        }
    }

    // MARK: - 输入法（NSTextInputClient）

    /// 模拟输入法组字：在 key 窗口的第一响应者（文字编辑器的 NSTextView）上设置标记文本
    func setMarkedText(_ text: String) async throws {
        let client = try await textClient()
        client.setMarkedText(
            text, selectedRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        try await flush()
    }

    /// 模拟输入法提交：用最终文字替换标记文本
    func insertText(_ text: String) async throws {
        try await textClient().insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        try await flush()
    }

    private func textClient() async throws -> NSTextView {
        guard let textView = try await keyTarget()?.firstResponder as? NSTextView else { throw DriverError.noTextView }
        return textView
    }

    // MARK: - 投递

    func post(_ event: NSEvent) async throws {
        pending.insert(Self.nanoseconds(event.timestamp))
        NSApp.postEvent(event, atStart: false)
        try await flush()
    }

    /// 投递哨兵并等它出队：此前投递的事件都已派发完毕；随后再让出一次，等 SwiftUI 等下一轮运行循环的更新
    func flush() async throws {
        sentinelSerial += 1
        let serial = sentinelSerial
        guard
            let sentinel = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: Self.sentinelSubtype, data1: serial, data2: 0)
        else { throw DriverError.eventCreationFailed("sentinel") }
        NSApp.postEvent(sentinel, atStart: false)
        let arrived = await withCheckedContinuation { continuation in
            waiters[serial] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.queueTimeout)
                self?.resume(serial, arrived: false)
            }
        }
        guard arrived else { throw DriverError.queueTimedOut }
        await Task.yield()
    }

    private func resume(_ serial: Int, arrived: Bool) {
        waiters.removeValue(forKey: serial)?.resume(returning: arrived)
    }

    /// 严格递增、取整微秒的时间戳
    private func nextTimestamp() -> TimeInterval {
        let now = (ProcessInfo.processInfo.systemUptime * 1_000_000).rounded(.down) / 1_000_000
        lastTimestamp = max(now, lastTimestamp + 0.000_01)
        return lastTimestamp
    }

    private static func nanoseconds(_ timestamp: TimeInterval) -> Int64 {
        Int64((timestamp * 1_000_000_000).rounded())
    }

    // MARK: - 目标窗口

    /// 全局点下最前面的、接收鼠标的本应用窗口（覆盖层、贴图）
    static func window(at point: CGPoint) -> NSWindow? {
        let appKit = ScreenTopologyProvider.toAppKit(point)
        let numbers = NSWindow.windowNumbers(options: []) ?? []
        for number in numbers {
            guard let window = NSApp.window(withWindowNumber: number.intValue), window.isVisible,
                !window.ignoresMouseEvents, window.frame.contains(appKit)
            else { continue }
            return window
        }
        return nil
    }

    private static func interpolate(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(Int((distance / dragStep).rounded(.up)), 1)
        return (1...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }
}
#endif
