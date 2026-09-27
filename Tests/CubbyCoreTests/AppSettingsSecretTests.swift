import Foundation
import Testing
@testable import CubbyCore

@Suite("AppSettings 密钥过滤 ignoresSecrets / shouldRecord")
@MainActor
struct AppSettingsSecretTests {
    private let secret = "token: " + FakeSecrets.github()
    private let ordinary = "今天的会议纪要"

    private func files() -> ClipContent {
        .files([URL(fileURLWithPath: "/tmp/" + FakeSecrets.github())])
    }

    // MARK: - ignoresSecrets 持久化

    @Test("ignoresSecrets 默认开启")
    func defaultsToTrue() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings(defaults: defaults).ignoresSecrets)
        }
    }

    @Test("关闭后新实例读回关闭，再开启后读回开启")
    func persists() {
        withIsolatedDefaults { defaults in
            AppSettings(defaults: defaults).ignoresSecrets = false
            #expect(!AppSettings(defaults: defaults).ignoresSecrets)
            #expect(defaults.object(forKey: "ignoresSecrets") as? Bool == false)

            AppSettings(defaults: defaults).ignoresSecrets = true
            #expect(AppSettings(defaults: defaults).ignoresSecrets)
        }
    }

    @Test("存储值类型非法时回退为开启（安全默认）")
    func invalidStoredValueFallsBackToTrue() {
        withIsolatedDefaults { defaults in
            defaults.set("no", forKey: "ignoresSecrets")
            #expect(AppSettings(defaults: defaults).ignoresSecrets)
        }
    }

    // MARK: - shouldRecord

    @Test("开启时：含密钥的文本与富文本不记录")
    func rejectsSecretText() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(!settings.shouldRecord(.text(secret)))
            #expect(!settings.shouldRecord(.richText(secret, formats: ["public.html": Data("<p>x</p>".utf8)])))
        }
    }

    @Test(
        "开启时：各类密钥的纯文本都不记录",
        arguments: [
            FakeSecrets.pem("RSA PRIVATE"), FakeSecrets.aws(), FakeSecrets.githubPAT(), FakeSecrets.openAI(),
            FakeSecrets.stripe(), FakeSecrets.slack(), FakeSecrets.google(), FakeSecrets.jwt(),
        ])
    func rejectsEachSecretKind(_ value: String) {
        withIsolatedDefaults { defaults in
            #expect(!AppSettings(defaults: defaults).shouldRecord(.text(value)))
        }
    }

    @Test("开启时：普通文本与富文本照常记录")
    func acceptsOrdinaryText() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.shouldRecord(.text(ordinary)))
            #expect(settings.shouldRecord(.richText(ordinary, formats: Fixtures.richFormats(for: ordinary))))
        }
    }

    @Test("开启时：图片与文件恒记录（即使文件名形似密钥）")
    func imagesAndFilesAlwaysRecorded() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.ignoresSecrets)
            #expect(settings.shouldRecord(.image(png: Data(secret.utf8), width: 1, height: 1)))
            #expect(settings.shouldRecord(files()))
        }
    }

    @Test("关闭时：任何内容都记录，包括密钥")
    func disabledRecordsEverything() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.ignoresSecrets = false
            #expect(settings.shouldRecord(.text(secret)))
            #expect(settings.shouldRecord(.richText(secret, formats: [:])))
            #expect(settings.shouldRecord(.text(ordinary)))
            #expect(settings.shouldRecord(.image(png: Data(), width: 0, height: 0)))
            #expect(settings.shouldRecord(files()))
        }
    }

    @Test(
        "剪贴板采集结果：内容按原规则判断，未转码的图片与 .image 同一规则",
        arguments: [true, false])
    func captureFollowsContentRules(ignoresSecrets: Bool) {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.ignoresSecrets = ignoresSecrets
            #expect(settings.shouldRecord(PasteboardCapture.content(.text(secret))) == !ignoresSecrets)
            #expect(settings.shouldRecord(PasteboardCapture.content(.text(ordinary))))
            let raw = PasteboardCapture.rawImage(RawImage(data: Data(secret.utf8)))
            #expect(settings.shouldRecord(raw) == settings.shouldRecord(.image(png: Data(), width: 0, height: 0)))
            #expect(settings.shouldRecord(raw))
        }
    }

    @Test("shouldRecord 与 shouldCapture 相互独立")
    func independentFromCapture() {
        withIsolatedDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.isPaused = true
            #expect(!settings.shouldCapture(from: nil))
            #expect(settings.shouldRecord(.text(ordinary)))
        }
    }
}
