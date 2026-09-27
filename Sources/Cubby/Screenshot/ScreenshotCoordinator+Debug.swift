#if DEBUG
import AppKit
import CubbyCore

/// 调试场景（--scenario screenshot:<名称>）。会话类场景用 FixtureFrameSource 合成桌面，
/// 不需要屏幕录制权限，也不会截到用户的真实屏幕
extension ScreenshotCoordinator {
    private static let scenarioPrefix = "screenshot:"

    /// - permission：权限引导窗口；pin：两张演示贴图
    /// - live：真实采集（需要权限），覆盖层交付前只在日志中记录耗时与帧尺寸
    /// - window-probe：对演示贴图做纯净窗口截图实测（带 / 不带阴影），只记录尺寸与透明度
    /// - showcase：README 截图用的展示场景（合成桌面 + 预置标注），见 ShowcaseScenario.swift
    /// - save-dialog：annotating 场景上屏后按 ⌘S 弹出真实的存储对话框，4 秒后自动点「取消」（走查 §9.4 用，不写文件）
    /// - translate：展示场景上屏后自动翻译（桩引擎、真实的 Vision 识别，不联网；走查截图翻译用）
    /// - 其余名称交给 ScreenshotDebugScenario（hovering、adjusting、annotating:<tool>、hover-cycle、window-mode 等）
    func startDebugScenario(_ scenario: String) {
        let name =
            scenario.hasPrefix(Self.scenarioPrefix) ? String(scenario.dropFirst(Self.scenarioPrefix.count)) : scenario
        switch name {
        case "permission": guide.show()
        case "pin": pins.pinDemo()
        case "live": startLiveCapture()
        case "window-probe": probeWindowCapture()
        case "showcase": startShowcase()
        case "save-dialog": startSaveDialogWalkthrough()
        case "translate": startTranslationShowcase()
        default: startFixture(named: name)
        }
    }

    private func startSaveDialogWalkthrough() {
        debugAfterPresent = { [savePrompt] overlay in
            (overlay as? ScreenshotOverlayController)?.send(.command(.save))
            (savePrompt as? ScreenshotSavePrompt)?.debugCancel(after: .seconds(4))
        }
        startFixture(named: "annotating")
    }

    /// 换上翻译桩（覆盖 App 提供的正式服务，只在这次调试运行中）后开始展示场景，上屏即按 ⇧⌘T
    private func startTranslationShowcase() {
        var script = E2ETranslationProvider.Script()
        script.firstDelay = .milliseconds(300)
        script.blockDelay = .milliseconds(160)
        translation = E2ETranslationProvider(script: script)
        translationRecognizer = VisionTranslationRecognizer()
        debugAfterPresent = { overlay in
            (overlay as? ScreenshotOverlayController)?.send(.command(.translate))
        }
        startShowcase()
    }

    private func startFixture(named name: String) {
        let fixture = FixtureFrameSource(screens: ScreenTopologyProvider.screens())
        let styles = settings.annotationStyles
        begin(frameSource: fixture, windowSource: fixture) { [logger] capture in
            let session = ScreenshotDebugScenario.session(named: name, topology: capture.topology, styles: styles)
            if session == nil {
                logger.error("Unknown screenshot scenario \(name, privacy: .public)")
            }
            return session
        }
    }

    /// 贴图是 Cubby 自己的窗口、内容是合成图片：实测不涉及用户内容。
    /// 设置了 CUBBY_DATA_DIR 时把两张结果写到该目录，便于检查圆角透明与阴影
    private func probeWindowCapture() {
        pins.pinDemo()
        guard let windowID = pins.windowIDs.sorted().first else { return }
        Task {
            // 等窗口服务器完成首次绘制
            try? await Task.sleep(for: .milliseconds(600))
            for includeShadow in [true, false] {
                await probe(windowID: windowID, includeShadow: includeShadow)
            }
        }
    }

    private func probe(windowID: UInt32, includeShadow: Bool) async {
        do {
            let result = try await WindowImageCapturer().captureWindow(
                id: windowID, includeShadow: includeShadow, timeout: Self.captureTimeout)
            let image = result.image
            let corner = Self.alpha(in: image, x: 0, y: 0)
            let center = Self.alpha(in: image, x: image.width / 2, y: image.height / 2)
            logger.notice(
                """
                Window probe: shadow \(includeShadow, privacy: .public), \
                \(image.width, privacy: .public)x\(image.height, privacy: .public) px @\(result.scale, privacy: .public)x, \
                corner alpha \(corner, privacy: .public), center alpha \(center, privacy: .public)
                """
            )
            if let directory = ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"],
                let png = ScreenshotExporter.pngData(image, scale: result.scale)
            {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(
                    "window-probe-shadow-\(includeShadow).png")
                try? png.write(to: url)
            }
        } catch {
            logger.error("Window probe failed: \(FrozenFrameCapturer.mapped(error).logName, privacy: .public)")
        }
    }

    /// 位图 (x, y)（左上原点）处像素的 alpha
    private static func alpha(in image: CGImage, x: Int, y: Int) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(
                image,
                in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return Int(pixel[3])
    }
}
#endif
