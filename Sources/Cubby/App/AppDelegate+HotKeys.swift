import AppKit
import CubbyCore

// 全局快捷键：注册、注销、冲突时回退到上一个可用的快捷键，以及录制新快捷键期间的暂停与恢复
extension AppDelegate {

    func registerHotKeys() {
        registerPanelHotKey()
        registerScreenshotHotKey()
        registerImagesHotKey()
        registerClotheslineHotKey()
    }

    /// 晾衣绳的显示 / 收起：关闭了快捷键或整个晾衣绳时注销
    func registerClotheslineHotKey() {
        guard settings.clotheslineEnabled, let hotKey = settings.clotheslineHotKey else {
            hotKeys.unregister(.clothesline)
            return
        }
        register(hotKey, for: .clothesline) { [weak self] in
            self?.toggleClothesline()
        }
    }

    /// 「只看图片」：用户关闭时注销
    func registerImagesHotKey() {
        guard let hotKey = settings.imagesHotKey else {
            hotKeys.unregister(.images)
            return
        }
        register(hotKey, for: .images) { [weak self] in
            self?.panel?.toggleImages()
        }
    }

    func registerPanelHotKey() {
        register(settings.hotKey, for: .togglePanel) { [weak self] in
            self?.panel?.toggle()
        }
    }

    /// 用户清空截图快捷键时注销（只剩菜单栏与面板按钮两个入口）
    func registerScreenshotHotKey() {
        guard let hotKey = settings.screenshotHotKey else {
            hotKeys.unregister(.screenshot)
            return
        }
        register(hotKey, for: .screenshot) { [weak self] in
            self?.screenshots?.start(.hotKey)
        }
    }

    /// 暂停期间（正在录制另一个快捷键）只登记，真正的结果在恢复时由 hotKeysResumed 处理
    func register(_ hotKey: HotKey, for action: HotKeyAction, handler: @escaping () -> Void) {
        switch hotKeys.register(hotKey, for: action, handler: handler) {
        case .registered: lastWorkingHotKeys[action] = hotKey
        case .deferred: break
        case .failed: hotKeyRegistrationFailed(hotKey, for: action)
        }
    }

    func hotKeyRegistrationFailed(_ hotKey: HotKey, for action: HotKeyAction) {
        logger.error(
            """
            Failed to register hot key \(hotKey.displayName, privacy: .public) \
            for action \(action.rawValue), maybe used by another app
            """
        )
        notifyHotKeyConflict(hotKey, for: action)
    }

    /// 新快捷键被占用时告知用户，并回退到该动作上一个可用的快捷键（回退会再次触发注册）
    func notifyHotKeyConflict(_ hotKey: HotKey, for action: HotKeyAction) {
        let fallback = lastWorkingHotKeys[action].flatMap { $0 == hotKey ? nil : $0 }
        let message =
            fallback.map {
                String(
                    localized: "\(hotKey.displayName) is already in use. Switched back to \($0.displayName).",
                    comment: "HUD when a new global shortcut is taken. %1$@ = new shortcut, %2$@ = previous shortcut"
                )
            }
            ?? String(
                localized: "\(hotKey.displayName) is used by another app. Choose a different shortcut in Settings.",
                comment: "HUD when the global shortcut is taken"
            )
        if let anchor = HUDToast.defaultAnchor() {
            HUDToast.show(message, symbolName: "exclamationmark.triangle.fill", tint: .orange, at: anchor)
        }
        guard let fallback else { return }
        settings.setHotKey(fallback, for: action)
    }

    /// 录制新快捷键期间暂停全局热键；恢复时报告暂停期间登记的快捷键是否注册成功
    func setShortcutRecording(_ isRecording: Bool) {
        if isRecording {
            hotKeys.suspend()
        } else {
            hotKeysResumed(failed: hotKeys.resume())
        }
    }

    /// 注册成功的记为「上一个可用」；失败的提示并回滚（与直接注册失败同一路径）
    func hotKeysResumed(failed: [HotKeyAction]) {
        for action in HotKeyAction.allCases {
            if let working = hotKeys.registeredHotKey(for: action) {
                lastWorkingHotKeys[action] = working
            }
        }
        for action in failed {
            guard let hotKey = settings.hotKey(for: action) else { continue }
            hotKeyRegistrationFailed(hotKey, for: action)
        }
    }
}
