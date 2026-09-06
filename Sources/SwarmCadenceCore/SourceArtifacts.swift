import Foundation
import GRDB

struct SourceValidationError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct ValidatedV2Source {
    let manifest: RawFetchManifest
    let data: Data
    let items: [[String: Any]]
    let rawURL: URL

    static func read(manifestURL: URL, expectedAccount: String?) throws -> ValidatedV2Source {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest: RawFetchManifest
        do { manifest = try decoder.decode(RawFetchManifest.self, from: Data(contentsOf: manifestURL)) }
        catch { throw SourceValidationError("\(manifestURL.lastPathComponent): manifest could not be decoded") }
        guard manifest.schemaVersion == 1, manifest.adapter == .v2 else {
            throw SourceValidationError("unsupported manifest schema or adapter")
        }
        _ = try AccountID(manifest.account)
        if let expectedAccount, expectedAccount != manifest.account {
            throw SourceValidationError("manifest account \(manifest.account) does not match requested account \(expectedAccount)")
        }
        guard !manifest.rawFileName.isEmpty, manifest.rawFileName == URL(fileURLWithPath: manifest.rawFileName).lastPathComponent else {
            throw SourceValidationError("manifest raw filename must be a sibling filename")
        }
        let rawURL = manifestURL.deletingLastPathComponent().appendingPathComponent(manifest.rawFileName)
        guard FileManager.default.fileExists(atPath: rawURL.path) else { throw SourceValidationError("matching raw file is missing") }
        let data = try Data(contentsOf: rawURL)
        guard data.count == manifest.rawBytes else { throw SourceValidationError("raw byte count does not match manifest") }
        guard RawFetch.sha256Hex(data) == manifest.rawSha256 else { throw SourceValidationError("raw sha256 does not match manifest") }
        guard (200..<300).contains(manifest.httpStatusCode),
              manifest.apiMetaCode.map({ (200..<300).contains($0) }) ?? true,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = object["response"] as? [String: Any],
              let checkins = response["checkins"] as? [String: Any],
              let items = checkins["items"] as? [[String: Any]] else {
            throw SourceValidationError("successful raw response.checkins.items was not present")
        }
        return ValidatedV2Source(manifest: manifest, data: data, items: items, rawURL: rawURL)
    }
}

/// Existing raw_files IDs remain stable. New identities are content-addressed and
/// account-scoped; legacy rows are never retroactively declared verified.
enum SourceArtifacts {
    static func identity(account: String, adapter: String, sha256: String) -> String {
        "artifact:\(account):\(adapter):\(sha256)"
    }
    static func observe(db: Database, rawFileID: Int, path: String, fetchedAt: String?, importedAt: String?) throws {
        let key = RawFetch.sha256Hex(Data("\(rawFileID)\n\(path)\n\(fetchedAt ?? "offline")".utf8))
        try db.execute(sql: """
            INSERT INTO source_observations(observation_key, raw_file_id, source_path, fetched_at, imported_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(observation_key) DO UPDATE SET imported_at = COALESCE(excluded.imported_at, source_observations.imported_at)
            """, arguments: [key, rawFileID, path, fetchedAt, importedAt])
    }
    static func requireOwnership(db: Database, checkinID: String, account: String) throws {
        if let owner = try String.fetchOne(db, sql: "SELECT account FROM checkins WHERE checkin_id = ?", arguments: [checkinID]), owner != account {
            throw CLIError("check-in ownership conflicts with requested account; import rolled back.")
        }
    }
}

struct ValidatedExportSource {
    let data: Data
    let items: [[String: Any]]
    let totalCount: Int
    static func read(_ fileURL: URL) throws -> ValidatedExportSource {
        let data = try Data(contentsOf: fileURL)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else {
            throw SourceValidationError("export checkins file could not be decoded")
        }
        return ValidatedExportSource(data: data, items: items, totalCount: object["count"] as? Int ?? items.count)
    }
}
