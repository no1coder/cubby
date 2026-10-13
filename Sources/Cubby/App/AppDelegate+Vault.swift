import CubbyCore

// 加密 Vault 的接线（docs/HISTORY-ENCRYPTION-DESIGN.md E6、E8）：
// ClipStore 先以内存模式创建，VaultCoordinator 在后台解析密钥、处理 E8 ②、迁移明文，就绪后把它切换为加密存储。
// 准备期间复制的内容记在内存里，就绪时并入加密历史（与锁定后「重试」同一条路径）
extension AppDelegate {
    func makeStoreAndVault() -> ClipStore {
        let store = ClipStore(inMemoryWithLimit: settings.historyLimit)
        let vault = VaultCoordinator(store: store) { [settings] in settings.historyLimit }
        vault.onReady = { [weak self] session in self?.vaultDidBecomeReady(session) }
        self.vault = vault
        return store
    }

    /// Vault 就绪、ClipStore 已切换为加密存储：接上安全记录，开始文字识别与缩略图回填（锁定期间都不写盘）
    private func vaultDidBecomeReady(_ session: VaultLaunch.Session) {
        attachSecurityLog(keys: session.keys)
        imageTextIndexer?.start()
        store?.backfillThumbnails()
    }
}
