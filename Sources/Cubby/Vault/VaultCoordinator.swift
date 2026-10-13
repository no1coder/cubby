import CubbyCore
import Foundation
import Observation
import os

/// 加密 Vault 的状态：设置 › 历史的「加密」一行、面板的「已锁定」横幅与迁移占位据此显示（界面在 Phase 3）
enum VaultStatus: Equatable {
    /// 正在读取钥匙串（可能停在系统询问上）、准备 Vault
    case preparing
    /// 正在把明文历史加密进 Vault（已处理 / 总条目数）
    case migrating(done: Int, total: Int)
    /// 正常：历史加密保存
    case ready
    /// 无法取得密钥（E8 ①）：本次运行只在内存中记录，可 retryUnlock()
    case locked
    /// 本次启动找不到旧历史的密钥（E8 ②）：旧 Vault 已改名保留在该位置，从空历史重新开始
    case resetAfterMissingKey(URL)
    /// 密钥可用，但加密历史读不了（更新版本写入、读取错误）：本次运行只在内存中记录、不写盘，原文件不动
    case readOnly(ReadOnlyReason)

    enum ReadOnlyReason: Equatable {
        /// 历史由更新版本的 Cubby 写入
        case newerVersion
        /// 读取失败（权限、磁盘等）
        case unreadable
    }

    /// 还在准备中（面板显示占位、期间的记录先留在内存里）
    var isPreparing: Bool {
        switch self {
        case .preparing, .migrating: true
        case .ready, .locked, .resetAfterMissingKey, .readOnly: false
        }
    }
}

/// 启动时（及「重试」时）在后台解析密钥、处理 E8 ②、迁移明文，然后把内存模式的 ClipStore 切换为加密存储。
///
/// 准备期间的记录：ClipStore 一开始就以内存模式创建（空历史、什么都不写盘），准备期间复制的内容照常记录在内存里；
/// 就绪后 ClipStore.unlock 把它们并入加密历史（与锁定后重试是同一条路径）。面板因此从不显示过期数据，也不会崩溃
@MainActor
@Observable
final class VaultCoordinator {
    private(set) var status: VaultStatus = .preparing
    /// 数据目录中保留的、当前密钥解不开的旧 Vault（E8 ②，设置里「在访达中显示」）
    private(set) var unreadableFolders: [URL] = []
    /// 最近一次迁移失败（明文原样保留，下次启动重试）
    private(set) var migrationFailed = false

    /// 每次成功切换到加密存储后调用（接上安全记录、启动文字识别与缩略图回填）
    @ObservationIgnored var onReady: ((VaultLaunch.Session) -> Void)?

    @ObservationIgnored private let store: ClipStore
    @ObservationIgnored private let keySource: HistoryKeySource.Choice
    @ObservationIgnored private let dataDirectory: URL
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var settledWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")

    init(
        store: ClipStore,
        keySource: HistoryKeySource.Choice = HistoryKeySource.current,
        dataDirectory: URL = AppPaths.root
    ) {
        self.store = store
        self.keySource = keySource
        self.dataDirectory = dataDirectory
    }

    /// 启动时调用一次
    func start() {
        guard running == nil else { return }
        run()
    }

    /// 已锁定或历史读取失败时重来一次（用户点「重试」）；成功后合并内存中的条目、开启写盘
    func retryUnlock() {
        guard status == .locked || status == .readOnly(.unreadable), running == nil else { return }
        run()
    }

    /// 等到不再处于准备中（就绪、锁定或重置之后）
    func waitUntilSettled() async {
        guard status.isPreparing else { return }
        await withCheckedContinuation { settledWaiters.append($0) }
    }

    private func run() {
        status = .preparing
        let launch = VaultLaunch(
            dataDirectory: dataDirectory, provider: keySource.provider, allowsDestructiveSteps: !keySource.isEphemeral)
        let progress: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in self?.reportProgress(done: done, total: total) }
        }
        running = Task { [weak self] in
            let outcome = await Self.perform(launch, progress: progress)
            await self?.finish(outcome)
        }
    }

    /// 在后台执行器上运行（钥匙串可能阻塞在系统询问上，迁移要读写几十 MB）
    @concurrent
    private nonisolated static func perform(
        _ launch: VaultLaunch, progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> Result<VaultLaunch.Outcome, any Error> {
        Result { try launch.run(progress: progress) }
    }

    private func reportProgress(done: Int, total: Int) {
        guard status.isPreparing, running != nil else { return }
        status = .migrating(done: done, total: total)
    }

    private func finish(_ outcome: Result<VaultLaunch.Outcome, any Error>) async {
        switch outcome {
        case .success(.ready(let session)):
            await adopt(session)
        case .success(.locked):
            logger.error("History is locked: recording in memory only")
            status = .locked
        case .failure(let error):
            logger.error("Failed to prepare the vault: \(error.localizedDescription, privacy: .public)")
            status = .locked
        }
        running = nil
        unreadableFolders = VaultRecovery(dataDirectory: dataDirectory).unreadableFolders()
        let waiters = settledWaiters
        settledWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// 切换为加密存储（读写在后台进行）。历史读不了时保持内存模式：不接安全记录、不启动后续写盘的任务
    private func adopt(_ session: VaultLaunch.Session) async {
        let storage = EncryptedHistoryStorage(vaultDirectory: session.vault.url, keys: session.keys)
        let blobs = EncryptedBlobStore(directory: session.vault.blobsDirectory, keys: session.keys)
        let outcome = await store.unlock(
            storage: storage, blobs: blobs, knownCorruption: session.corruptedHistoryBackup)
        logger.info("Vault unlock: \(String(describing: outcome), privacy: .public)")
        migrationFailed = session.migrationFailed
        guard outcome != .readOnly else {
            status = .readOnly(store.loadIssue == .unreadable ? .unreadable : .newerVersion)
            return
        }
        status = session.quarantinedFolder.map(VaultStatus.resetAfterMissingKey) ?? .ready
        onReady?(session)
    }
}
