import Observation

/// 按钮上的短暂确认（例如「已复制」）：flash 后显示一段时间自动恢复，再次 flash 重新计时
@MainActor
@Observable
final class TransientFeedback {
    private(set) var isShowing = false
    @ObservationIgnored private var reset: Task<Void, Never>?

    func flash(for duration: Duration) {
        reset?.cancel()
        isShowing = true
        reset = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.isShowing = false
        }
    }

    func clear() {
        reset?.cancel()
        isShowing = false
    }
}
