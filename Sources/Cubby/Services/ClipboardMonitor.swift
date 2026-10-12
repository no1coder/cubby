import AppKit
import CubbyCore

/// 轮询系统剪贴板的 changeCount，发现变化时读取内容并回调。
/// 主线程上只取数据并校验 changeCount；只有 TIFF 的图片以原始字节交出，转码由后台完成
@MainActor
final class ClipboardMonitor {
    /// 内容、前台应用与这次变化的 changeCount（地址守护据此把替换与入历史的那一条配对）
    typealias Handler = (PasteboardCapture, SourceApp?, Int) -> Void

    /// 每一次剪贴板变化（在入历史的各项过滤之前）：地址守护用。text 只在内容不长时给出（敏感值都很短）
    struct Change {
        let text: String?
        /// Cubby 自己写入的：带本应用的写入标记，且 changeCount 是 Cubby 写入后记下的（OwnPasteboardWrites）
        let isOwnWrite: Bool
        let source: SourceApp?
        let changeCount: Int
    }

    /// 按下 ⌘C / ⌘X 后额外检查剪贴板的时刻（毫秒）：比平时 0.5 秒一次的轮询更早读到用户复制的值，
    /// 在后台程序换掉它之前开始守护
    static let keystrokePollDelays: [Int] = [30, 80, 150, 300, 600]

    /// 地址守护只看短文本：再长也不可能是地址或卡号
    static let maxObservedTextBytes = 1024

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let handler: Handler
    private var timer: Timer?
    private var lastChangeCount: Int
    /// 地址守护（AppDelegate 在守护开启时设置）；nil 时不额外读取文本
    var onChange: ((Change) -> Void)?
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
        let source = Self.frontmostSource()
        // 先交给地址守护：被忽略的应用、标记为机密的内容等不入历史的变化同样要比对
        onChange?(observedChange(source: source, changeCount: changeCount))

        guard !PasteboardReader.shouldIgnore(pasteboard),
            let capture = PasteboardReader.capture(from: pasteboard),
            // 读取期间剪贴板又被改写时丢弃本次结果，下一轮轮询会读取最新内容
            pasteboard.changeCount == changeCount
        else { return }
        handler(capture, source, changeCount)
    }

    /// 输入监控看到 ⌘C / ⌘X：在接下来的几个时刻各检查一次（没有变化时什么都不做，不影响平时的轮询）。
    /// 计时器同样只挂在 runLoopModes 上，不在模态循环里读剪贴板
    func pollSoon() {
        guard timer != nil else { return }
        for delay in Self.keystrokePollDelays {
            let check = Timer(timeInterval: TimeInterval(delay) / 1000, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            for mode in Self.runLoopModes {
                RunLoop.main.add(check, forMode: mode)
            }
        }
    }

    private func observedChange(source: SourceApp?, changeCount: Int) -> Change {
        let types = pasteboard.types ?? []
        let text = types.contains(.string) ? pasteboard.string(forType: .string) : nil
        return Change(
            text: text.flatMap { $0.utf8.count <= Self.maxObservedTextBytes ? $0 : nil },
            isOwnWrite: types.contains(PasteboardReader.markerType)
                && OwnPasteboardWrites.contains(changeCount, on: pasteboard),
            source: source, changeCount: changeCount)
    }

    private static func frontmostSource() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}
