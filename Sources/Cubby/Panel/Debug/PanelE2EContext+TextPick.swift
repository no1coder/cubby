#if DEBUG
import AppKit
import CubbyCore

/// 拆词脚本的辅助（docs/TEXT-PICK-DESIGN.md §4）：找到详情区里的自绘词块区、按文字取块、点 / 拖词块、读右键菜单
@MainActor
extension PanelE2EContext {
    var pick: TextPickController {
        viewModel.textPick
    }

    var pickTokens: [TextPickToken] {
        pick.document?.tokens ?? []
    }

    /// 等分词完成（长文本在后台分词）
    func waitForPickDocument() async throws {
        try await wait("the pick-words document") { self.pick.document != nil }
        try await settle()
    }

    /// 文字为 text 的第 occurrence 块（从 0 起）
    func tokenIndex(_ text: String, occurrence: Int = 0) throws -> Int {
        let matches = pickTokens.indices.filter { pickTokens[$0].text == text }
        guard matches.indices.contains(occurrence) else { throw PanelE2EError.missingAnchor("token \(text)") }
        return matches[occurrence]
    }

    /// 详情区里的词块区
    var pickCanvas: TextPickCanvasView? {
        Self.firstCanvas(in: detailWindow.contentView)
    }

    private static func firstCanvas(in view: NSView?) -> TextPickCanvasView? {
        guard let view else { return nil }
        if let canvas = view as? TextPickCanvasView { return canvas }
        return view.subviews.lazy.compactMap { firstCanvas(in: $0) }.first
    }

    /// 某块中心的全局位置（先滚到可见）
    func tokenPoint(_ index: Int) async throws -> CGPoint {
        guard let canvas = pickCanvas, let point = canvas.debugScreenPoint(ofToken: index) else {
            throw PanelE2EError.missingAnchor("token #\(index)")
        }
        try await settle(.milliseconds(60))
        return ScreenTopologyProvider.toGlobal(point)
    }

    /// 点一块；flags 为点击时按住的修饰键（⇧单击）
    func clickToken(_ index: Int, flags: NSEvent.ModifierFlags = []) async throws {
        let point = try await tokenPoint(index)
        if !flags.isEmpty { try await driver.setModifiers(flags) }
        try await driver.click(at: point)
        if !flags.isEmpty { try await driver.setModifiers([]) }
        try await settle()
    }

    /// 从 from 块按下，经过 through 各块（往回拖也可以），在最后一块松开
    func dragTokens(from start: Int, through targets: [Int]) async throws {
        let first = try await tokenPoint(start)
        var points = [first]
        for target in targets {
            points.append(try await tokenPoint(target))
        }
        try await driver.drag(through: points)
        try await settle()
    }

    /// 列表里某条卡片的中心（先选中它，让列表滚到可见）
    func cardPoint(_ key: String) async throws -> CGPoint {
        try select(key)
        try await settle(.milliseconds(250))
        return try point(of: "list.card.\(PanelE2EFixtures.id(key))")
    }

    // MARK: - 右键菜单

    /// 卡片菜单里某一项的快照
    struct MenuItemSnapshot {
        /// 菜单全部项的标题（排查用）
        let titles: [String]
        /// nil 表示菜单里没有这一项
        let isEnabled: Bool?
        let keyEquivalent: String
        let modifiers: NSEvent.ModifierFlags
    }

    /// 卡片的右键菜单：向卡片下方的视图要它右键时会弹出的菜单（`menu(for:)`，SwiftUI 的 contextMenu 由此提供），
    /// 记下 title 这一项；choose 为 true 且可用时执行它。合成的右键事件弹不出 SwiftUI 菜单（实测），
    /// 这里不走菜单的模态追踪，脚本也就不会卡在打开的菜单上
    /// - Parameter selectingFirst: 先选中这张卡（让列表滚到它）；为 false 时卡片须已在可见区域，
    ///   用来确认菜单作用于右键的那张卡而不是选中项
    func contextMenu(
        on key: String, item title: String, choose: Bool, selectingFirst: Bool = true
    ) async throws -> MenuItemSnapshot? {
        let center =
            selectingFirst ? try await cardPoint(key) : try point(of: "list.card.\(PanelE2EFixtures.id(key))")
        let window = panelWindow
        let location = window.convertPoint(fromScreen: ScreenTopologyProvider.toAppKit(center))
        guard
            let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1),
            let menu = Self.contextMenu(in: window, at: location, for: event)
        else { return nil }
        menu.update()
        let index = menu.items.firstIndex { $0.title == title }
        let item = index.map { menu.items[$0] }
        let snapshot = MenuItemSnapshot(
            titles: menu.items.map(\.title), isEnabled: item?.isEnabled, keyEquivalent: item?.keyEquivalent ?? "",
            modifiers: item?.keyEquivalentModifierMask ?? [])
        if choose, let index, item?.isEnabled == true {
            menu.performActionForItem(at: index)
        }
        try await settle()
        return snapshot
    }

    /// 从命中的视图往上找第一个提供右键菜单的视图
    private static func contextMenu(in window: NSWindow, at location: NSPoint, for event: NSEvent) -> NSMenu? {
        guard let content = window.contentView else { return nil }
        var view = content.hitTest(content.convert(location, from: nil))
        while let current = view {
            if let menu = current.menu(for: event) { return menu }
            view = current.superview
        }
        return nil
    }
}
#endif
