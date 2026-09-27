import Foundation
import os

extension ClipStore {
    /// 启动时读取历史遇到的问题，供界面向用户说明原因
    public enum LoadIssue: Equatable, Sendable {
        /// 历史文件损坏：已移至 backupURL，本次从空历史开始并正常写盘
        case restoredFromCorruption(backupURL: URL)
        /// 历史文件由更新版本的 Cubby 写入（关联值为文件中的版本号）：本次运行只读，不改动原文件
        case newerVersion(Int)
        /// 读取失败（权限、磁盘等）：本次运行只读，避免用空数据覆盖已有历史
        case unreadable

        /// 出现该问题时本次运行是否仍可写盘
        var allowsPersistence: Bool {
            switch self {
            case .restoredFromCorruption: true
            case .newerVersion, .unreadable: false
            }
        }
    }

    /// 启动加载的结果
    struct InitialLoad {
        let history: ClipHistory
        let issue: LoadIssue?
        /// 数据由旧格式迁移而来，需要以当前格式重新保存
        let needsResave: Bool

        var canPersist: Bool {
            issue?.allowsPersistence ?? true
        }

        static func failed(_ issue: LoadIssue) -> InitialLoad {
            InitialLoad(history: .empty, issue: issue, needsResave: false)
        }
    }

    static func loadInitialHistory(from storage: HistoryPersisting, logger: Logger) -> InitialLoad {
        do {
            let outcome = try storage.loadReportingMigration()
            if outcome.didMigrate {
                logger.info(
                    "Migrated history file from v\(outcome.sourceVersion) to v\(HistoryMigrator.currentVersion)"
                )
            }
            return InitialLoad(history: outcome.history, issue: nil, needsResave: outcome.didMigrate)
        } catch HistoryStorageError.corrupted(let backupURL) {
            logger.error("History file is corrupted, backed up to \(backupURL.path, privacy: .public)")
            return .failed(.restoredFromCorruption(backupURL: backupURL))
        } catch HistoryStorageError.unsupportedVersion(let found) {
            logger.error(
                "History file v\(found) is newer than supported v\(HistoryMigrator.currentVersion), read-only"
            )
            return .failed(.newerVersion(found))
        } catch {
            logger.error("Failed to read history, not saving: \(error.localizedDescription, privacy: .public)")
            return .failed(.unreadable)
        }
    }
}
