import AppKit
import CubbyCore

/// 晾衣绳单击：放大编辑一张历史图片
enum HistoryImageEditResult: Equatable {
    /// esc / × / 显示器变化
    case cancelled
    /// ⌘C 或「复制」：标注后的图已在剪贴板上
    case copied
    /// ↩ 或「完成并晾回」：新历史条目的 id
    case hungBack(UUID)
    /// 请求了晾回，但暂停记录中或图片超出历史大小限制（或写入失败）
    case notSaved
    /// 贴图 / 存储 / 提取文字 / 翻译结束了会话
    case other
}

/// 放大编辑的图片来源（缩放时用它以新的尺寸重建覆盖层）
struct HistoryImageEditSource {
    let item: ClipItem
    let image: CGImage
    /// 原图 PNG 的 DPI 倍率
    let dpiScale: CGFloat
    let screen: CaptureScreen
}

/// 进行中的放大编辑
struct HistoryImageEditSession {
    let overlay: any ScreenshotOverlayPresenting
    let source: HistoryImageEditSource
    let layout: HistoryImageLayout
    let onFinish: @MainActor (HistoryImageEditResult) -> Void
}

/// 晾衣绳放大编辑（docs/UI-UPGRADE-PLAN.md §5「单击 → 放大并标注」）：把历史图片当作冻结帧喂给截图覆盖层，
/// 复用全部标注能力。不截屏（不需要屏幕录制权限）：背景由图片本身合成（`HistoryImageBackdrop`）。
/// 会话的选区锁定为图片本身（`ScreenshotSession.locked`）；导出按原图像素尺寸（`HistoryEditContext.nativeFrame`）。
/// 只用一块屏幕；显示器布局变化时取消（与截图相同）
extension ScreenshotCoordinator {
    /// Returns false when it could not start (another screenshot session is active, the image can't be decoded).
    @discardableResult
    func editHistoryImage(
        _ item: ClipItem, imageData: Data, on screen: NSScreen,
        onFinish: @escaping @MainActor (HistoryImageEditResult) -> Void
    ) -> Bool {
        guard !isActive else {
            logger.info("History image edit ignored: a screenshot session is active")
            return false
        }
        guard let captureScreen = ScreenTopologyProvider.captureScreen(for: screen) else {
            logger.error("History image edit: no display for the screen")
            return false
        }
        guard let decoded = HistoryImageBackdrop.decode(imageData) else {
            logger.error("History image edit: couldn't decode the image")
            return false
        }
        let source = HistoryImageEditSource(
            item: item, image: decoded.image, dpiScale: decoded.dpiScale, screen: captureScreen)
        return presentHistoryEdit(source, zoom: nil, tool: .rectangle, onFinish: onFinish)
    }

    // MARK: - 上屏与缩放

    private func presentHistoryEdit(
        _ source: HistoryImageEditSource,
        zoom: CGFloat?,
        tool: ScreenshotTool,
        onFinish: @escaping @MainActor (HistoryImageEditResult) -> Void
    ) -> Bool {
        let screen = source.screen
        let pixelSize = CGSize(width: source.image.width, height: source.image.height)
        guard let layout = HistoryImageLayout.layout(imagePixelSize: pixelSize, screen: screen, zoom: zoom),
            let backdrop = HistoryImageBackdrop.render(source.image, layout: layout, screen: screen)
        else {
            logger.error("History image edit: couldn't lay out the image")
            return false
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let capture = CaptureSession(
            topology: ScreenTopology(screens: [screen], windows: [], ownPID: ownPID),
            frames: [FrozenFrame(screen: screen, image: backdrop)])
        let session = ScreenshotSession.locked(
            selection: layout.imageRect,
            screenID: screen.id,
            styles: settings.annotationStyles,
            cursor: ScreenTopologyProvider.toGlobal(NSEvent.mouseLocation),
            tool: tool)
        let services = translationServices
        let overlay = overlayFactory(capture, session.settingTranslationAvailable(services != nil), self)
        if let services {
            overlay.attachTranslation(services)
        }
        overlay.attachHistoryEdit(historyEditContext(source, layout: layout))
        state = .presenting(
            Presentation(
                overlay: overlay, capture: capture, windowSource: windowSource,
                screens: ScreenTopologyProvider.screens()))
        historyEdit = HistoryImageEditSession(overlay: overlay, source: source, layout: layout, onFinish: onFinish)
        overlay.present()
        logger.notice("History image edit shown at \(layout.zoomPercent, privacy: .public)%")
        return true
    }

    private func historyEditContext(_ source: HistoryImageEditSource, layout: HistoryImageLayout)
        -> HistoryEditContext
    {
        let nativeScreen = CaptureScreen(id: source.screen.id, frame: layout.nativeRect, scale: layout.nativeScale)
        let item = source.item
        let time = item.createdAt.formatted(date: .omitted, time: .shortened)
        let detail = String(
            localized: "\(String(source.image.width)) × \(String(source.image.height)) · hung at \(time)",
            comment: "Clothesline image editor header: image size in pixels and the time the item was copied")
        return HistoryEditContext(
            nativeFrame: FrozenFrame(screen: nativeScreen, image: source.image),
            pngScale: source.dpiScale,
            layout: layout,
            icon: ImageCache.shared.appIcon(bundleID: item.source?.bundleID, pointSize: HistoryEditTokens.iconSize),
            title: item.source?.name ?? TextStats.unknownSource,
            detail: detail,
            onZoom: { [weak self] direction in self?.rezoomHistoryEdit(direction) }
        )
    }

    /// − / +：以新的缩放重建覆盖层（只在还没有标注时允许，标注是按屏幕点存的）
    private func rezoomHistoryEdit(_ direction: Int) {
        guard case .presenting(let presentation) = state, let edit = historyEdit,
            edit.overlay === presentation.overlay, !edit.overlay.hasAnnotations, !edit.overlay.isFinishing
        else { return }
        let zoom = edit.layout.steppedZoom(direction)
        guard abs(zoom - edit.layout.zoom) > 0.0001 else { return }
        let tool = (edit.overlay as? ScreenshotOverlayController)?.session.tool ?? .rectangle
        historyEdit = nil
        state = .idle
        edit.overlay.dismiss()
        if !presentHistoryEdit(edit.source, zoom: zoom, tool: tool, onFinish: edit.onFinish) {
            edit.onFinish(.cancelled)
        }
    }

    // MARK: - 结果

    /// 该覆盖层是不是晾衣绳放大编辑（它的输出不再自动挂到晾衣绳）
    func isEditingHistoryImage(in overlay: any ScreenshotOverlayPresenting) -> Bool {
        historyEdit?.overlay === overlay
    }

    /// 取出属于该覆盖层的放大编辑（取出后不再回调第二次）
    func takeHistoryEdit(for overlay: any ScreenshotOverlayPresenting) -> HistoryImageEditSession? {
        guard let edit = historyEdit, edit.overlay === overlay else { return nil }
        historyEdit = nil
        return edit
    }

    /// 不经过 didFinishWith 结束的放大编辑（存储、翻译设置期间布局变化）
    func finishHistoryEdit(of overlay: any ScreenshotOverlayPresenting, with result: HistoryImageEditResult) {
        takeHistoryEdit(for: overlay)?.onFinish(result)
    }

    func handleHistoryEdit(_ result: ScreenshotResult, edit: HistoryImageEditSession, presentation: Presentation) {
        switch result {
        case .cancel:
            edit.onFinish(.cancelled)
        case .copy(let export):
            output.copy(export, hangsOnClothesline: false)
            edit.onFinish(.copied)
        case .hangBack(let export):
            let source = edit.source.item.source
            Task { [weak self] in
                guard let self else { return }
                let record = await self.output.recordHistoryImage(export, source: source)
                self.hungBack(record, export: export, edit: edit)
            }
        case .failed(let failure):
            logger.error("History image edit failed: \(String(describing: failure), privacy: .public)")
            warn(String(localized: "Couldn't create the screenshot", comment: "HUD when exporting a screenshot fails"))
            edit.onFinish(.cancelled)
        case .pin(let export):
            output.pin(export, hangsOnClothesline: false)
            edit.onFinish(.other)
        case .extractText, .copyColor, .translatedText, .captureWindow:
            handle(result, presentation: presentation)
            edit.onFinish(.other)
        }
    }

    /// 晾回的结果：没存进历史时提示原因（原图仍在绳上）
    private func hungBack(
        _ record: ScreenshotOutputService.HistoryImageRecord,
        export: ScreenshotExport,
        edit: HistoryImageEditSession
    ) {
        guard case .recorded(let id) = record else {
            logger.notice("Annotated history image not saved: \(String(describing: record), privacy: .public)")
            warn(Self.notSavedMessage(record))
            edit.onFinish(.notSaved)
            return
        }
        edit.onFinish(.hungBack(id))
    }

    private static func notSavedMessage(_ record: ScreenshotOutputService.HistoryImageRecord) -> String {
        switch record {
        case .paused:
            String(
                localized: "Not saved: recording is paused",
                comment: "HUD when Done & Hang Back can't add the annotated image to the history")
        case .tooLarge:
            String(
                localized: "Not saved: too large for history",
                comment: "HUD when Done & Hang Back can't add the annotated image to the history")
        case .failed, .recorded:
            String(
                localized: "Couldn't save the image to history",
                comment: "HUD when Done & Hang Back fails to write the annotated image")
        }
    }
}
