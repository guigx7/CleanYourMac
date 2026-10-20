import Foundation

public struct CleanReport: Codable, Sendable, Equatable {
    public let freedBytes: Int64
    public let removed: [String]
    /// id do item → motivo
    public let failed: [String: String]
    public let dryRun: Bool
    public let date: Date

    public init(freedBytes: Int64, removed: [String], failed: [String: String], dryRun: Bool, date: Date = Date()) {
        self.freedBytes = freedBytes
        self.removed = removed
        self.failed = failed
        self.dryRun = dryRun
        self.date = date
    }
}

/// Grava um JSON por limpeza (padrão: ~/Library/Logs/CleanYourMac/).
public struct CleanupLog: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: CleanupLog {
        CleanupLog(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CleanYourMac"))
    }

    @discardableResult
    public func write(_ report: CleanReport) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: report.date).replacingOccurrences(of: ":", with: "")
        var url = directory.appendingPathComponent("cleanup-\(stamp).json")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("cleanup-\(stamp)-\(n).json")
            n += 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url)
        return url
    }
}
