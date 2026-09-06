import Foundation
import GRDB

public struct SourceSyncState: Codable, Equatable {
    public let lastAttemptAt: String?
    public let lastSuccessfulCheckAt: String?
    public let lastRunStatus: String?
    public let recentSyncComplete: Bool
    public let historyCoverage: String
    public let historyVerifiedAsOf: String?
    public let nextOffsetHint: Int?
}

enum SyncState {
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func begin(dbPath: String, account: String, adapter: String, now: Date) throws -> String {
        let id = UUID().uuidString
        let queue = try SwarmDatabase.openDatabase(path: dbPath)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO ingestion_runs(id, account, adapter, started_at, status) VALUES (?, ?, ?, ?, 'running')",
                           arguments: [id, account, adapter, timestamp(now)])
        }
        return id
    }
    static func checked(dbPath: String, runID: String, at: String) throws {
        let queue = try SwarmDatabase.openDatabase(path: dbPath)
        try queue.write { db in
            try db.execute(sql: "UPDATE ingestion_runs SET last_successful_check_at = ? WHERE id = ?", arguments: [at, runID])
        }
    }
    static func finish(dbPath: String, runID: String, status: String, complete: Bool, historyVerified: Bool, nextOffset: Int) throws {
        let queue = try SwarmDatabase.openDatabase(path: dbPath)
        try queue.write { db in
            try db.execute(sql: """
                UPDATE ingestion_runs SET status = ?, recent_complete = ?, history_verified = ?, next_offset_hint = ? WHERE id = ?
                """, arguments: [status, complete, historyVerified, nextOffset, runID])
        }
    }
    static func abandonIfRunning(dbPath: String, runID: String) throws {
        let queue = try SwarmDatabase.openDatabase(path: dbPath)
        try queue.write { db in
            try db.execute(sql: "UPDATE ingestion_runs SET status = 'failed' WHERE id = ? AND status = 'running'", arguments: [runID])
        }
    }
    static func read(db: Database, account: String?, adapter: String?) throws -> SourceSyncState {
        guard try db.tableExists("ingestion_runs") else {
            return SourceSyncState(lastAttemptAt: nil, lastSuccessfulCheckAt: nil, lastRunStatus: nil,
                recentSyncComplete: false, historyCoverage: "unknown", historyVerifiedAsOf: nil, nextOffsetHint: nil)
        }
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM ingestion_runs WHERE (? IS NULL OR account = ?) AND (? IS NULL OR adapter = ?)
            ORDER BY started_at DESC, rowid DESC
            """, arguments: [account, account, adapter, adapter])
        let last = rows.first
        let successful = rows.compactMap { $0["last_successful_check_at"] as String? }.max()
        let verified = rows.filter { ($0["history_verified"] as Bool) }.compactMap { $0["last_successful_check_at"] as String? }.max()
        // Aggregate queries never claim that one account's traversal covers all accounts.
        let scoped = account != nil
        return SourceSyncState(lastAttemptAt: last?["started_at"], lastSuccessfulCheckAt: successful,
            lastRunStatus: last?["status"], recentSyncComplete: scoped && (last?["recent_complete"] ?? false),
            historyCoverage: scoped && verified != nil ? "verified_as_of" : (rows.isEmpty ? "unknown" : "partial"),
            historyVerifiedAsOf: scoped ? verified : nil, nextOffsetHint: scoped ? last?["next_offset_hint"] : nil)
    }
}
