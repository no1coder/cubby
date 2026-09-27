import Testing

/// 让访问系统剪贴板服务（pboard）的测试一次只跑一个。
///
/// 多个线程同时对剪贴板做同步 XPC 调用（创建命名剪贴板、clearContents、releaseGlobally、
/// 首次创建 NSApplication 时初始化通用剪贴板……）时，pboard 偶发不再回复这个进程的任何请求：
/// pboard 自身空闲，发起调用的线程全部卡在 `_CFPBXPCSendMessageWithReplySync`。
/// 协作线程池的宽度等于 CPU 核数（CI 上为 3），这些线程占满线程池后整个测试进程静默挂起，
/// 连测试运行器自己的输出也停了（CI 两次 30 分钟超时都停在测试开始后 1 秒内）。
/// 本地用 `taskpolicy -c background` 并行运行剪贴板相关测试可稳定复现（8 次挂起 3 次），
/// 串行运行 12 次从未复现。
///
/// 所有会触达 pboard 的套件都加上 `.serializedPasteboardAccess`：同一时刻只有一个测试用例访问剪贴板，
/// 其余测试照常并行。排队的测试在异步互斥上挂起、不占线程，不会反过来占满线程池。
/// 与 `.serialized` 不同，它跨套件生效（`.serialized` 只约束同一套件内的测试）。
struct SerializedPasteboardAccess: SuiteTrait, TestTrait, TestScoping {
    /// 当前任务是否已持有互斥
    @TaskLocal private static var isHeld = false

    var isRecursive: Bool { true }

    /// 只包住具体的测试用例；套件本身不持有互斥，否则套件与其中的测试会互相等待
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        // trait 被嵌套应用（例如套件与其中的测试都加了）时内层直接执行，避免同一任务自己等自己
        guard !Self.isHeld else {
            try await function()
            return
        }
        try await PasteboardAccessGate.shared.run {
            try await Self.$isHeld.withValue(true) { try await function() }
        }
    }
}

extension Trait where Self == SerializedPasteboardAccess {
    /// 跨套件串行访问系统剪贴板（原因见 `SerializedPasteboardAccess`）
    static var serializedPasteboardAccess: Self { Self() }
}

/// 先到先得的异步互斥：等待方挂起而不阻塞线程
actor PasteboardAccessGate {
    static let shared = PasteboardAccessGate()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(_ body: @Sendable () async throws -> Void) async throws {
        await acquire()
        defer { release() }
        try await body()
    }

    private func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// 有人排队时直接把互斥交给队首（isHeld 保持为 true），否则释放
    private func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
}
