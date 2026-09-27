import Testing
@testable import CubbyCore

@Suite("TranslationSendDwell 云端发送前的停留")
struct TranslationSendDwellTests {
    @Test("本机引擎不停留")
    func onDeviceSendsAtOnce() {
        #expect(TranslationSendDwell.remaining(sendsTextOffDevice: false, isCached: false, elapsed: .zero) == .zero)
    }

    @Test("缓存命中不发送，也不停留")
    func cachedSendsAtOnce() {
        #expect(TranslationSendDwell.remaining(sendsTextOffDevice: true, isCached: true, elapsed: .zero) == .zero)
    }

    @Test("云端引擎等满总停留：卡片跟随选中项从零开始")
    func cloudWaitsTheWholeDwell() {
        #expect(
            TranslationSendDwell.remaining(sendsTextOffDevice: true, isCached: false, elapsed: .zero)
                == TranslationSendDwell.cloud)
    }

    @Test("按住 ⌥ 已等的 300 ms 计入总停留：还要再等 300 ms")
    func holdCountsTowardsTheDwell() {
        let remaining = TranslationSendDwell.remaining(
            sendsTextOffDevice: true, isCached: false, elapsed: .milliseconds(300))
        #expect(remaining == .milliseconds(300))
    }

    @Test("已等够或超过总停留时立即发送，不会是负数")
    func neverNegative() {
        #expect(
            TranslationSendDwell.remaining(sendsTextOffDevice: true, isCached: false, elapsed: .seconds(2)) == .zero)
        #expect(
            TranslationSendDwell.remaining(
                sendsTextOffDevice: true, isCached: false, elapsed: .zero, total: .milliseconds(100))
                == .milliseconds(100))
    }
}
