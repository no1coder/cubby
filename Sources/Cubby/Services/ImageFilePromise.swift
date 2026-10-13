import AppKit
import CubbyCore
import os
import UniformTypeIdentifiers

/// 拖出图片条目时交给拖拽会话的一项（docs/HISTORY-ENCRYPTION-DESIGN.md E9），同时提供：
/// - 文件承诺：访达等接受文件承诺的目标给出目标位置，由这里把解密后的 PNG 直接写过去，Cubby 不写临时明文副本；
/// - PNG / TIFF 数据：邮件、预览、文本编辑等接受图片数据的目标直接读取（只在目标真正索取时才解密）。
/// 不提供文件 URL：访达看到 URL 会改为复制那个文件，就又需要临时副本了
final class ImageFilePromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Drag")
    /// 写文件在后台队列上进行（大图解密 + 写盘不卡主线程）
    private static let writeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "io.github.no1coder.Cubby.file-promise"
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private static let fileExtension = "png"
    private static let dataTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    private let source: ClipImageSource
    /// 访达里显示的文件名：条目标题去掉路径分隔等字符
    let fileName: String

    init(source: ClipImageSource, title: String) {
        self.source = source
        self.fileName = SharedFileExport.fileName(title, fileExtension: Self.fileExtension)
        super.init()
        fileType = UTType.png.identifier
        // delegate 是弱引用：由自身充当，拖拽会话持有本对象期间一直有效
        delegate = self
    }

    // MARK: - 图片数据

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + Self.dataTypes
    }

    override func writingOptions(
        forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        // 图片数据延迟提供：只有目标真正读取时才解密
        Self.dataTypes.contains(type) ? .promised : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .png: imageData()
        case .tiff: imageData().flatMap { NSImage(data: $0)?.tiffRepresentation }
        default: super.pasteboardPropertyList(forType: type)
        }
    }

    /// 解密后的原图（PNG）；读不到时为 nil
    func imageData() -> Data? {
        do {
            return try source.data()
        } catch {
            Self.logger.error("Failed to read a dragged image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        completionHandler(Self.write(source, to: url))
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.writeQueue
    }

    /// 把原图解密后直接写到目标给出的位置；返回错误（成功为 nil）
    static func write(_ source: ClipImageSource, to url: URL) -> (any Error)? {
        do {
            try source.data().write(to: url, options: .withoutOverwriting)
            return nil
        } catch {
            logger.error("Failed to fulfil a file promise: \(error.localizedDescription, privacy: .public)")
            return error
        }
    }
}
