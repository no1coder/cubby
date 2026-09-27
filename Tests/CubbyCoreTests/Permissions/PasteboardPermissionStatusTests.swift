import AppKit
import Testing
@testable import CubbyCore

@Suite("剪贴板权限状态与按钮动作")
struct PasteboardPermissionStatusTests {
    @Test(
        "按钮动作：尚未询问过时由 App 触发系统询问，询问过则只能去系统设置，已允许时没有按钮",
        arguments: [
            (PasteboardPermissionStatus.allowed, PermissionButtonAction?.none),
            (.notDetermined, .grantAccess),
            (.ask, .openSystemSettings),
            (.denied, .openSystemSettings),
        ]
    )
    func buttonAction(status: PasteboardPermissionStatus, expected: PermissionButtonAction?) {
        #expect(status.buttonAction == expected)
    }

    @Test(
        "只有询问过但未设为允许时才需要提醒",
        arguments: [
            (PasteboardPermissionStatus.allowed, false),
            (.notDetermined, false),
            (.ask, true),
            (.denied, true),
        ]
    )
    func needsAttention(status: PasteboardPermissionStatus, expected: Bool) {
        #expect(status.needsAttention == expected)
    }

    @Test("原始值保持稳定（诊断信息与日志依赖这些值）")
    func rawValuesAreStable() {
        #expect(PasteboardPermissionStatus.allCases.map(\.rawValue) == ["allowed", "notDetermined", "ask", "denied"])
    }

    @Test("按钮动作的原始值保持稳定（日志依赖）")
    func buttonActionRawValues() {
        #expect(PermissionButtonAction.allCases.map(\.rawValue) == ["grantAccess", "openSystemSettings"])
    }

    @Test("NSPasteboard.AccessBehavior 与状态一一对应")
    func mapsAccessBehavior() throws {
        guard #available(macOS 15.4, *) else {
            // 旧系统上没有 accessBehavior，映射不适用
            return
        }
        #expect(PasteboardPermissionStatus(NSPasteboard.AccessBehavior.alwaysAllow) == .allowed)
        #expect(PasteboardPermissionStatus(NSPasteboard.AccessBehavior.default) == .notDetermined)
        #expect(PasteboardPermissionStatus(NSPasteboard.AccessBehavior.ask) == .ask)
        #expect(PasteboardPermissionStatus(NSPasteboard.AccessBehavior.alwaysDeny) == .denied)
    }
}
