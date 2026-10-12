import Foundation
import Testing
@testable import CubbyCore

@Suite("地址守护状态机")
struct AddressGuardTests {
    private let original = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    private let attacker = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
    private let attacker2 = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB"
    private let bitcoin = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    private let wallet = "com.example.wallet"
    private let source = SourceApp(bundleID: "com.example.wallet", name: "Wallet")
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    private func changed(
        _ text: String?, at seconds: TimeInterval, frontmost: String? = "com.example.wallet", source: SourceApp? = nil
    ) -> AddressGuard.Event {
        .pasteboardChanged(text: text, date: at(seconds), frontmostBundleID: frontmost, source: source)
    }

    private func eth(_ text: String) -> SensitiveValue {
        SensitiveValue(kind: .ethereum, value: text)
    }

    /// 已在 0 秒守护 original 的状态
    private func guarding(_ configuration: AddressGuard.Configuration = .init()) -> AddressGuard {
        AddressGuard(configuration: configuration).handling(changed(original, at: 0, source: source)).0
    }

    @Test("默认配置：全部类型、10 秒、没有输入监控")
    func defaults() {
        let state = AddressGuard()
        #expect(state.configuration.kinds == Set(SensitiveKind.allCases))
        #expect(state.configuration.window == 10)
        #expect(state.configuration.monitorsKeystrokes == false)
        #expect(state.guarded == nil)
        #expect(state.lastCopyKeystroke == nil)
    }

    @Test("复制敏感值后开始守护")
    func startsGuarding() {
        let (state, outcome) = AddressGuard().handling(changed(original, at: 0, source: source))
        let copy = AddressGuard.Copy(
            value: eth(original), date: start, frontmostBundleID: wallet, source: source, text: original)
        #expect(outcome == .guarding(copy))
        #expect(state.guarded == copy)
        #expect(state.lastCopyKeystroke == nil)
    }

    @Test("复制普通文本或没有文本时清除守护")
    func clearsOnOrdinaryText() {
        for text in ["hello", nil] {
            let (state, outcome) = guarding().handling(copyKeystrokeEvent(at: 1)).0.handling(changed(text, at: 2))
            #expect(outcome == .none)
            #expect(state.guarded == nil)
            #expect(state.lastCopyKeystroke == nil)
        }
    }

    private func copyKeystrokeEvent(at seconds: TimeInterval) -> AddressGuard.Event {
        .copyKeystroke(date: at(seconds))
    }

    @Test("时间窗内同类型、前台未变的另一个值判定为被替换；状态仍守护原值")
    func detectsTamper() {
        let before = guarding()
        let (state, outcome) = before.handling(changed(attacker, at: 3))
        let expected = AddressGuard.Tamper(
            original: before.guarded!, replacement: eth(attacker), date: at(3), frontmostBundleID: wallet,
            checkedKeystrokes: false, replacementText: attacker)
        #expect(outcome == .tampered(expected))
        #expect(expected.elapsed == 3)
        #expect(state.guarded == before.guarded)
    }

    @Test("时间窗边界：恰好等于窗口算，超过不算，时间倒流不算")
    func windowEdges() {
        #expect(isTamper(guarding().handling(changed(attacker, at: 10)).1))
        #expect(isTamper(guarding().handling(changed(attacker, at: 0)).1))
        #expect(isGuarding(guarding().handling(changed(attacker, at: 10.001)).1))
        #expect(isGuarding(guarding().handling(changed(attacker, at: -1)).1))
        let custom = AddressGuard.Configuration(window: 2)
        #expect(isGuarding(guarding(custom).handling(changed(attacker, at: 3)).1))
    }

    @Test("类型不同时不算被替换，改为守护新值")
    func kindMismatch() {
        let (state, outcome) = guarding().handling(changed(bitcoin, at: 1))
        #expect(isGuarding(outcome))
        #expect(state.guarded?.value == SensitiveValue(kind: .bitcoin, value: bitcoin))
    }

    @Test("前台应用变了不算被替换；都为 nil 视为相同")
    func frontmost() {
        #expect(isGuarding(guarding().handling(changed(attacker, at: 1, frontmost: "com.other")).1))
        #expect(isGuarding(guarding().handling(changed(attacker, at: 1, frontmost: nil)).1))
        let nilFront = AddressGuard().handling(changed(original, at: 0, frontmost: nil)).0
        #expect(isTamper(nilFront.handling(changed(attacker, at: 1, frontmost: nil)).1))
    }

    @Test("有输入监控：守护开始后按过 ⌘C 不算被替换，之前按的不影响")
    func keystrokes() {
        let config = AddressGuard.Configuration(monitorsKeystrokes: true)
        // 守护开始后按 ⌘C
        let pressed = guarding(config).handling(copyKeystrokeEvent(at: 1))
        #expect(pressed.1 == .none)
        #expect(pressed.0.lastCopyKeystroke == at(1))
        let (afterKey, outcome) = pressed.0.handling(changed(attacker, at: 2))
        #expect(isGuarding(outcome))
        #expect(afterKey.guarded?.value == eth(attacker))
        #expect(afterKey.lastCopyKeystroke == nil)

        // 恰好与复制同一时刻的按键也算用户复制
        #expect(isGuarding(guarding(config).handling(copyKeystrokeEvent(at: 0)).0.handling(changed(attacker, at: 1)).1))

        // 早于守护开始的按键（复制原值时的那次）不影响
        let early = guarding(config).handling(copyKeystrokeEvent(at: -0.5)).0
        if case .tampered(let tamper) = early.handling(changed(attacker, at: 2)).1 {
            #expect(tamper.checkedKeystrokes)
        } else {
            Issue.record("expected tamper")
        }
    }

    @Test("开始守护会清掉之前记录的按键")
    func guardingResetsKeystroke() {
        let config = AddressGuard.Configuration(monitorsKeystrokes: true)
        let state = AddressGuard(configuration: config).handling(copyKeystrokeEvent(at: -1)).0
        #expect(state.lastCopyKeystroke == at(-1))
        #expect(state.handling(changed(original, at: 0)).0.lastCopyKeystroke == nil)
    }

    @Test("没有输入监控时忽略按键")
    func keystrokesIgnoredWithoutMonitoring() {
        let state = guarding().handling(copyKeystrokeEvent(at: 1)).0
        if case .tampered(let tamper) = state.handling(changed(attacker, at: 2)).1 {
            #expect(tamper.checkedKeystrokes == false)
        } else {
            Issue.record("expected tamper")
        }
    }

    @Test("关闭的类型不守护")
    func disabledKinds() {
        let config = AddressGuard.Configuration(kinds: [.bitcoin])
        let (state, outcome) = AddressGuard(configuration: config).handling(changed(original, at: 0))
        #expect(outcome == .none)
        #expect(state.guarded == nil)
    }

    @Test("再次复制同一个值：刷新守护时间，不算被替换")
    func recopy() {
        let (state, outcome) = guarding().handling(changed(original, at: 8, frontmost: "com.other"))
        #expect(outcome == .none)
        #expect(
            state.guarded
                == AddressGuard.Copy(
                    value: eth(original), date: at(8), frontmostBundleID: wallet, source: source, text: original))
        // 刷新后时间窗从 8 秒重新算
        #expect(isTamper(state.handling(changed(attacker, at: 17)).1))
    }

    @Test("Cubby 自己写入敏感值时成为新的守护对象；写普通文本清除守护")
    func cubbyWrites() {
        let (state, outcome) = guarding().handling(
            .cubbyWrote(text: attacker, date: at(1), frontmostBundleID: "com.cubby"))
        let copy = AddressGuard.Copy(
            value: eth(attacker), date: at(1), frontmostBundleID: "com.cubby", source: nil, text: attacker)
        #expect(outcome == .guarding(copy))
        #expect(state.guarded == copy)

        let cleared = state.handling(.cubbyWrote(text: "hello", date: at(2), frontmostBundleID: nil))
        #expect(cleared.1 == .none)
        #expect(cleared.0.guarded == nil)
    }

    @Test("Cubby 写入后清掉记录的按键")
    func cubbyWriteResetsKeystroke() {
        let config = AddressGuard.Configuration(monitorsKeystrokes: true)
        let state = guarding(config).handling(copyKeystrokeEvent(at: 1)).0
        let written = state.handling(.cubbyWrote(text: original, date: at(2), frontmostBundleID: wallet)).0
        #expect(written.lastCopyKeystroke == nil)
    }

    @Test("「是我自己换的」：替换后的值成为守护对象")
    func acceptFlow() {
        let before = guarding(.init(monitorsKeystrokes: true))
        guard case .tampered(let tamper) = before.handling(changed(attacker, at: 2)).1 else {
            Issue.record("expected tamper")
            return
        }
        let (state, outcome) = before.handling(.acceptedReplacement(tamper))
        let copy = AddressGuard.Copy(
            value: eth(attacker), date: at(2), frontmostBundleID: wallet, source: nil, text: attacker)
        #expect(outcome == .guarding(copy))
        #expect(state.guarded == copy)
        #expect(state.lastCopyKeystroke == nil)
        // 之后再变成 attacker 不再报警，变成另一个才报
        #expect(state.handling(changed(attacker, at: 3)).1 == .none)
        #expect(isTamper(state.handling(changed(attacker2, at: 3)).1))
    }

    @Test("被替换后再换成第二个值，仍按原值判定为被替换")
    func secondReplacement() {
        let first = guarding().handling(changed(attacker, at: 1)).0
        guard case .tampered(let tamper) = first.handling(changed(attacker2, at: 2)).1 else {
            Issue.record("expected tamper")
            return
        }
        #expect(tamper.original.value == eth(original))
        #expect(tamper.replacement == eth(attacker2))
    }

    @Test("configured 只换配置，不动守护状态")
    func configured() {
        let state = guarding()
        let updated = state.configured(.init(kinds: [.bitcoin], window: 5, monitorsKeystrokes: true))
        #expect(updated.guarded == state.guarded)
        #expect(updated.configuration.window == 5)
        #expect(updated.configuration.kinds == [.bitcoin])
    }

    @Test("推荐配置：有输入监控 10 秒，没有时 1.5 秒")
    func recommended() {
        let kinds: Set<SensitiveKind> = [.ethereum]
        let monitored = AddressGuard.Configuration.recommended(kinds: kinds, monitorsKeystrokes: true)
        #expect(monitored == AddressGuard.Configuration(kinds: kinds, window: 10, monitorsKeystrokes: true))
        let plain = AddressGuard.Configuration.recommended(kinds: kinds, monitorsKeystrokes: false)
        #expect(plain == AddressGuard.Configuration(kinds: kinds, window: 1.5, monitorsKeystrokes: false))
        // 没有输入监控：1.5 秒内算替换，之后在同一个应用里复制另一个地址不算
        let state = guarding(plain)
        #expect(isTamper(state.handling(changed(attacker, at: 1.5)).1))
        #expect(!isTamper(state.handling(changed(attacker, at: 2)).1))
    }

    @Test("以太坊地址不分大小写：EIP-55 写法与全小写是同一个值，不算替换")
    func ethereumCaseInsensitive() {
        let (state, outcome) = guarding().handling(changed(original.lowercased(), at: 1))
        #expect(outcome == .none)
        #expect(state.guarded?.value == eth(original))
        #expect(state.guarded?.text == original.lowercased())
        #expect(eth(original).isSame(as: eth(original.uppercased().replacingOccurrences(of: "0X", with: "0x"))))
        #expect(!SensitiveValue(kind: .tron, value: "Ta").isSame(as: SensitiveValue(kind: .tron, value: "TA")))
        #expect(!eth(original).isSame(as: SensitiveValue(kind: .solana, value: original)))
    }

    @Test("原文保留首尾空白与分隔符，「恢复」写回原文；不知道原文时用规范化的值")
    func keepsRawText() {
        let card = " 4111 1111 1111 1111\n"
        let state = AddressGuard().handling(changed(card, at: 0)).0
        #expect(state.guarded?.value == SensitiveValue(kind: .bankCard, value: "4111111111111111"))
        #expect(state.guarded?.restorableText == card)
        let unknown = AddressGuard.Copy(value: eth(original), date: start, frontmostBundleID: nil, source: nil)
        #expect(unknown.restorableText == original)
    }

    private func isTamper(_ outcome: AddressGuard.Outcome) -> Bool {
        if case .tampered = outcome { return true }
        return false
    }

    private func isGuarding(_ outcome: AddressGuard.Outcome) -> Bool {
        if case .guarding = outcome { return true }
        return false
    }
}
