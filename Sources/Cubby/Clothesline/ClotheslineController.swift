import AppKit
import CubbyCore
import SwiftUI
import os

/// 晾衣绳（docs/UI-UPGRADE-PLAN.md 第 5 节）：屏幕顶部的透明非激活窗口。
/// 显示 / 收起由 ClotheslineReveal 决定（快捷键与菜单切换、指针停在屏幕顶边、从菜单栏往下拉、挂上新照片后短暂滑下），
/// 控制器每 1/20 秒轮询一次指针与左键状态：喂给状态机，并算出悬停的照片（窗口不是 key，不能依赖 onHover）
@MainActor
final class ClotheslineController {
    private static let pollInterval: TimeInterval = 1.0 / 20
    /// 滑下 / 收起的时长
    private static let slideDuration: TimeInterval = 0.22

    private let store: ClipStore
    private let settings: AppSettings
    private let window = ClotheslineWindow()
    let model = ClotheslineModel()
    private var reveal = ClotheslineReveal.hidden
    private var timer: Timer?
    /// 开着晾衣绳（start 之后、stop 之前）；绳上为空且没显示时暂停轮询
    private var isRunning = false
    /// 指针进入顶边（或开始往下拉）时算一次的「全屏空间」结果，离开后清掉（避免每帧枚举窗口）
    private var fullScreenAtEdge: Bool?
    private var screen: NSScreen?
    private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Clothesline")

    /// 单击照片：放大编辑（AppDelegate 接到截图覆盖层的历史图片编辑）
    var onEdit: ((ClipItem) -> Void)?
    #if DEBUG
    /// 截图走查：悬停状态由 debugShow 固定，不随指针变化
    var debugHoverLocked = false
    #endif

    init(store: ClipStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        window.contentView = FirstMouseHostingView(rootView: ClotheslineView(model: model))
        model.onCopy = { [weak self] item in self?.copy(item) }
        model.onEdit = { [weak self] item in self?.onEdit?(item) }
        model.onRemove = { [weak self] item in self?.takeDown(item) }
    }

    var isShown: Bool {
        model.isShown
    }

    // MARK: - 生命周期

    func start() {
        isRunning = true
        refresh()
    }

    /// 关闭晾衣绳：收起并停止轮询。绳上的条目仍受保护（重新开启时原样回来），refresh 同步保护集合
    func stop() {
        isRunning = false
        refresh()
        apply(shown: false)
    }

    /// 只在开着、且绳上有照片（或正显示 / 编辑中）时轮询指针
    private func updatePolling() {
        let needed = isRunning && (!model.entries.isEmpty || model.isShown || model.editingID != nil)
        if needed, timer == nil {
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = Self.pollInterval * 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !needed, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    /// 历史或绳子变了：绳上只保留仍在历史里的图片，重建照片
    func refresh() {
        let existing = Set(store.history.items.lazy.filter { $0.kind == .image }.map(\.id))
        let retained = settings.clothesline.retaining(existing)
        // 历史读取失败（不落盘）时历史是空的：只在显示上过滤，不回写设置，免得下次正常启动时绳上的照片丢了
        if store.canPersist, retained != settings.clothesline { settings.clothesline = retained }
        store.protectedIDs = Set(retained.itemIDs)
        let entries = retained.itemIDs.compactMap { id in
            store.item(id: id).map { ClotheslineModel.Entry(item: $0, imageURL: store.imageURL(for: $0)) }
        }
        model.update(entries: entries, width: (screen ?? NSScreen.main)?.frame.width ?? 0)
        updatePolling()
    }

    // MARK: - 挂上 / 取下

    func contains(_ item: ClipItem) -> Bool {
        settings.clothesline.contains(item.id)
    }

    /// 挂上（超出 12 张时取下最早的）或取下；挂上时绳子短暂滑下，新照片带一次衰减摆动
    func toggle(_ item: ClipItem) {
        guard item.kind == .image else { return }
        if contains(item) {
            takeDown(item)
        } else {
            hang(item)
        }
    }

    func hang(_ item: ClipItem) {
        settings.clothesline = settings.clothesline.hanging(item.id).line
        refresh()
        let now = ProcessInfo.processInfo.systemUptime
        model.markHung(item.id, at: now)
        reveal = reveal.peeking(now: now, conditions: conditions(checkingFullScreen: true))
        tick()
    }

    /// 放大编辑后「完成并晾回」：新条目挂在原位置，原图留在历史里
    func replace(_ oldID: UUID, with newID: UUID) {
        settings.clothesline = settings.clothesline.replacing(oldID, with: newID)
        refresh()
    }

    func takeDown(_ item: ClipItem) {
        settings.clothesline = settings.clothesline.removing(item.id)
        refresh()
    }

    // MARK: - 放大编辑

    /// 放大编辑期间：绳子保持显示、浮到截图覆盖层之上（设计图里绳子露在暗背景上方），原位置显示虚线空位；
    /// 不接收点击（编辑由覆盖层处理）
    func beginEditing(_ id: UUID) {
        model.editingID = id
        model.hoveredID = nil
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.ignoresMouseEvents = true
        apply(shown: true)
        updatePolling()
    }

    func endEditing() {
        model.editingID = nil
        window.level = ClotheslineWindow.restingLevel
        window.ignoresMouseEvents = false
        // 回到绳上后再停留片刻（指针不在绳上时按「挂上新照片」的时长收起）
        reveal = reveal.peeking(
            now: ProcessInfo.processInfo.systemUptime, conditions: conditions(checkingFullScreen: false))
        tick()
    }

    /// 快捷键 / 菜单：显示或收起
    func toggle() {
        reveal = reveal.toggled(
            now: ProcessInfo.processInfo.systemUptime, conditions: conditions(checkingFullScreen: true))
        tick()
    }

    /// 轮询用的条件：绳上为空或已显示时不判断全屏；进入顶边或往下拉（含刚按下的这一帧）时判断一次并缓存到离开。
    /// 往下拉期间还要看这次按下是否打开了菜单 / 弹出框，或是 ⌘ 拖动状态图标（这两种拖动都不算）
    private func edgeConditions(
        atTopEdge: Bool, sample: ClotheslineReveal.PointerSample, on screen: NSScreen
    ) -> ClotheslineReveal.Conditions {
        let pulling = reveal.tracksPull(sample)
        let watching = atTopEdge || pulling
        let base = conditions(checkingFullScreen: false)
        guard watching, !model.isShown, !model.entries.isEmpty else {
            if !watching { fullScreenAtEdge = nil }
            return base
        }
        let fullScreen = fullScreenAtEdge ?? conditions(checkingFullScreen: true).isFullScreenSpace
        fullScreenAtEdge = fullScreen
        let pressedOnItem =
            pulling
            && (NSEvent.modifierFlags.contains(.command)
                || MenuBarPopUp.isOpen(below: sample.location.x, on: screen, menuBarHeight: sample.menuBarHeight))
        return ClotheslineReveal.Conditions(
            isEnabled: base.isEnabled, isEmpty: base.isEmpty, isFullScreenSpace: fullScreen, dwell: base.dwell,
            revealsOnDwell: base.revealsOnDwell, isMenuOpen: pressedOnItem)
    }

    /// 外部条件。全屏空间的判断要列出所有窗口，只在需要时做（指针到了顶边、切换或挂上新照片时）
    private func conditions(checkingFullScreen: Bool) -> ClotheslineReveal.Conditions {
        let screen = screen(containing: NSEvent.mouseLocation)
        return ClotheslineReveal.Conditions(
            isEnabled: settings.clotheslineEnabled, isEmpty: model.entries.isEmpty,
            isFullScreenSpace: checkingFullScreen && screen.map(FullScreenSpace.isActive(on:)) == true,
            dwell: settings.clotheslineDwell, revealsOnDwell: settings.clotheslineRevealsOnDwell)
    }

    // MARK: - 双击复制

    private func copy(_ item: ClipItem) {
        do {
            try PasteboardWriter.write(item, imageURL: store.imageURL(for: item), to: .general)
            OwnPasteboardWrites.record(.general)
            store.promote(id: item.id)
            if let anchor = HUDToast.defaultAnchor() {
                HUDToast.show(String(localized: "Copied to clipboard", comment: "HUD after copying"), at: anchor)
            }
        } catch {
            logger.error("Failed to copy a clothesline photo: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    // MARK: - 轮询

    private func tick() {
        let pointer = NSEvent.mouseLocation
        guard let pointerScreen = screen(containing: pointer) else { return }
        if !model.isShown, pointerScreen != screen {
            screen = pointerScreen
            refresh()
        }
        // 显示期间以绳子所在的屏为准：指针移到另一块屏的顶边不算「在绳上」
        let current = model.isShown ? (screen ?? pointerScreen) : pointerScreen
        let frame = ClotheslineWindow.frame(on: screen ?? current, height: ClotheslineLayout.windowHeight)
        // 绳子区域向上延伸到屏幕顶边：从顶边滑下后指针还停在菜单栏上时不算离开
        let bottom = frame.maxY - model.layout.occupiedHeight
        let area = CGRect(x: frame.minX, y: bottom, width: frame.width, height: current.frame.maxY - bottom)
        let isPressed = NSEvent.pressedMouseButtons & 1 != 0
        let sample = ClotheslineReveal.PointerSample(
            location: pointer, screenTopY: current.frame.maxY, lineArea: area,
            now: ProcessInfo.processInfo.systemUptime, isPressed: isPressed,
            menuBarHeight: Self.menuBarHeight(on: current))
        let atTopEdge =
            NSMouseInRect(pointer, current.frame, false)
            && pointer.y >= current.frame.maxY - ClotheslineReveal.edgeBand
        // 放大编辑期间绳子一直显示，不受指针离开影响
        guard model.editingID == nil else { return }
        reveal = reveal.updated(
            with: sample, conditions: edgeConditions(atTopEdge: atTopEdge, sample: sample, on: current))
        apply(shown: reveal.isShown)
        updateHover(pointer: pointer, frame: frame)
    }

    private func updateHover(pointer: CGPoint, frame: CGRect) {
        #if DEBUG
        if debugHoverLocked { return }
        #endif
        guard model.isShown, model.editingID == nil else {
            if model.hoveredID != nil { model.hoveredID = nil }
            return
        }
        // 窗口坐标：原点在左上角
        let local = CGPoint(x: pointer.x - frame.minX, y: frame.maxY - pointer.y)
        let hovered = model.layout.photo(at: local)?.id
        if hovered != model.hoveredID { model.hoveredID = hovered }
    }

    /// 常驻菜单栏占的高度；自动隐藏或这块屏没有菜单栏时为 0（状态机只认最顶边，免得把窗口标题栏当成菜单栏）
    private static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        max(screen.frame.maxY - screen.visibleFrame.maxY, 0)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: - 滑下 / 收起

    private func apply(shown: Bool) {
        guard shown != model.isShown, let screen = screen ?? NSScreen.main else { return }
        model.isShown = shown
        let frame = ClotheslineWindow.frame(on: screen, height: ClotheslineLayout.windowHeight)
        // 藏在菜单栏后面：整个窗口在菜单栏下沿之上
        let hidden = frame.offsetBy(dx: 0, dy: frame.height)
        let reduceMotion = Motion.prefersReducedMotion
        if shown {
            window.setFrame(reduceMotion ? frame : hidden, display: false)
            window.alphaValue = reduceMotion ? 0 : 1
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = reduceMotion ? Motion.fade : Self.slideDuration
                context.timingFunction = CAMediaTimingFunction(name: shown ? .easeOut : .easeIn)
                if reduceMotion {
                    window.animator().alphaValue = shown ? 1 : 0
                } else {
                    window.animator().setFrame(shown ? frame : hidden, display: true)
                }
            },
            completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.model.isShown else { return }
                    self.window.orderOut(nil)
                    self.updatePolling()
                }
            })
    }
}

/// 当前空间是否被全屏应用占用（全屏应用的空间里不显示晾衣绳）：
/// 前台应用有一个与屏幕同大的普通层级窗口，且菜单栏不占可见区域
enum FullScreenSpace {
    static func isActive(on screen: NSScreen) -> Bool {
        guard screen.visibleFrame.maxY >= screen.frame.maxY,
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return false }
        let windows =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let size = screen.frame.size
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return bounds["Width"] == size.width && bounds["Height"] == size.height
        }
    }
}

/// 菜单栏下方是否挂着一个菜单 / 弹出框（按在菜单标题、状态图标、控制中心等模块上时会弹出）：
/// 高于普通窗口层级、顶边贴着菜单栏下沿、横向覆盖指针位置。只看这一小块，常驻的悬浮窗不会误判
enum MenuBarPopUp {
    /// 顶边离菜单栏下沿多远以内算「挂在菜单栏下」（pt）
    private static let attachSlop: CGFloat = 12

    static func isOpen(below x: CGFloat, on screen: NSScreen, menuBarHeight: CGFloat) -> Bool {
        // CGWindow 坐标原点在主屏左上角、y 向下
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return false }
        let barBottom = primaryTop - screen.frame.maxY + max(menuBarHeight, ClotheslineReveal.edgeBand)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int ?? 0) > 0,
                (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                let dict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: dict)
            else { return false }
            return abs(bounds.minY - barBottom) <= attachSlop && bounds.height > attachSlop
                && bounds.minX <= x && x <= bounds.maxX
        }
    }
}

#if DEBUG
extension ClotheslineController {
    /// 截图走查：显示绳子；可让第二张照片保持悬停状态（不必移动鼠标）
    func debugShow(hoveringSecond: Bool) {
        refresh()
        toggle()
        guard hoveringSecond, model.entries.count > 1 else { return }
        debugHoverLocked = true
        model.hoveredID = model.entries[1].id
    }
}
#endif
