import ServiceManagement

/// 开机自启（需要以 .app 形式运行才生效）
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 已注册但需要用户在「系统设置 › 通用 › 登录项」中批准
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
