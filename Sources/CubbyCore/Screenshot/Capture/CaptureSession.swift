/// 一次采集的结果：几何拓扑 + 每块屏幕的冻结帧
///
/// `@unchecked Sendable` 的理由：只包含不可变的 `FrozenFrame`（其中 CGImage 不可变）与 Sendable 的拓扑。
public struct CaptureSession: @unchecked Sendable {
    /// 屏幕与窗口拓扑
    public let topology: ScreenTopology
    /// 每块屏幕一帧
    public let frames: [FrozenFrame]

    public init(topology: ScreenTopology, frames: [FrozenFrame]) {
        self.topology = topology
        self.frames = frames
    }

    /// 某块屏幕的冻结帧；该屏未采集到时为 nil
    public func frame(for screenID: UInt32) -> FrozenFrame? {
        frames.first { $0.screen.id == screenID }
    }
}
