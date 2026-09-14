import Foundation
import SwiftData
import os

public enum TempoSharedStore {
    public static let appGroupID = "group.com.ayipocket.tempo"
    public static let databaseName = "Tempo"

    public static func makeModelContainer() -> ModelContainer {
        let schema = Schema([StressEntry.self, MoodEntry.self, MentalHealthSurveyResult.self])

        // Tier 1: App Group 共享 store(主 App + Widget + Siri 三方共享)
        // 显式 cloudKitDatabase: .none 禁止 SwiftData 自动 iCloud 同步 — Tempo 用 CloudKit 给 Friends 服务,不是 SwiftData.
        if let url = sharedStoreURL() {
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
            // 失败可能是 schema 不兼容老 store → 删旧文件重建
            tryDeleteStore(at: url)
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }

        // Tier 2: 默认沙盒位置(主 App 单独可用,Widget 看不到)
        let sandboxConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [sandboxConfig]) {
            return container
        }
        // 默认沙盒失败 → 删默认 store 文件重建
        tryDeleteDefaultStores()
        if let container = try? ModelContainer(for: schema, configurations: [sandboxConfig]) {
            return container
        }

        // Tier 3: 内存(数据无法持久化,但避免启动崩溃)
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
            )
        } catch {
            // 真到这一步说明设备 SwiftData 完全坏了(连 in-memory 都建不了),App 实际无法继续运行。
            // 不能 return nil(makeModelContainer 已经被多个 entrypoint 当 non-optional 用,改 optional 是大重构)
            // 至少把 error 详情写到 os.Logger 让 crashlog 里能看到根因
            let logger = Logger(subsystem: "com.ayipocket.tempo", category: "Storage")
            logger.fault("FATAL: failed to create even in-memory ModelContainer: \(String(describing: error))")
            fatalError("Failed to create even in-memory ModelContainer: \(error)")
        }
    }

    /// Optional 变体 —— 上层若想优雅降级(显示「数据库不可用」兜底页)可调这个。
    /// 极低概率失败(已经 5 层 fallback),实际 release 几乎不会触发。
    public static func tryMakeModelContainer() -> ModelContainer? {
        let schema = Schema([StressEntry.self, MoodEntry.self, MentalHealthSurveyResult.self])
        if let url = sharedStoreURL(),
           let container = try? ModelContainer(for: schema,
               configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]) {
            return container
        }
        if let container = try? ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)]) {
            return container
        }
        return try? ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    private static func tryDeleteStore(at url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        // SQLite 三件套
        try? fm.removeItem(at: url.appendingPathExtension("shm"))
        try? fm.removeItem(at: url.appendingPathExtension("wal"))
        let withSuffix = url.deletingPathExtension()
        try? fm.removeItem(at: withSuffix.appendingPathExtension("sqlite-shm"))
        try? fm.removeItem(at: withSuffix.appendingPathExtension("sqlite-wal"))
    }

    private static func tryDeleteDefaultStores() {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: support.path) {
            for entry in entries where entry.hasSuffix(".sqlite") || entry.hasSuffix(".store") || entry.hasSuffix("-shm") || entry.hasSuffix("-wal") {
                try? FileManager.default.removeItem(at: support.appendingPathComponent(entry))
            }
        }
    }

    public static func sharedStoreURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("\(databaseName).sqlite")
    }
}
