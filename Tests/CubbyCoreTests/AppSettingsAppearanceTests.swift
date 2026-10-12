import AppKit
import Foundation
import Testing
@testable import CubbyCore

/// 深浅色外观（docs/UI-UPGRADE-PLAN.md 第 2 节）：默认跟随系统，可固定浅色 / 深色
@Suite("AppAppearance 外观设置")
@MainActor
struct AppSettingsAppearanceTests {
    @Test("选项顺序：跟随系统、浅色、深色")
    func cases() {
        #expect(AppAppearance.allCases == [.system, .light, .dark])
        #expect(Set(AppAppearance.allCases.map(\.displayName)).count == 3)
    }

    @Test(
        "对应的系统外观：跟随系统为 nil（不覆盖），浅色为 aqua，深色为 darkAqua",
        arguments: [
            (AppAppearance.system, NSAppearance.Name?.none),
            (.light, .aqua),
            (.dark, .darkAqua),
        ])
    func appearanceName(_ appearance: AppAppearance, _ name: NSAppearance.Name?) {
        #expect(appearance.appearanceName == name)
    }

    @Test("从未设置时跟随系统")
    func defaultsToSystem() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).appearance == .system)
        }
    }

    @Test("每个选项都以原始值存储并可被新实例读回", arguments: AppAppearance.allCases)
    func roundTrip(_ appearance: AppAppearance) {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).appearance = appearance
            #expect(defaults.string(forKey: "appearance") == appearance.rawValue)
            #expect(AppSettings(defaults: defaults).appearance == appearance)
        }
    }

    @Test("存储值非法时回退为跟随系统", arguments: ["", "sepia", "Dark"])
    func invalidFallsBack(_ stored: String) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: "appearance")
            #expect(AppSettings(defaults: defaults).appearance == .system)
        }
    }

    @Test("存储值类型不对时回退为跟随系统")
    func wrongTypeFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set(2, forKey: "appearance")
            #expect(AppSettings(defaults: defaults).appearance == .system)
        }
    }
}
