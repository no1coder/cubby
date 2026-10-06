import AppKit

/// 给读屏器的即时播报：按钮标题短暂变化（例如「已复制」）时 VoiceOver 不会自己朗读
enum AccessibilityAnnouncement {
    @MainActor
    static func post(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
