import Carbon.HIToolbox
import Testing
@testable import CubbyCore

@Suite("HotKeyRegistry 快捷键登记表")
struct HotKeyRegistryTests {
    private let panel = HotKey.default
    private let screenshot = HotKey.screenshotDefault
    private let other = HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey), keyLabel: "K")

    @Test("空登记表：未暂停、没有要注册的动作")
    func empty() {
        let registry = HotKeyRegistry()
        #expect(!registry.isSuspended)
        #expect(registry.activeActions.isEmpty)
        #expect(registry.hotKey(for: .togglePanel) == nil)
    }

    @Test("登记后按 rawValue 顺序出现在待注册动作中")
    func registering() {
        let registry = HotKeyRegistry()
            .registering(screenshot, for: .screenshot)
            .registering(panel, for: .togglePanel)
        #expect(registry.activeActions == [.togglePanel, .screenshot])
        #expect(registry.hotKey(for: .screenshot) == screenshot)
    }

    @Test("同一动作再次登记会替换快捷键")
    func replacing() {
        let registry = HotKeyRegistry()
            .registering(panel, for: .togglePanel)
            .registering(other, for: .togglePanel)
        #expect(registry.hotKey(for: .togglePanel) == other)
        #expect(registry.activeActions == [.togglePanel])
    }

    @Test("移除后不再登记，也不再待注册")
    func removing() {
        let registry = HotKeyRegistry()
            .registering(panel, for: .togglePanel)
            .registering(screenshot, for: .screenshot)
            .removing(.screenshot)
        #expect(registry.hotKey(for: .screenshot) == nil)
        #expect(registry.activeActions == [.togglePanel])
    }

    @Test("暂停期间没有待注册动作，但登记保留")
    func suspending() {
        let registry = HotKeyRegistry().registering(panel, for: .togglePanel).suspended()
        #expect(registry.isSuspended)
        #expect(registry.activeActions.isEmpty)
        #expect(registry.hotKey(for: .togglePanel) == panel)
    }

    @Test("暂停按次数计数：两次暂停需要两次恢复")
    func nestedSuspension() {
        let twice = HotKeyRegistry().registering(panel, for: .togglePanel).suspended().suspended()
        #expect(twice.resumed().isSuspended)
        #expect(twice.resumed().activeActions.isEmpty)
        #expect(!twice.resumed().resumed().isSuspended)
        #expect(twice.resumed().resumed().activeActions == [.togglePanel])
    }

    @Test("未暂停时恢复不会变成负数")
    func resumeClampsAtZero() {
        let registry = HotKeyRegistry().resumed().resumed()
        #expect(!registry.isSuspended)
        #expect(registry.suspended().isSuspended)
        #expect(!registry.suspended().resumed().isSuspended)
    }

    @Test("暂停期间登记的快捷键在恢复后才待注册")
    func registeringWhileSuspended() {
        let suspended = HotKeyRegistry().suspended().registering(screenshot, for: .screenshot)
        #expect(suspended.activeActions.isEmpty)
        #expect(suspended.resumed().activeActions == [.screenshot])
    }

    @Test("原值不被修改（值语义）")
    func immutability() {
        let original = HotKeyRegistry().registering(panel, for: .togglePanel)
        _ = original.suspended().removing(.togglePanel)
        #expect(original.activeActions == [.togglePanel])
        #expect(!original.isSuspended)
    }

    @Test("热键 id 与动作互相映射；签名不符或未知 id 返回 nil")
    func idMapping() {
        for action in HotKeyAction.allCases {
            let id = HotKeyRegistry.hotKeyID(for: action)
            #expect(HotKeyRegistry.action(signature: HotKeyRegistry.signature, id: id) == action)
        }
        #expect(HotKeyRegistry.action(signature: 0x4142_4344, id: 1) == nil)
        #expect(HotKeyRegistry.action(signature: HotKeyRegistry.signature, id: 99) == nil)
        #expect(HotKeyRegistry.signature == 0x4355_4259)
    }
}
