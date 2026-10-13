import AppKit
import CubbyCore

/// 某项系统隐私授权的签名记录：每次确认授权有效时记下签名键，据此判断授权是否因签名变化而失效（见 SignedGrant）
@MainActor
struct SignedGrantRecord {
    /// UserDefaults 键；沿用已发布版本使用的键名，升级后无需迁移
    let defaultsKey: String
    /// tccutil 使用的服务名（Accessibility、ScreenCapture）
    let tccService: String

    private static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.no1coder.Cubby"

    /// 重置本应用该项授权的终端命令（只复制给用户执行，应用不代为执行）
    var resetCommand: String {
        "tccutil reset \(tccService) \(Self.bundleID)"
    }

    func status(isGranted: Bool) -> SignedGrantStatus {
        let defaults = UserDefaults.standard
        let result = SignedGrant.evaluate(
            isGranted: isGranted,
            recorded: defaults.string(forKey: defaultsKey),
            currentKeys: SigningInfo.launched?.authorizationKeys ?? []
        )
        if let key = result.keyToRecord {
            defaults.set(key, forKey: defaultsKey)
        }
        return result.status
    }

    /// 复制重置命令到系统剪贴板，并带上自身写入标记，避免被记录进历史
    func copyResetCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resetCommand, forType: .string)
        pasteboard.setData(Data(), forType: PasteboardReader.markerType)
        OwnPasteboardWrites.record(pasteboard)
    }
}
