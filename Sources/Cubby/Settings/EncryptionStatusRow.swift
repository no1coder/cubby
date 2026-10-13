import AppKit
import CubbyCore
import SwiftUI

/// 设置 › 历史的「加密」一行（docs/HISTORY-ENCRYPTION-DESIGN.md §4）：正常时只是一行绿色「已开启」；
/// 迁移中显示进度；已锁定、找不到旧密钥时变橙色并给出按钮
struct EncryptionStatusRow: View {
    let vault: VaultCoordinator

    private static let progressWidth: CGFloat = 150

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Text("Encryption", comment: "Settings › History: row title for history encryption")
            subtitle
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch vault.status {
        case .preparing, .ready:
            if vault.migrationFailed {
                Text(EncryptionCopy.migrationFailed).foregroundStyle(.orange)
            } else {
                Text(EncryptionCopy.readySubtitle)
            }
        case .migrating:
            Text(EncryptionCopy.migratingSubtitle)
        case .locked:
            Text(EncryptionCopy.lockedSubtitle).foregroundStyle(.orange)
        case .resetAfterMissingKey:
            Text(EncryptionCopy.resetSubtitle).foregroundStyle(.orange)
        case .readOnly(let reason):
            Text(reason.warning.title).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch vault.status {
        case .preparing:
            ProgressView().controlSize(.small)
        case .migrating(let done, let total):
            HStack(spacing: 8) {
                ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
                    .frame(width: Self.progressWidth)
                Text(verbatim: "\(done) / \(total)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label {
                Text("On", comment: "Settings › History: history encryption is on")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .locked:
            Button(EncryptionCopy.tryAgain) { vault.retryUnlock() }
        case .resetAfterMissingKey(let folder):
            Button(EncryptionCopy.showInFinder) { ItemOpener.revealInFinder([folder.path]) }
        case .readOnly(.unreadable):
            Button(EncryptionCopy.tryAgain) { vault.retryUnlock() }
        case .readOnly(.newerVersion):
            Label {
                Text(EncryptionCopy.readOnly)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

/// 数据目录里还留着当前密钥解不开的旧历史（E8 ②，之后的启动）：提供「在访达中显示」
struct UnreadableHistoryRow: View {
    let folders: [URL]

    var body: some View {
        LabeledContent {
            Button(EncryptionCopy.showInFinder) { ItemOpener.revealInFinder(folders.map(\.path)) }
        } label: {
            Text("Old history", comment: "Settings › History: row for old history that can't be decrypted")
            Text(
                "Can't be decrypted with the current key. It's kept and restored automatically if the key comes back.",
                comment: "Settings › History: subtitle of the old history row"
            )
        }
    }
}

/// 「加密」一行下方的说明（随状态变化）
struct EncryptionFooter: View {
    let vault: VaultCoordinator

    var body: some View {
        Text(text).foregroundStyle(.secondary)
    }

    private var text: String {
        switch vault.status {
        case .preparing, .ready: EncryptionCopy.readyFooter
        case .migrating: EncryptionCopy.migratingFooter
        case .locked: EncryptionCopy.lockedFooter
        case .resetAfterMissingKey(let folder): EncryptionCopy.resetFooter(folderName: folder.lastPathComponent)
        case .readOnly(let reason): reason.warning.detail
        }
    }
}

/// 加密相关文案（设置页与面板共用的部分）
enum EncryptionCopy {
    static var readySubtitle: String {
        String(
            localized: "History, images and logs are stored encrypted",
            comment: "Settings › History: subtitle of the Encryption row when encryption is on")
    }

    static var migratingSubtitle: String {
        String(
            localized: "Encrypting existing history…",
            comment: "Settings › History: subtitle while the existing history is being encrypted")
    }

    static var lockedSubtitle: String {
        String(
            localized: "History is locked: can't read the key from the keychain",
            comment: "Settings › History: shown when the encryption key can't be read")
    }

    static var resetSubtitle: String {
        String(
            localized: "Couldn't find the key for your old history, so Cubby started a new one",
            comment: "Settings › History: shown when the key for the old history is missing")
    }

    static var migrationFailed: String {
        String(
            localized:
                "Your existing history couldn't be encrypted this time and was left as is. Cubby will try again next launch.",
            comment: "Settings › History: shown when encrypting the existing history failed")
    }

    static var readyFooter: String {
        String(
            localized: """
                The key is stored in your login keychain, so other apps can only read encrypted data. \
                Only allow a keychain prompt right after installing or updating Cubby, when Cubby itself asks. \
                Deny it at any other time — denying never loses data.
                """,
            comment: "Settings › History: footer under the Encryption row")
    }

    static var migratingFooter: String {
        String(
            localized: """
                This only happens on the first launch after an update. \
                The old unencrypted files are deleted only after everything is encrypted and verified.
                """,
            comment: "Settings › History: footer while the existing history is being encrypted")
    }

    static var lockedFooter: String {
        String(
            localized: """
                New copies are kept in memory for now. Click Try Again and allow Cubby's request, \
                and they'll be merged into your history. Your existing history isn't lost.
                """,
            comment: "Settings › History: footer when history is locked")
    }

    static func resetFooter(folderName: String) -> String {
        String(
            localized: """
                The key in your keychain is gone (for example, after resetting the login keychain), \
                so the old history can't be decrypted. It's kept in the “\(folderName)” folder and won't be deleted, \
                and it's restored automatically if the key comes back.
                """,
            comment:
                "Settings › History: footer when the key for the old history is missing. The argument is a folder name."
        )
    }

    /// 历史由更新版本写入、本次不写盘时「加密」一行右侧的状态
    static var readOnly: String {
        String(
            localized: "Read-only",
            comment: "Settings › History: status when the history was written by a newer version, so nothing is saved")
    }

    static var tryAgain: String {
        String(localized: "Try Again", comment: "Button: read the key from the keychain again")
    }

    static var showInFinder: String {
        String(localized: "Show in Finder", comment: "Button")
    }
}

extension VaultStatus {
    /// 本次启动因找不到旧密钥而从空历史重新开始（E8 ②）
    var isResetAfterMissingKey: Bool {
        if case .resetAfterMissingKey = self { return true }
        return false
    }

    /// 诊断信息用的英文描述：不含路径、密钥或密钥 ID
    var diagnosticDescription: String {
        switch self {
        case .preparing: "preparing"
        case .migrating(let done, let total): "migrating (\(done)/\(total))"
        case .ready: "ready"
        case .locked: "locked"
        case .resetAfterMissingKey: "reset after missing key"
        case .readOnly(.newerVersion): "read-only (newer version)"
        case .readOnly(.unreadable): "read-only (unreadable)"
        }
    }
}

extension VaultStatus.ReadOnlyReason {
    /// 沿用面板上读取历史出错时的提醒文案：更新版本写入 / 无法保存
    var warning: PanelWarning {
        switch self {
        case .newerVersion: .historyFromNewerVersion
        case .unreadable: .persistenceDisabled
        }
    }
}
