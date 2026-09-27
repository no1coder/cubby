import Foundation
import Testing

/// 每个测试使用独立的 UserDefaults 域，结束时删除
@MainActor
func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "cubby-test-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建独立的 UserDefaults")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
