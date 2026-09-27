import AppKit
import Carbon.HIToolbox
import SwiftUI
import CubbyCore

/// 快捷键录制控件：点击后按下新的组合键即可保存，esc 或点击其他位置取消。
/// 录制期间通过 onRecordingChange 通知外部临时注销全局热键，否则按下当前热键会直接触发对应动作。
/// 可清空的录制器（截图快捷键）多一个「关闭」按钮；与其他功能占用的快捷键相同时拒绝并说明原因
struct ShortcutRecorder: View {
    /// 已被其他功能占用的快捷键，以及录到它时显示的原因
    struct Reservation {
        let hotKey: HotKey
        let message: String
    }

    @Binding var hotKey: HotKey?
    let defaultHotKey: HotKey
    let allowsClearing: Bool
    let reservations: [Reservation]
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var rejection: String?
    @State private var rejectionToken = 0
    @State private var shakeCount: CGFloat = 0

    /// 录制框连同其后的「恢复默认」「关闭」按钮共占的宽度：按钮出现时录制框让出相应宽度，整组宽度不变，
    /// 设置里上下两个录制器（截图快捷键多一个「关闭」）的录制框左缘、整组右缘都落在同一竖线上。
    /// 键帽放不下时录制框按内容撑开（向左延伸），不压缩键帽
    private static let fieldWidth: CGFloat = 168
    private static let fieldHeight: CGFloat = 28
    /// 录制框内容的水平内边距
    private static let fieldInset: CGFloat = 8
    private static let rejectionDuration: Duration = .seconds(1.8)

    /// 不可清空的快捷键（面板）
    init(
        hotKey: Binding<HotKey>,
        defaultHotKey: HotKey = .default,
        reservations: [Reservation] = [],
        onRecordingChange: @escaping (Bool) -> Void
    ) {
        _hotKey = Binding(
            get: { hotKey.wrappedValue },
            set: { newValue in
                if let newValue { hotKey.wrappedValue = newValue }
            }
        )
        self.defaultHotKey = defaultHotKey
        self.allowsClearing = false
        self.reservations = reservations
        self.onRecordingChange = onRecordingChange
    }

    /// 可关闭的快捷键：nil 表示关闭。allowsClearing 为 false 时不显示「关闭」按钮（仍可显示已关闭的状态并重新录制）
    init(
        optionalHotKey: Binding<HotKey?>,
        defaultHotKey: HotKey,
        allowsClearing: Bool = true,
        reservations: [Reservation] = [],
        onRecordingChange: @escaping (Bool) -> Void
    ) {
        _hotKey = optionalHotKey
        self.defaultHotKey = defaultHotKey
        self.allowsClearing = allowsClearing
        self.reservations = reservations
        self.onRecordingChange = onRecordingChange
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                field
                if !isRecording && hotKey != defaultHotKey {
                    resetButton
                }
                if !isRecording && allowsClearing && hotKey != nil {
                    Button("Off") { hotKey = nil }
                        .controlSize(.small)
                }
            }
            .frame(width: Self.fieldWidth, alignment: .trailing)
            Button(isRecording ? "Cancel" : "Record") { setRecording(!isRecording) }
                .controlSize(.small)
        }
        .background(
            KeyEventCapture(
                isRecording: isRecording,
                onKeyDown: handleKeyDown,
                onModifiersChange: handleModifiersChange,
                onInterrupt: { setRecording(false) }
            )
        )
        .onDisappear { setRecording(false) }
        .animation(.easeOut(duration: 0.12), value: isRecording)
    }

    // MARK: - 子视图

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return Button {
            setRecording(true)
        } label: {
            fieldContent
                // 先撑满录制框再居中：无论键帽多少、是否在录制，内容始终水平居中。
                // 宽度取按钮之外的剩余空间（见 fieldWidth），但不小于键帽本身
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, Self.fieldInset)
                .frame(height: Self.fieldHeight)
                .background(
                    shape.fill(isRecording ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                )
                .overlay(
                    shape.strokeBorder(
                        isRecording ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isRecording ? 1.5 : 0.5
                    )
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .modifier(ShakeEffect(animatableData: shakeCount))
        .help(isRecording ? "Press a new shortcut, or esc to cancel" : "Click, then press a new shortcut")
        .accessibilityLabel(
            isRecording ? Text("Recording shortcut") : Text("Keyboard shortcut: \(displayName)")
        )
    }

    @ViewBuilder
    private var fieldContent: some View {
        if !isRecording, let hotKey {
            // 键帽保持理想宽度：录制框让出按钮空间后放不下时撑开录制框，而不是截断键帽
            ShortcutKeyCaps(symbols: hotKey.keySymbols)
                .fixedSize()
        } else if !isRecording {
            Text("Off")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
        } else if let rejection {
            // 较长的原因（如「已用于打开面板」的英文）允许折成两行并略微缩小，不截断
            Label(rejection, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        } else if !liveModifiers.isEmpty {
            HStack(spacing: 4) {
                ShortcutKeyCaps(symbols: Self.symbols(for: liveModifiers), isDimmed: true)
                Text(verbatim: "…").foregroundStyle(.secondary)
            }
        } else {
            Text("Press the new shortcut…")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// 默认值已被另一功能占用时不能恢复（例如面板快捷键被改成了 ⇧⌘2），悬停提示原因
    private var resetButton: some View {
        let blocker = reservations.first { $0.hotKey == defaultHotKey }
        return Button {
            hotKey = defaultHotKey
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(blocker != nil)
        .help(blocker.map { Text(verbatim: $0.message) } ?? Text("Restore default (\(defaultHotKey.displayName))"))
        .accessibilityLabel("Restore default shortcut")
    }

    /// 当前快捷键的显示名；关闭时为「关闭」
    private var displayName: String {
        hotKey?.displayName
            ?? String(localized: "Off", comment: "Shortcut recorder state when the shortcut is turned off")
    }

    // MARK: - 录制逻辑

    private func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        liveModifiers = []
        rejection = nil
        onRecordingChange(recording)
    }

    private func handleModifiersChange(_ flags: NSEvent.ModifierFlags) {
        liveModifiers = flags.intersection([.control, .option, .shift, .command])
        if !liveModifiers.isEmpty {
            rejection = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            setRecording(false)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 不带修饰键的字符（如 ⇧⌘1 取 "1" 而不是 "!"）
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let recorded = HotKey(keyCode: event.keyCode, modifierFlags: flags, characters: characters) else {
            let hasPrimaryModifier = !flags.isDisjoint(with: [.command, .option, .control])
            reject(
                hasPrimaryModifier
                    ? String(localized: "Key not supported", comment: "Shortcut recorder error")
                    : String(localized: "Include ⌘, ⌥ or ⌃", comment: "Shortcut recorder error")
            )
            return
        }
        guard !ReservedShortcuts.contains(recorded) else {
            reject(
                String(localized: "\(recorded.displayName) is a system shortcut", comment: "Shortcut recorder error")
            )
            return
        }
        if let reservation = reservations.first(where: { $0.hotKey == recorded }) {
            reject(reservation.message)
            return
        }
        hotKey = recorded
        setRecording(false)
    }

    /// 不合法的组合：抖动并短暂显示原因
    private func reject(_ message: String) {
        rejection = message
        rejectionToken += 1
        let token = rejectionToken
        withAnimation(.linear(duration: 0.32)) { shakeCount += 1 }
        Task { @MainActor in
            try? await Task.sleep(for: Self.rejectionDuration)
            if rejectionToken == token { rejection = nil }
        }
    }

    private static func symbols(for flags: NSEvent.ModifierFlags) -> [String] {
        let ordered: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return ordered.filter { flags.contains($0.0) }.map(\.1)
    }
}

/// 会破坏常用编辑操作的全局快捷键，不允许设置
private enum ReservedShortcuts {
    private static let commandOnlyKeyCodes: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_Q, kVK_ANSI_S, kVK_ANSI_V,
        kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Z, kVK_Tab, kVK_Space,
    ]

    static func contains(_ hotKey: HotKey) -> Bool {
        hotKey.modifiers == UInt32(cmdKey) && commandOnlyKeyCodes.contains(Int(hotKey.keyCode))
    }
}

/// 左右抖动，用于提示输入不合法
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    private let travel: CGFloat = 4

    init(animatableData: CGFloat) {
        self.animatableData = animatableData
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = travel * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
