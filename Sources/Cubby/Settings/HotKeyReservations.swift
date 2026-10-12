import CubbyCore

/// 全局快捷键之间互相保留：录制某个动作的快捷键时，不能与其他动作（面板、截图、只看图片、晾衣绳）的快捷键相同
@MainActor
enum HotKeyReservations {
    static func excluding(_ action: HotKeyAction, settings: AppSettings) -> [ShortcutRecorder.Reservation] {
        HotKeyAction.allCases.filter { $0 != action }.compactMap { other in
            settings.hotKey(for: other).map {
                ShortcutRecorder.Reservation(hotKey: $0, message: message(for: other))
            }
        }
    }

    private static func message(for action: HotKeyAction) -> String {
        switch action {
        case .togglePanel: ShortcutReservationCopy.panel
        case .screenshot: ShortcutReservationCopy.screenshots
        case .images:
            String(localized: "Already used to show only images", comment: "Shortcut recorder error")
        case .clothesline:
            String(localized: "Already used for the clothesline", comment: "Shortcut recorder error")
        }
    }
}
