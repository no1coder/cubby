import AppKit
import Testing
@testable import CubbyCore

/// 可变的权限状态（模拟用户在系统询问框中作答后状态改变）
@MainActor
private final class StatusBox {
    var value: PasteboardPermissionStatus
    private(set) var openSettingsCount = 0

    init(_ value: PasteboardPermissionStatus) {
        self.value = value
    }

    func openSettings() {
        openSettingsCount += 1
    }
}

/// 假的「读取剪贴板」：记录调用次数，读取时可模拟用户作答
private actor FakePromptTrigger: PasteboardPromptTrigger {
    private let hasContent: Bool
    private let onRead: @Sendable @MainActor () -> Void
    private(set) var readCount = 0

    init(hasContent: Bool, onRead: @escaping @Sendable @MainActor () -> Void = {}) {
        self.hasContent = hasContent
        self.onRead = onRead
    }

    func readOnceAndDiscard() async -> Bool {
        readCount += 1
        await onRead()
        return hasContent
    }
}

@MainActor
@Suite("剪贴板权限按钮逻辑")
struct PasteboardAccessRequestTests {
    private func makeRequest(_ box: StatusBox, trigger: FakePromptTrigger) -> PasteboardAccessRequest {
        PasteboardAccessRequest(
            status: { box.value },
            trigger: trigger,
            openSettings: { box.openSettings() }
        )
    }

    @Test("已允许：什么也不做")
    func alreadyAllowed() async {
        let box = StatusBox(.allowed)
        let trigger = FakePromptTrigger(hasContent: true)
        let outcome = await makeRequest(box, trigger: trigger).perform()
        #expect(outcome == .alreadyAllowed)
        #expect(await trigger.readCount == 0)
        #expect(box.openSettingsCount == 0)
    }

    @Test("询问过（询问 / 拒绝）：只打开系统设置，不再读取剪贴板", arguments: [PasteboardPermissionStatus.ask, .denied])
    func opensSettingsAfterAsking(status: PasteboardPermissionStatus) async {
        let box = StatusBox(status)
        let trigger = FakePromptTrigger(hasContent: true)
        let outcome = await makeRequest(box, trigger: trigger).perform()
        #expect(outcome == .openedSettings)
        #expect(await trigger.readCount == 0)
        #expect(box.openSettingsCount == 1)
    }

    @Test("尚未询问过：读取一次剪贴板触发系统询问，作答后返回新状态", arguments: [PasteboardPermissionStatus.allowed, .ask])
    func grantsAccessByReadingOnce(answer: PasteboardPermissionStatus) async {
        let box = StatusBox(.notDetermined)
        let trigger = FakePromptTrigger(hasContent: true) { box.value = answer }
        let outcome = await makeRequest(box, trigger: trigger).perform()
        #expect(outcome == .changed(to: answer))
        #expect(await trigger.readCount == 1)
        #expect(box.openSettingsCount == 0)
    }

    @Test("读取了内容但状态没变：不打开系统设置（避免盖住系统询问框）")
    func unchangedAfterReading() async {
        let box = StatusBox(.notDetermined)
        let trigger = FakePromptTrigger(hasContent: true)
        let outcome = await makeRequest(box, trigger: trigger).perform()
        #expect(outcome == .unchanged)
        #expect(await trigger.readCount == 1)
        #expect(box.openSettingsCount == 0)
    }

    @Test("剪贴板为空：系统无从询问，提示用户先复制点内容")
    func nothingToRead() async {
        let box = StatusBox(.notDetermined)
        let trigger = FakePromptTrigger(hasContent: false)
        let outcome = await makeRequest(box, trigger: trigger).perform()
        #expect(outcome == .nothingToRead)
        #expect(box.openSettingsCount == 0)
    }

    @Test("状态变化优先于「没有可读内容」")
    func changedWinsOverNothingToRead() async {
        let box = StatusBox(.notDetermined)
        let trigger = FakePromptTrigger(hasContent: false) { box.value = .ask }
        let outcome = await makeRequest(box, trigger: trigger).perform()
        #expect(outcome == .changed(to: .ask))
    }
}

@Suite("读取系统剪贴板以触发询问")
struct SystemPasteboardPromptTriggerTests {
    @Test("优先选择体积小的类型（纯文本、链接），不去读整张图片")
    func prefersLightweightTypes() {
        let types: [NSPasteboard.PasteboardType] = [.tiff, .png, .string]
        #expect(SystemPasteboardPromptTrigger.probeType(in: types) == .string)
        #expect(SystemPasteboardPromptTrigger.probeType(in: [.tiff, .URL]) == .URL)
        #expect(SystemPasteboardPromptTrigger.probeType(in: [.pdf, .fileURL, .rtf]) == .fileURL)
    }

    @Test("没有偏好的类型时读取第一个类型；没有类型时不读取")
    func fallsBackToFirstType() {
        #expect(SystemPasteboardPromptTrigger.probeType(in: [.tiff, .png]) == .tiff)
        #expect(SystemPasteboardPromptTrigger.probeType(in: []) == nil)
    }

    @Test("空剪贴板：不读取")
    func emptyPasteboard() {
        withTemporaryPasteboard { pasteboard in
            #expect(!SystemPasteboardPromptTrigger.readOnce(from: pasteboard))
        }
    }

    @Test("有内容：读取一次后丢弃，剪贴板保持原样")
    func readsWithoutChangingPasteboard() {
        withTemporaryPasteboard { pasteboard in
            pasteboard.setString("hello", forType: .string)
            let changeCount = pasteboard.changeCount
            #expect(SystemPasteboardPromptTrigger.readOnce(from: pasteboard))
            #expect(pasteboard.changeCount == changeCount)
            #expect(pasteboard.string(forType: .string) == "hello")
        }
    }

    @Test(
        "机密、临时内容与 Cubby 自己写入的内容：不读取",
        arguments: [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            PasteboardReader.markerType.rawValue,
        ]
    )
    func skipsPrivateContent(marker: String) {
        withTemporaryPasteboard { pasteboard in
            pasteboard.declareTypes([.string, .init(marker)], owner: nil)
            pasteboard.setString("secret", forType: .string)
            pasteboard.setData(Data(), forType: .init(marker))
            #expect(!SystemPasteboardPromptTrigger.readOnce(from: pasteboard))
        }
    }

    @Test("异步读取指定名称的剪贴板（后台线程）")
    func readsNamedPasteboardAsynchronously() async {
        let name = NSPasteboard.Name("cubby-test-\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(await SystemPasteboardPromptTrigger(pasteboardName: name).readOnceAndDiscard() == false)
        pasteboard.setString("hello", forType: .string)
        #expect(await SystemPasteboardPromptTrigger(pasteboardName: name).readOnceAndDiscard())
    }
}
