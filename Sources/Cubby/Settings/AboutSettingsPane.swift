import CubbyCore
import SwiftUI

/// 设置 › 关于：版本、使用说明、检查更新、复制诊断信息
struct AboutSettingsPane: View {
    let settings: AppSettings
    let store: ClipStore
    let updates: UpdateCoordinator
    let openUserGuide: () -> Void

    private static let contentWidth: CGFloat = 520
    private static let iconSize: CGFloat = 96
    private static let copiedFeedbackDuration: Duration = .seconds(2)

    /// 在本页点「检查更新」得到的结果（已知的新版本由 AboutUpdateStatus 直接从协调器读取）
    @State private var manualResult: UpdateChecker.Result?
    @State private var didCopyDiagnostics = false

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return String(localized: "Development build", comment: "Version text when running without an app bundle")
        }
        guard let build = info?["CFBundleVersion"] as? String else {
            return String(localized: "Version \(version)", comment: "About: app version")
        }
        return String(localized: "Version \(version) (\(build))", comment: "About: app version and build number")
    }

    private var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    var body: some View {
        VStack(spacing: 0) {
            AppIconImage(size: Self.iconSize)

            Text(verbatim: "Cubby")
                .font(.title.weight(.bold))
                .padding(.top, 12)
            Text(versionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text(AppCopy.tagline)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            actions
                .padding(.top, 16)
            AboutUpdateStatus(updates: updates, manualResult: manualResult)
                .padding(.top, 8)

            privacyNote
                .padding(.top, 20)

            if let copyright {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: Self.contentWidth)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("User Guide", action: openUserGuide)
            Button(updates.isChecking ? "Checking…" : "Check for Updates", action: checkForUpdates)
                .disabled(updates.isChecking)
            Button(didCopyDiagnostics ? "Copied" : "Copy Diagnostic Info", action: copyDiagnostics)
                .disabled(didCopyDiagnostics)
                .help(
                    """
                    Copies the version, system and permission status for bug reports. \
                    Never includes clipboard content.
                    """
                )
        }
    }

    private func checkForUpdates() {
        Task { @MainActor in
            manualResult = await updates.check()
        }
    }

    private func copyDiagnostics() {
        Task { @MainActor in
            let size = await DirectorySize.bytes(at: AppPaths.root)
            Diagnostics.copy(Diagnostics.report(settings: settings, store: store, dataSize: size))
            didCopyDiagnostics = true
            try? await Task.sleep(for: Self.copiedFeedbackDuration)
            didCopyDiagnostics = false
        }
    }

    private var privacyNote: some View {
        Label {
            Text("All clipboard data stays on this Mac and is never uploaded.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
