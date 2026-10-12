import CubbyCore
import SwiftUI

/// 设置 › 通用 › 晾衣绳（docs/UI-UPGRADE-PLAN.md 第 5 节）：开关、显示 / 收起的快捷键、指针停在顶边多久后滑下、
/// 绳上的张数与「全部取下」
struct ClotheslineSettingsSection: View {
    @Bindable var settings: AppSettings
    let onShortcutRecordingChange: (Bool) -> Void

    var body: some View {
        Section {
            Toggle(isOn: $settings.clotheslineEnabled) {
                Text("Hang images at the top of the screen")
                Text(
                    "Press ⌘L on an image in the panel to hang it; rest the pointer at the top edge to slide the line down"
                )
            }
            if settings.clotheslineEnabled {
                LabeledContent("Show / Hide") {
                    ShortcutRecorder(
                        optionalHotKey: $settings.clotheslineHotKey,
                        defaultHotKey: .clotheslineDefault,
                        reservations: HotKeyReservations.excluding(.clothesline, settings: settings),
                        onRecordingChange: onShortcutRecordingChange
                    )
                }
                Picker("Slide down after the pointer rests at the top edge for", selection: $settings.clotheslineDwell)
                {
                    ForEach(AppSettings.clotheslineDwellChoices, id: \.self) { seconds in
                        Text(Self.secondsText(seconds)).tag(seconds)
                    }
                }
                LabeledContent("Photos on the line") {
                    HStack(spacing: 10) {
                        Text(
                            "\(settings.clothesline.count) of \(Clothesline.capacity) photos",
                            comment: "Settings: number of photos on the clothesline, e.g. “4 of 12 photos”"
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        Button("Take All Down") { settings.clothesline = Clothesline() }
                            .disabled(settings.clothesline.isEmpty)
                    }
                }
            }
        } header: {
            Text("Clothesline")
        } footer: {
            Text(
                "Click a photo on the line to enlarge and annotate it, double-click to copy it, or drag it into another app. Taking a photo down doesn't remove it from your history."
            )
            .foregroundStyle(.secondary)
        }
    }

    /// 「0.5 秒」：按界面语言格式化（小数点、单位）
    private static func secondsText(_ seconds: TimeInterval) -> String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}
