import SwiftUI

/// 「登录时自动启动」开关：设置失败时回滚并显示原因
struct LaunchAtLoginToggle: View {
    @State private var isOn = LaunchAtLogin.isEnabled || LaunchAtLogin.requiresApproval
    @State private var needsApproval = LaunchAtLogin.requiresApproval
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(get: { isOn }, set: { update($0) }))
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if needsApproval {
                HStack(spacing: 4) {
                    Text("Allow Cubby in Login Items")
                        .foregroundStyle(.orange)
                    Button("Open Login Items Settings", action: LaunchAtLogin.openSystemSettings)
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
        }
        .onAppear(perform: syncWithSystem)
    }

    private func update(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = String(
                localized: "Couldn't change the login item: \(error.localizedDescription)",
                comment: "Error when turning launch at login on or off"
            )
        }
        // 无论成功与否都以系统实际状态为准（失败即回滚）
        syncWithSystem()
    }

    private func syncWithSystem() {
        needsApproval = LaunchAtLogin.requiresApproval
        isOn = LaunchAtLogin.isEnabled || needsApproval
    }
}
