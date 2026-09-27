import AppKit
import CubbyCore
import ImageIO
import os
import UniformTypeIdentifiers

/// 缩略图与图标缓存：缩略图按实际内存占用限额、在后台限流解码，面板隐藏一段时间后清空
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    /// 缩略图缓存上限，按实际内存计。每张上屏的位图还对应一份等大的 CoreAnimation 渲染副本，
    /// 寿命跟随位图（剖析实测滚完全部图片后 CA 132MB + CG raster 129MB），所以成本按位图的 2 倍计。
    /// 64MB 实际内存 ≈ 32MB 位图 ≈ 29 张卡片缩略图（720×405）或 5 张 1600px 预览图，远多于一屏；
    /// 剖析中同样的有效上限使滚完 2000 条后的 footprint 从 397MB 降到 153MB，滚动帧 p95 不变
    private static let thumbnailCostLimit = 64 * 1024 * 1024
    private static let renderCopyFactor = 2
    /// 同时解码的缩略图数：5K 图单张解码 70–150ms、瞬时占用可达数十 MB；
    /// 并发 20 张时峰值 +121MB 而墙钟并不更短，限到 3 张后一屏的图约两轮解完
    private static let maxConcurrentDecodes = 3

    private let thumbnails = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()
    private let decodeGate: DecodeGate
    /// 解码中的图：快速滚动时同一张图只解码一次，后来的请求等待同一结果
    private var inFlight: [NSString: PendingDecode] = [:]
    private var purgeTask: Task<Void, Never>?

    private init() {
        decodeGate = DecodeGate(limit: Self.maxConcurrentDecodes)
        thumbnails.totalCostLimit = Self.thumbnailCostLimit
        icons.countLimit = 300
    }

    func cachedThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        thumbnails.object(forKey: Self.key(url, maxPixelSize))
    }

    /// 按最长边像素生成缩略图；大图不会整张解码进内存。
    /// 解码在调用方（视图的 .task）的任务里排队等许可：视图消失、任务取消时，排队中的请求立即放弃、不再解码。
    /// 已开始的解码是一次无法中断的 ImageIO 同步调用，完成后照常写入缓存，卡片滑回时直接命中
    func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = Self.key(url, maxPixelSize)
        if let cached = thumbnails.object(forKey: key) { return cached }
        if let pending = inFlight[key] { return await pending.result() }

        guard await decodeGate.acquire() else { return nil }
        // 排队期间可能已被取消，或同一张图已由其他请求解出 / 正在解码
        guard !Task.isCancelled, thumbnails.object(forKey: key) == nil, inFlight[key] == nil else {
            decodeGate.release()
            if let cached = thumbnails.object(forKey: key) { return cached }
            guard !Task.isCancelled, let pending = inFlight[key] else { return nil }
            return await pending.result()
        }

        let pending = PendingDecode()
        inFlight[key] = pending
        let decoded = await Self.decodeThumbnail(url: url, maxPixelSize: maxPixelSize)
        let image = decoded.map { store($0, key: key) }
        inFlight[key] = nil
        decodeGate.release()
        pending.finish(image)
        return image
    }

    /// 面板隐藏后延迟清空缩略图：NSCache 不会主动释放，常驻菜单栏期间这部分内存没有用处。
    /// 期间再次呼出会取消清理（cancelScheduledPurge），马上重开时缩略图仍在
    func purgeThumbnails(after delay: Duration) {
        purgeTask?.cancel()
        purgeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.thumbnails.removeAllObjects()
            self.purgeTask = nil
        }
    }

    func cancelScheduledPurge() {
        purgeTask?.cancel()
        purgeTask = nil
    }

    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        let key = "app:\(bundleID)" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: key)
        return icon
    }

    /// 指定点尺寸的应用图标（嵌入 Text 时按 NSImage 的 size 渲染，因此需要单独缩放）；未安装时为通用应用图标
    func appIcon(bundleID: String?, pointSize: CGFloat) -> NSImage {
        let key = "app:\(bundleID ?? "-")@\(pointSize)" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let source = appIcon(bundleID: bundleID) ?? genericAppIcon
        // 复制后再改尺寸，不影响缓存中的原图；多分辨率表示仍保留，绘制时自动选用合适的一档
        guard let sized = source.copy() as? NSImage else { return source }
        sized.size = NSSize(width: pointSize, height: pointSize)
        icons.setObject(sized, forKey: key)
        return sized
    }

    let genericAppIcon = NSWorkspace.shared.icon(for: .applicationBundle)

    func fileIcon(path: String) -> NSImage {
        let key = "file:\(path)" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(icon, forKey: key)
        return icon
    }

    private static func key(_ url: URL, _ maxPixelSize: Int) -> NSString {
        "\(url.path)#\(maxPixelSize)" as NSString
    }

    /// 写入缓存，成本按位图字节数 × 渲染副本系数计
    private func store(_ decoded: CGImage, key: NSString) -> NSImage {
        let image = NSImage(cgImage: decoded, size: .zero)
        thumbnails.setObject(image, forKey: key, cost: decoded.bytesPerRow * decoded.height * Self.renderCopyFactor)
        return image
    }

    /// 在全局并发执行器上解码（@concurrent：离开主线程），但仍属于调用方的任务，
    /// 不再像 Task.detached 那样脱离视图 .task 的取消。
    /// 这里不检查取消：能走到这一步的请求已拿到许可且未取消，而同一张图的等待者依赖它的结果，
    /// 中途放弃会让等待者拿到 nil 且不再重试。
    /// 卡片请求优先读记录时预生成的小缩略图（720px JPEG 解码不到 1ms）；没有或不够大（预览面板的 1600px）时解码原图
    @concurrent
    private nonisolated static func decodeThumbnail(url: URL, maxPixelSize: Int) async -> CGImage? {
        if let small = ImageThumbnail.decode(forImageAt: url, maxPixelSize: maxPixelSize) { return small }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// 同一张图的一次解码：发起者解完后把结果交给期间加入等待的请求
@MainActor
private final class PendingDecode {
    private var waiters: [CheckedContinuation<NSImage?, Never>] = []

    /// 不响应取消：已取消的等待者最多再等一次解码（≤150ms），结果照常写入缓存
    func result() async -> NSImage? {
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ image: NSImage?) {
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume(returning: image)
        }
    }
}

/// 解码并发闸门：最多 limit 个请求同时持有许可，其余按先后排队；
/// 排队中的请求在所属任务被取消时立即以 false 返回，不占用许可
private final class DecodeGate: Sendable {
    private struct Waiter: Sendable {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct State: Sendable {
        var available: Int
        var nextID: UInt64 = 0
        var waiters: [Waiter] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(limit: Int) {
        state = OSAllocatedUnfairLock(initialState: State(available: limit))
    }

    /// 取得许可返回 true（用完须 release）；排队期间所属任务被取消返回 false
    func acquire() async -> Bool {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // 取消标记先于 onCancel 设置：无论两者谁先拿到锁，排队中的请求都不会漏掉取消
                let granted: Bool? = state.withLock { state in
                    if Task.isCancelled { return false }
                    if state.available > 0 {
                        state.available -= 1
                        return true
                    }
                    state.waiters.append(Waiter(id: id, continuation: continuation))
                    return nil
                }
                if let granted { continuation.resume(returning: granted) }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Waiter? in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiters.remove(at: index)
            }
            cancelled?.continuation.resume(returning: false)
        }
    }

    /// 归还许可：有人排队时直接转交给最早的一个
    func release() {
        let next = state.withLock { state -> Waiter? in
            guard !state.waiters.isEmpty else {
                state.available += 1
                return nil
            }
            return state.waiters.removeFirst()
        }
        next?.continuation.resume(returning: true)
    }
}
