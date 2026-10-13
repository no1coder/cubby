import Testing
@testable import CubbyCore

@Suite("系统授权与签名绑定：判断授权是否因签名变化而失效")
struct SignedGrantTests {
    private static let developerID = "req:identifier x and certificate leaf[subject.OU] = T"
    private static let development = "req:identifier x and certificate leaf[subject.CN] = \"Apple Development\""
    private static let legacyTeam = "team:T"

    @Test("已授权：首次记下当前签名键")
    func grantedRecordsKey() {
        let result = SignedGrant.evaluate(
            isGranted: true, recorded: nil, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result == SignedGrantEvaluation(status: .granted, keyToRecord: Self.developerID))
    }

    @Test("已授权且记录未变：不重复写入")
    func grantedKeepsRecord() {
        let result = SignedGrant.evaluate(
            isGranted: true, recorded: Self.developerID, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result == SignedGrantEvaluation(status: .granted, keyToRecord: nil))
    }

    @Test("已授权但记录是旧格式：升级为当前格式")
    func grantedUpgradesLegacyRecord() {
        let result = SignedGrant.evaluate(
            isGranted: true, recorded: Self.legacyTeam, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result == SignedGrantEvaluation(status: .granted, keyToRecord: Self.developerID))
    }

    @Test("从未授权过：未授权")
    func neverGranted() {
        let result = SignedGrant.evaluate(
            isGranted: false, recorded: nil, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result.status == .notGranted)
        #expect(result.keyToRecord == nil)
    }

    @Test("签名未变却未授权（用户在系统设置里关掉了）：未授权而非失效")
    func revokedWithSameSignature() {
        let result = SignedGrant.evaluate(
            isGranted: false, recorded: Self.developerID, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result.status == .notGranted)
    }

    @Test("同一团队从 Apple Development 换成 Developer ID 签名：判定失效（旧实现只比较团队 ID，会漏判）")
    func certificateKindChangedIsStale() {
        let result = SignedGrant.evaluate(
            isGranted: false, recorded: Self.development, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result.status == .stale)
        #expect(result.keyToRecord == nil)
    }

    @Test("旧版本记下的团队键与当前团队一致：无法区分证书类型，保守判为未授权")
    func legacyRecordSameTeam() {
        let result = SignedGrant.evaluate(
            isGranted: false, recorded: Self.legacyTeam, currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result.status == .notGranted)
    }

    @Test("旧版本记下的是 ad-hoc 键：判定失效")
    func legacyAdHocRecordIsStale() {
        let result = SignedGrant.evaluate(
            isGranted: false, recorded: "adhoc:abc", currentKeys: [Self.developerID, Self.legacyTeam])
        #expect(result.status == .stale)
    }

    @Test("读不到当前签名：无从比较，判为未授权且不写记录")
    func unknownSignature() {
        #expect(
            SignedGrant.evaluate(isGranted: false, recorded: Self.developerID, currentKeys: [])
                == SignedGrantEvaluation(status: .notGranted, keyToRecord: nil))
        #expect(
            SignedGrant.evaluate(isGranted: true, recorded: nil, currentKeys: [])
                == SignedGrantEvaluation(status: .granted, keyToRecord: nil))
    }
}
