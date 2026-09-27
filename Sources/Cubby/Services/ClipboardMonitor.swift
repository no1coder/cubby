import AppKit
import CubbyCore

/// 轮询系统剪贴板的 changeCount，发现变化时读取内容并回调。
/// 主线程上只取数据并校验 changeCount；只有 TIFF 的图片以原始字节交出，转码由后台完成
@MainActor
final class ClipboardMonitor {
    typealias Handler = (PasteboardCapture, SourceApp?) -> Void

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let handler: Handler
    private var timer: Timer?
    private var lastChangeCount: Int
    /// 轮询所在的运行循环模式（刻意排除 modalPanel，见 start() 中的说明）
    static let runLoopModes: [RunLoop.Mode] = [.default, .eventTracking]

    init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.5, handler: @escaping Handler) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.handler = handler
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval * 0.2
        // 只挂 default 与 eventTracking（菜单展开、拖拽期间仍能监听），**不能用 .common**：
        // macOS 15.4+ 剪贴板隐私为「询问」时，系统询问框是本进程内的模态框（modalPanel 模式）且占着剪贴板内部队列，
        // 计时器若在模态循环里重入读取 changeCount 会触发 libdispatch 断言崩溃，后台读取路径则会死锁
        for mode in Self.runLoopModes {
            RunLoop.main.add(timer, forMode: mode)
        }
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard !PasteboardReader.shouldIgnore(pasteboard),
            let capture = PasteboardReader.capture(from: pasteboard),
            // 读取期间剪贴板又被改写时丢弃本次结果，下一轮轮询会读取最新内容
            pasteboard.changeCount == changeCount
        else { return }
        handler(capture, Self.frontmostSource())
    }

    private static func frontmostSource() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}
