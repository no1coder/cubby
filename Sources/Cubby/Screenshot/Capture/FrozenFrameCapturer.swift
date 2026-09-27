import CoreGraphics
import CoreVideo
import CubbyCore
import Foundation
import ScreenCaptureKit
import os

/// ScreenCaptureKit 实现：每块屏幕按原生像素各采一帧（并行），排除 Cubby 自己的窗口（贴图除外，Q12）。
/// 窗口列表另用 CGWindowList 读取：它按 z 序从前到后返回，且只取几何信息，不读标题
struct FrozenFrameCapturer: FrameSource {
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")

    func capture(excludingPID: pid_t, exceptWindowIDs: Set<UInt32>, timeout: Duration) async throws -> CaptureSession {
        let screens = await ScreenTopologyProvider.screens()
        guard !screens.isEmpty else { throw FrameCaptureError.noDisplays }
        return try await CaptureDeadline.run(timeout) {
            try await Self.captureAll(screens: screens, ownPID: excludingPID, keeping: exceptWindowIDs)
        }
    }

    // MARK: - 采集

    private static func captureAll(
        screens: [CaptureScreen],
        ownPID: pid_t,
        keeping keptIDs: Set<UInt32>
    ) async throws -> CaptureSession {
        let clock = ContinuousClock()
        let start = clock.now
        let content = try await shareableContent()
        let contentReady = clock.now
        let windows = WindowListReader.candidates(ownPID: ownPID, keeping: keptIDs)
        let jobs = makeJobs(screens: screens, content: content, ownPID: ownPID, keeping: keptIDs)
        let frames = try await captureFrames(jobs)
        guard !frames.isEmpty else { throw FrameCaptureError.noDisplays }

        let capturedIDs = Set(frames.map(\.screen.id))
        logger.notice(
            """
            Frozen frames: \(frames.count, privacy: .public) screen(s), \
            content \(milliseconds(contentReady - start), privacy: .public) ms, \
            frames \(milliseconds(clock.now - contentReady), privacy: .public) ms
            """
        )
        let topology = ScreenTopology(
            screens: screens.filter { capturedIDs.contains($0.id) },
            windows: windows,
            ownPID: ownPID
        )
        return CaptureSession(topology: topology, frames: frames)
    }

    private static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw mapped(error)
        }
    }

    /// 每块屏幕一个过滤器：排除 Cubby 进程，但保留贴图窗口
    private static func makeJobs(
        screens: [CaptureScreen],
        content: SCShareableContent,
        ownPID: pid_t,
        keeping keptIDs: Set<UInt32>
    ) -> [DisplayCaptureJob] {
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let keptWindows = content.windows.filter { keptIDs.contains($0.windowID) }
        return screens.compactMap { screen in
            guard let display = content.displays.first(where: { $0.displayID == screen.id }) else { return nil }
            let filter = SCContentFilter(
                display: display, excludingApplications: ownApps, exceptingWindows: keptWindows)
            return DisplayCaptureJob(screen: screen, filter: filter, configuration: configuration(for: screen))
        }
    }

    private static func configuration(for screen: CaptureScreen) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(screen.pixelSize.width)
        configuration.height = Int(screen.pixelSize.height)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return configuration
    }

    /// 各屏并行采集；单屏失败不影响其他屏（全部失败时由调用方报 noDisplays），但权限类错误直接抛出
    private static func captureFrames(_ jobs: [DisplayCaptureJob]) async throws -> [FrozenFrame] {
        try await withThrowingTaskGroup(of: FrozenFrame?.self) { group in
            for job in jobs {
                group.addTask {
                    do {
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: job.filter,
                            configuration: job.configuration
                        )
                        return FrozenFrame(screen: job.screen, image: image)
                    } catch {
                        let mappedError = mapped(error)
                        if case .notAuthorized = mappedError { throw mappedError }
                        logger.error(
                            "Screen \(job.screen.id, privacy: .public) failed: \(mappedError.logName, privacy: .public)"
                        )
                        return nil
                    }
                }
            }
            var frames: [FrozenFrame] = []
            for try await frame in group {
                if let frame { frames.append(frame) }
            }
            // 保持与屏幕列表相同的顺序
            return jobs.compactMap { job in frames.first { $0.screen.id == job.screen.id } }
        }
    }

    // MARK: - 辅助

    /// 用户拒绝（或尚未授权）时 ScreenCaptureKit 返回 userDeclined
    static func mapped(_ error: any Error) -> FrameCaptureError {
        if let known = error as? FrameCaptureError { return known }
        if error is CaptureDeadline.TimedOut { return .timedOut }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .notAuthorized
        }
        return .underlying(error)
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

/// 一块屏幕的采集参数。ScreenCaptureKit 的过滤器与配置在创建后只读、不再修改，
/// 交给并发子任务使用是安全的，因此标为 @unchecked Sendable（SDK 未标注 Sendable）
private struct DisplayCaptureJob: @unchecked Sendable {
    let screen: CaptureScreen
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
}

/// 屏幕上的窗口几何（CGWindowList：前 → 后）；只读 id、边界、层级、进程与透明度，不读标题
enum WindowListReader {
    /// Cubby 自己的窗口只保留 keeping 中的（贴图），其余（HUD 等）不在冻结帧里，也不参与悬停
    static func candidates(ownPID: pid_t, keeping keptIDs: Set<UInt32>) -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let candidate = candidate(from: info) else { return nil }
            let isOwnHidden = candidate.ownerPID == ownPID && !keptIDs.contains(candidate.id)
            return isOwnHidden ? nil : candidate
        }
    }

    private static func candidate(from info: [String: Any]) -> WindowCandidate? {
        guard
            let number = info[kCGWindowNumber as String] as? NSNumber,
            let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsInfo)
        else { return nil }
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        return WindowCandidate(
            id: number.uint32Value,
            frame: bounds,
            layer: layer,
            ownerPID: pid.int32Value,
            alpha: alpha
        )
    }
}
