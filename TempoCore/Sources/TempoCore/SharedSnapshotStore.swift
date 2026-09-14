//
//  SharedSnapshotStore.swift
//  TempoCore
//
//  Phone 主 App ↔ Widget Extension ↔ Watch App 之间共享 WatchSnapshot 的「快照文件」。
//
//  设计:
//   - App Group 容器下放一个 widget-snapshot.json
//   - Phone HomeView.loadHKData 算完后 write
//   - Widget Timeline Provider 在 getTimeline 时 read(同步、毫秒级)
//   - 写入用 atomic write,避免 Widget 读到半截 JSON
//
//  为什么不用 SwiftData?— Widget 用 SwiftData 启动开销大、有崩溃风险,
//  小文件 JSON 是 Apple 自己也推荐给 Widget 用的方式。
//

import Foundation

public enum SharedSnapshotStore {
    public static let appGroupID = "group.com.ayipocket.tempo"
    public static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    // MARK: - Write(Phone 端)

    @discardableResult
    public static func write(_ snapshot: WatchSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Read(Widget / Watch / 其他读方)

    public static func read() -> WatchSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchSnapshot.self, from: data)
    }

    /// 异步版 — Phone HomeView 等主线程场景使用,把磁盘 IO 移到后台队列。
    /// Widget Provider 保留同步 `read()`(WidgetKit 本身就是同步流程)。
    public static func readAsync() async -> WatchSnapshot? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: Self.read())
            }
        }
    }

    /// 文件是否存在且 < 24h(用于判断 widget 是否该显示 mock)
    public static var hasFreshFile: Bool {
        guard let url = fileURL else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modDate) < 24 * 3600
    }

    public static func deleteFile() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
