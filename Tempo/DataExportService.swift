//
//  DataExportService.swift
//  Tempo
//

import Foundation
import TempoCore

enum DataExportService {
    static func exportCSV(entries: [StressEntry]) -> URL? {
        var csv = "timestamp,bpm,hrv,score,level\n"
        let formatter = ISO8601DateFormatter()
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let ts = formatter.string(from: entry.timestamp)
            let hrvStr = entry.hrv.map { String(format: "%.1f", $0) } ?? ""
            csv += "\(ts),\(entry.bpm),\(hrvStr),\(entry.scoreValue),\(entry.levelRaw)\n"
        }
        guard let data = csv.data(using: .utf8) else { return nil }
        return write(data, fileName: "Tempo-\(timestampSuffix()).csv")
    }

    static func exportJSON(entries: [StressEntry]) -> URL? {
        let exports = entries.sorted(by: { $0.timestamp < $1.timestamp }).map {
            ExportEntry(
                timestamp: $0.timestamp,
                bpm: $0.bpm,
                hrv: $0.hrv,
                score: $0.scoreValue,
                level: $0.levelRaw
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(exports) else { return nil }
        return write(data, fileName: "Tempo-\(timestampSuffix()).json")
    }

    private struct ExportEntry: Codable {
        let timestamp: Date
        let bpm: Double
        let hrv: Double?
        let score: Int
        let level: String
    }

    private static func timestampSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    private static func write(_ data: Data, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
