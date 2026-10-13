#if DEBUG
import AppKit
import CubbyCore

/// 历史加密（docs/HISTORY-ENCRYPTION-DESIGN.md §5 的面板 E2E 清单）：迁移占位、锁定横幅与重试、
/// 拖出图片交出可读的数据与文件（不写临时副本）；并检查数据目录里不再有能直接解析的 PNG / JSON
extension PanelE2EScenarios {
    static var vault: [PanelE2EScenario] {
        [vaultMigration, vaultLocked, vaultDrag]
    }

    static var vaultMigration: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.vault = PanelE2EWorld.VaultSetup(plaintextItems: 300, waitsAtGate: true)
        return PanelE2EScenario(
            name: "vault-migration",
            summary: "while the vault is preparing the list shows \"Encrypting your history…\" (after a short delay); "
                + "once ready the migrated items appear and no plaintext is left",
            options: options
        ) { context in
            let world = context.world
            guard let vault = world.vault, let gate = world.keyGate else { throw PanelE2EError.missingItem("vault") }
            vault.start()
            try await context.open()
            context.check("the vault is still preparing", vault.status.isPreparing)
            context.check("the placeholder is in the list area", context.hasAnchor("panel.vault-placeholder"))
            try await context.settle(.milliseconds(500))
            context.check("the placeholder shows after the delay", context.hasAnchor("panel.vault-placeholder.text"))
            gate.open()
            await context.eventually("the vault becomes ready", timeout: .seconds(15)) { vault.status == .ready }
            await context.eventually("the placeholder goes away") { !context.hasAnchor("panel.vault-placeholder") }
            context.checkEqual("all migrated items are listed", 300, context.viewModel.totalCount)
            context.check("migration didn't fail", !vault.migrationFailed)
            checkNoPlaintext(context, in: world.dataDirectory)
        }
    }

    static var vaultLocked: PanelE2EScenario {
        var options = PanelE2EWorld.Options()
        options.vault = PanelE2EWorld.VaultSetup(startsLocked: true)
        return PanelE2EScenario(
            name: "vault-locked",
            summary: "a denied keychain read shows \"History is locked\"; Try Again re-reads the key; Not Now hides "
                + "it for this run; once unlocked, items copied meanwhile are merged and saved",
            options: options
        ) { context in
            let world = context.world
            guard let vault = world.vault, let gate = world.keyGate else { throw PanelE2EError.missingItem("vault") }
            vault.start()
            await context.eventually("the vault is locked") { vault.status == .locked }
            let copied = world.store.record(.text("Copied while locked"), source: nil)
            try await context.open()
            let warnings = context.viewModel.visibleWarnings
            context.check("the locked banner is shown", warnings.contains(.historyLocked), detail: "\(warnings)")
            context.checkEqual("… with Try Again", EncryptionCopy.tryAgain, PanelWarning.historyLocked.actionTitle)
            context.check(
                "the item copied while locked is listed", copied.map { world.store.item(id: $0.id) != nil } ?? false)
            try await context.click("banner.locked.action")
            await context.eventually("Try Again while still denied locks again") { vault.status == .locked }
            context.check("… and the banner stays", context.viewModel.visibleWarnings.contains(.historyLocked))
            try await context.click("banner.locked.dismiss")
            await context.eventually("Not Now hides the banner") {
                !context.viewModel.visibleWarnings.contains(.historyLocked)
            }
            try await context.reopen()
            context.check("reopening keeps it hidden", !context.viewModel.visibleWarnings.contains(.historyLocked))
            gate.setLocked(false)
            vault.retryUnlock()
            await context.eventually("allowing the key unlocks the vault", timeout: .seconds(10)) {
                vault.status == .ready
            }
            context.check(
                "the item copied while locked is kept", copied.map { world.store.item(id: $0.id) != nil } ?? false)
            world.store.flush()
            let saved = VaultDirectory(
                url: world.dataDirectory.appendingPathComponent(VaultDirectory.defaultName, isDirectory: true))
            context.check(
                "the history is now saved encrypted",
                FileManager.default.fileExists(atPath: saved.historyURL.path))
            checkNoPlaintext(context, in: world.dataDirectory)
        }
    }

    static var vaultDrag: PanelE2EScenario {
        PanelE2EScenario(
            name: "vault-drag",
            summary: "dragging an image offers a file promise plus PNG / TIFF data (no file URL); fulfilling the "
                + "promise writes a readable PNG without leaving a temporary copy"
        ) { context in
            let item = try context.item("image")
            guard let source = context.world.store.imageSource(for: item) else {
                throw PanelE2EError.missingItem("image source")
            }
            let shared = SharedFileExport.temporary.root
            let sharedBefore = Self.fileCount(in: shared)
            let promise = ImageFilePromise(source: source, title: item.title)
            let types = promise.writableTypes(for: NSPasteboard(name: NSPasteboard.Name("cubby.e2e.drag")))
            context.check("the item offers PNG data", types.contains(.png), detail: "\(types)")
            context.check("… and TIFF data", types.contains(.tiff))
            context.check("… but no file URL (Finder would copy a temporary file)", !types.contains(.fileURL))
            let png = promise.pasteboardPropertyList(forType: .png) as? Data
            context.check("the PNG data decodes", png.flatMap(NSImage.init(data:)) != nil)
            let tiff = promise.pasteboardPropertyList(forType: .tiff) as? Data
            context.check("the TIFF data decodes", tiff.flatMap(NSImage.init(data:)) != nil)
            context.check("the promised file is named after the item", promise.fileName.hasSuffix(".png"))
            let destination = context.world.directory.appendingPathComponent("Dropped", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let target = destination.appendingPathComponent(promise.fileName)
            let error = ImageFilePromise.write(source, to: target)
            context.check("fulfilling the promise succeeds", error == nil, detail: "\(String(describing: error))")
            context.check("the dropped file is a readable image", NSImage(contentsOf: target) != nil)
            context.checkEqual("no temporary copy was written", sharedBefore, Self.fileCount(in: shared))
            checkNoPlaintext(context, in: context.world.directory.appendingPathComponent("Vault"))
        }
    }

    /// 数据目录里不再有能直接解析的 PNG / JSON（拖出测试的落点目录除外）
    private static func checkNoPlaintext(_ context: PanelE2EContext, in directory: URL) {
        let readable = Self.files(in: directory)
            .filter { !$0.path.contains("/Dropped/") && !$0.lastPathComponent.hasPrefix("defaults") }
            .filter { Self.isReadablePlaintext($0) }
        context.check(
            "the data folder has no readable PNG or JSON", readable.isEmpty,
            detail: readable.map(\.lastPathComponent).joined(separator: ", "))
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

    private static func isReadablePlaintext(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        if data.starts(with: pngSignature) { return true }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func files(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private static func fileCount(in directory: URL) -> Int {
        files(in: directory).count
    }
}
#endif
