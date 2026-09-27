import Foundation
import Testing
@testable import CubbyCore

/// 用注入的模拟迁移链验证扩展方式：日后追加 v2 等步骤时，
/// 链条按顺序逐级执行、版本号由链统一写入、任一步出错都报告 malformed
@Suite("HistoryMigrator 迁移链扩展")
struct HistoryMigrationChainTests {
    private struct SimulatedStepError: Error {}

    private static func item(_ text: String) -> String {
        #"{"id":"8A6F2C1E-0B3D-4E5F-9A7B-1C2D3E4F5A6B","kind":"text","payload":{"text":{"_0":"\#(text)"}},"#
            + #""createdAt":0,"isFavorite":false,"contentHash":"text:\#(text)"}"#
    }

    /// 模拟的两步链（目标版本 2）：
    /// - v0 → v1：旧键 clips 改名为 items
    /// - v1 → v2：所有条目标记为收藏；要求输入已带 schemaVersion 1，以证明上一步完成后才执行且版本号已逐级写入
    private static let simulatedSteps: [HistoryMigrator.Step] = [
        { object in
            let clips = object["clips"] ?? [Any]()
            return object.filter { $0.key != "clips" }.merging(["items": clips]) { _, new in new }
        },
        { object in
            guard object["schemaVersion"] as? Int == 1, let items = object["items"] as? [[String: Any]] else {
                throw SimulatedStepError()
            }
            let favorited = items.map { $0.merging(["isFavorite": true]) { _, new in new } }
            return object.merging(["items": favorited]) { _, new in new }
        },
    ]

    private func migrate(_ json: String, steps: [HistoryMigrator.Step] = simulatedSteps) throws
        -> HistoryMigrator.Outcome
    {
        try HistoryMigrator.migrate(Data(json.utf8), steps: steps)
    }

    @Test("真实迁移链的长度即当前版本号")
    func realChainDefinesCurrentVersion() {
        #expect(HistoryMigrator.steps.count == HistoryMigrator.currentVersion)
    }

    @Test("v0 依次经过两步到达 v2")
    func v0RunsWholeChain() throws {
        let outcome = try migrate(#"{"clips":[\#(Self.item("a")),\#(Self.item("b"))]}"#)
        #expect(outcome.sourceVersion == 0)
        #expect(outcome.history.items.map(\.text) == ["a", "b"])
        #expect(outcome.history.items.map(\.isFavorite) == [true, true])
    }

    @Test("v1 只执行最后一步")
    func v1RunsLastStepOnly() throws {
        let outcome = try migrate(#"{"schemaVersion":1,"items":[\#(Self.item("a"))]}"#)
        #expect(outcome.sourceVersion == 1)
        #expect(outcome.history.items.map(\.isFavorite) == [true])
    }

    @Test("已是目标版本时不执行任何步骤")
    func targetVersionSkipsSteps() throws {
        let outcome = try migrate(#"{"schemaVersion":2,"items":[\#(Self.item("a"))]}"#)
        #expect(outcome.sourceVersion == 2)
        #expect(outcome.history.items.map(\.isFavorite) == [false])
    }

    @Test("高于目标版本时拒绝")
    func beyondTargetIsRejected() {
        #expect(throws: HistoryMigrationError.unsupportedVersion(found: 3)) {
            try migrate(#"{"schemaVersion":3,"items":[]}"#)
        }
    }

    @Test("某一步抛错时报告 malformed")
    func throwingStepIsMalformed() {
        let steps: [HistoryMigrator.Step] = [{ _ in throw SimulatedStepError() }]
        #expect(throws: HistoryMigrationError.malformed) {
            try migrate(#"{"items":[]}"#, steps: steps)
        }
    }

    @Test("某一步产出无法序列化为 JSON 的值时报告 malformed")
    func invalidJSONObjectIsMalformed() {
        let steps: [HistoryMigrator.Step] = [{ $0.merging(["items": Date()]) { _, new in new } }]
        #expect(throws: HistoryMigrationError.malformed) {
            try migrate(#"{"items":[]}"#, steps: steps)
        }
    }

    @Test("迁移产物不符合当前结构时报告 malformed")
    func undecodableResultIsMalformed() {
        let steps: [HistoryMigrator.Step] = [{ $0.merging(["items": "oops"]) { _, new in new } }]
        #expect(throws: HistoryMigrationError.malformed) {
            try migrate(#"{"items":[]}"#, steps: steps)
        }
    }
}
