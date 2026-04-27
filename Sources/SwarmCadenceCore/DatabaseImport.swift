import Foundation
import GRDB

public struct RawImportResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let dbPath: String
    public let rawDirectory: String
    public let rawFilesImported: Int
    public let rawFilesInserted: Int
    public let checkinsUpserted: Int
    public let checkinsInserted: Int
    public let venuesUpserted: Int
    public let venuesInserted: Int
    public let categoriesUpserted: Int
    public let categoriesInserted: Int
    public let skippedFiles: Int
    public let skippedCheckins: Int
    public let warnings: [String]
}

public struct DatabaseStatsResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let dbPath: String
    public let rawFiles: Int
    public let checkins: Int
    public let venues: Int
    public let categories: Int
    public let minCreatedAt: Int?
    public let maxCreatedAt: Int?
    public let oldestCreatedAtISO8601: String?
    public let latestCreatedAtISO8601: String?
}

public enum SwarmDatabase {
    public static func importRawV2Checkins(
        dbPath: String,
        rawDirectory: String,
        importedAt: Date = Date()
    ) throws -> RawImportResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        guard !rawDirectory.isEmpty else {
            throw CLIError("missing required --raw-dir <dir>.")
        }

        let rawDirectoryURL = URL(fileURLWithPath: rawDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rawDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError("--raw-dir does not exist or is not a directory: \(rawDirectory).")
        }

        let dbQueue = try openDatabase(path: dbPath)
        try migrate(dbQueue)

        let manifestURLs = try FileManager.default
            .contentsOfDirectory(at: rawDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".manifest.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let importedAtString = iso8601String(importedAt)
        var accumulator = ImportAccumulator()

        try dbQueue.write { db in
            for manifestURL in manifestURLs {
                do {
                    let imported = try importOneManifest(
                        db: db,
                        manifestURL: manifestURL,
                        rawDirectoryURL: rawDirectoryURL,
                        importedAt: importedAtString
                    )
                    accumulator.rawFilesImported += 1
                    accumulator.rawFilesInserted += imported.rawFileInserted ? 1 : 0
                    accumulator.checkinsUpserted += imported.checkinsUpserted
                    accumulator.checkinsInserted += imported.checkinsInserted
                    accumulator.venuesUpserted += imported.venuesUpserted
                    accumulator.venuesInserted += imported.venuesInserted
                    accumulator.categoriesUpserted += imported.categoriesUpserted
                    accumulator.categoriesInserted += imported.categoriesInserted
                    accumulator.skippedCheckins += imported.skippedCheckins
                } catch let error as RawImportSkip {
                    accumulator.skippedFiles += 1
                    accumulator.warnings.append("skipped manifest: \(error.message)")
                }
            }
        }

        return RawImportResult(
            schemaVersion: 1,
            command: "db import-raw",
            dbPath: dbPath,
            rawDirectory: rawDirectory,
            rawFilesImported: accumulator.rawFilesImported,
            rawFilesInserted: accumulator.rawFilesInserted,
            checkinsUpserted: accumulator.checkinsUpserted,
            checkinsInserted: accumulator.checkinsInserted,
            venuesUpserted: accumulator.venuesUpserted,
            venuesInserted: accumulator.venuesInserted,
            categoriesUpserted: accumulator.categoriesUpserted,
            categoriesInserted: accumulator.categoriesInserted,
            skippedFiles: accumulator.skippedFiles,
            skippedCheckins: accumulator.skippedCheckins,
            warnings: accumulator.warnings
        )
    }

    public static func stats(dbPath: String) throws -> DatabaseStatsResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }

        let dbQueue = try openDatabase(path: dbPath)
        try migrate(dbQueue)

        return try dbQueue.read { db in
            let minCreatedAt = try Int.fetchOne(db, sql: "SELECT MIN(created_at_unix) FROM checkins")
            let maxCreatedAt = try Int.fetchOne(db, sql: "SELECT MAX(created_at_unix) FROM checkins")

            return DatabaseStatsResult(
                schemaVersion: 1,
                command: "db stats",
                dbPath: dbPath,
                rawFiles: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM raw_files") ?? 0,
                checkins: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM checkins") ?? 0,
                venues: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM venues") ?? 0,
                categories: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0,
                minCreatedAt: minCreatedAt,
                maxCreatedAt: maxCreatedAt,
                oldestCreatedAtISO8601: minCreatedAt.map(iso8601String(timestamp:)),
                latestCreatedAtISO8601: maxCreatedAt.map(iso8601String(timestamp:))
            )
        }
    }

    private static func openDatabase(path: String) throws -> DatabaseQueue {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        if !directory.path.isEmpty {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try DatabaseQueue(path: path, configuration: configuration)
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_raw_v2_import") { db in
            try db.execute(sql: """
            CREATE TABLE raw_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                relative_path TEXT NOT NULL UNIQUE,
                raw_file_name TEXT NOT NULL,
                manifest_file_name TEXT NOT NULL,
                sha256 TEXT NOT NULL,
                bytes INTEGER NOT NULL,
                fetched_at TEXT NOT NULL,
                adapter TEXT NOT NULL,
                account TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                api_version TEXT NOT NULL,
                "limit" INTEGER NOT NULL,
                "offset" INTEGER NOT NULL,
                http_status INTEGER NOT NULL,
                api_meta_code INTEGER,
                returned_count INTEGER,
                total_count INTEGER,
                imported_at TEXT NOT NULL
            );

            CREATE TABLE venues (
                venue_id TEXT PRIMARY KEY,
                name TEXT,
                lat REAL,
                lng REAL,
                categories_json TEXT,
                raw_json TEXT,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE checkins (
                checkin_id TEXT PRIMARY KEY,
                account TEXT NOT NULL,
                source_adapter TEXT NOT NULL,
                created_at_unix INTEGER,
                created_at_iso TEXT,
                venue_id TEXT REFERENCES venues(venue_id),
                raw_file_id INTEGER NOT NULL REFERENCES raw_files(id),
                raw_json TEXT NOT NULL,
                imported_at TEXT NOT NULL
            );

            CREATE TABLE categories (
                category_id TEXT PRIMARY KEY,
                name TEXT,
                plural_name TEXT,
                short_name TEXT,
                icon_json TEXT,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE checkin_categories (
                checkin_id TEXT NOT NULL REFERENCES checkins(checkin_id) ON DELETE CASCADE,
                category_id TEXT NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
                venue_id TEXT REFERENCES venues(venue_id),
                account TEXT NOT NULL,
                raw_file_id INTEGER NOT NULL REFERENCES raw_files(id),
                ordinal INTEGER NOT NULL,
                PRIMARY KEY (checkin_id, category_id)
            );

            CREATE INDEX idx_checkins_account_created_at ON checkins(account, created_at_unix);
            CREATE INDEX idx_checkins_venue_id ON checkins(venue_id);
            CREATE INDEX idx_raw_files_account_offset ON raw_files(account, "offset");
            """)
        }
        try migrator.migrate(dbQueue)
    }

    private static func importOneManifest(
        db: Database,
        manifestURL: URL,
        rawDirectoryURL: URL,
        importedAt: String
    ) throws -> ManifestImportCounts {
        let manifest: RawFetchManifest
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            manifest = try decoder.decode(RawFetchManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw RawImportSkip("manifest could not be decoded")
        }

        guard manifest.adapter == .v2 else {
            throw RawImportSkip("only v2 raw files can be imported")
        }

        let rawURL = rawDirectoryURL.appendingPathComponent(manifest.rawFileName)
        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw RawImportSkip("matching raw file is missing")
        }

        let rawData = try Data(contentsOf: rawURL)
        guard rawData.count == manifest.rawBytes else {
            throw RawImportSkip("raw byte count does not match manifest")
        }
        guard RawFetch.sha256Hex(rawData) == manifest.rawSha256 else {
            throw RawImportSkip("raw sha256 does not match manifest")
        }

        let envelope = try parseEnvelope(rawData)
        let existingRawFileID = try Int.fetchOne(
            db,
            sql: "SELECT id FROM raw_files WHERE relative_path = ?",
            arguments: [manifest.rawFileName]
        )

        try db.execute(
            sql: """
            INSERT INTO raw_files (
                relative_path, raw_file_name, manifest_file_name, sha256, bytes,
                fetched_at, adapter, account, endpoint, api_version, "limit",
                "offset", http_status, api_meta_code, returned_count, total_count,
                imported_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(relative_path) DO UPDATE SET
                raw_file_name = excluded.raw_file_name,
                manifest_file_name = excluded.manifest_file_name,
                sha256 = excluded.sha256,
                bytes = excluded.bytes,
                fetched_at = excluded.fetched_at,
                adapter = excluded.adapter,
                account = excluded.account,
                endpoint = excluded.endpoint,
                api_version = excluded.api_version,
                "limit" = excluded."limit",
                "offset" = excluded."offset",
                http_status = excluded.http_status,
                api_meta_code = excluded.api_meta_code,
                returned_count = excluded.returned_count,
                total_count = excluded.total_count,
                imported_at = excluded.imported_at
            """,
            arguments: [
                manifest.rawFileName,
                manifest.rawFileName,
                manifestURL.lastPathComponent,
                manifest.rawSha256,
                manifest.rawBytes,
                manifest.fetchedAt,
                manifest.adapter.rawValue,
                manifest.account,
                manifest.endpoint,
                manifest.apiVersion,
                manifest.limit,
                manifest.offset,
                manifest.httpStatusCode,
                manifest.apiMetaCode,
                manifest.returnedCount,
                manifest.totalCount,
                importedAt
            ]
        )

        let rawFileID = try Int.fetchOne(
            db,
            sql: "SELECT id FROM raw_files WHERE relative_path = ?",
            arguments: [manifest.rawFileName]
        ).orThrow("raw file row was not available after import.")

        var counts = ManifestImportCounts(rawFileInserted: existingRawFileID == nil)

        for item in envelope.items {
            guard let checkinID = nonEmptyString(item["id"]) else {
                counts.skippedCheckins += 1
                continue
            }

            let existingCheckin = try String.fetchOne(
                db,
                sql: "SELECT checkin_id FROM checkins WHERE checkin_id = ?",
                arguments: [checkinID]
            )
            let venue = item["venue"] as? [String: Any]
            let venueID = nonEmptyString(venue?["id"])
            if let venueID, let venue {
                let existingVenue = try String.fetchOne(
                    db,
                    sql: "SELECT venue_id FROM venues WHERE venue_id = ?",
                    arguments: [venueID]
                )
                let categories = venue["categories"] as? [[String: Any]] ?? []
                try upsertVenue(db: db, venueID: venueID, venue: venue, categories: categories, updatedAt: importedAt)
                counts.venuesUpserted += 1
                counts.venuesInserted += existingVenue == nil ? 1 : 0
            }

            let createdAt = intValue(item["createdAt"])
            try db.execute(
                sql: """
                INSERT INTO checkins (
                    checkin_id, account, source_adapter, created_at_unix,
                    created_at_iso, venue_id, raw_file_id, raw_json, imported_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(checkin_id) DO UPDATE SET
                    account = excluded.account,
                    source_adapter = excluded.source_adapter,
                    created_at_unix = excluded.created_at_unix,
                    created_at_iso = excluded.created_at_iso,
                    venue_id = excluded.venue_id,
                    raw_file_id = excluded.raw_file_id,
                    raw_json = excluded.raw_json,
                    imported_at = excluded.imported_at
                """,
                arguments: [
                    checkinID,
                    manifest.account,
                    manifest.adapter.rawValue,
                    createdAt,
                    createdAt.map(iso8601String(timestamp:)),
                    venueID,
                    rawFileID,
                    try jsonString(item),
                    importedAt
                ]
            )
            counts.checkinsUpserted += 1
            counts.checkinsInserted += existingCheckin == nil ? 1 : 0

            if let venueID, let categories = venue?["categories"] as? [[String: Any]] {
                try upsertCategories(
                    db: db,
                    categories: categories,
                    checkinID: checkinID,
                    venueID: venueID,
                    account: manifest.account,
                    rawFileID: rawFileID,
                    updatedAt: importedAt,
                    counts: &counts
                )
            }
        }

        return counts
    }

    private static func parseEnvelope(_ data: Data) throws -> V2CheckinsEnvelope {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let response = object["response"] as? [String: Any],
              let checkins = response["checkins"] as? [String: Any],
              let items = checkins["items"] as? [[String: Any]] else {
            throw RawImportSkip("raw response.checkins.items was not present")
        }

        return V2CheckinsEnvelope(items: items)
    }

    private static func upsertVenue(
        db: Database,
        venueID: String,
        venue: [String: Any],
        categories: [[String: Any]],
        updatedAt: String
    ) throws {
        let location = venue["location"] as? [String: Any]
        try db.execute(
            sql: """
            INSERT INTO venues (
                venue_id, name, lat, lng, categories_json, raw_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(venue_id) DO UPDATE SET
                name = excluded.name,
                lat = excluded.lat,
                lng = excluded.lng,
                categories_json = excluded.categories_json,
                raw_json = excluded.raw_json,
                updated_at = excluded.updated_at
            """,
            arguments: [
                venueID,
                nonEmptyString(venue["name"]),
                doubleValue(location?["lat"]),
                doubleValue(location?["lng"]),
                try jsonString(categories),
                try jsonString(venue),
                updatedAt
            ]
        )
    }

    private static func upsertCategories(
        db: Database,
        categories: [[String: Any]],
        checkinID: String,
        venueID: String,
        account: String,
        rawFileID: Int,
        updatedAt: String,
        counts: inout ManifestImportCounts
    ) throws {
        for (index, category) in categories.enumerated() {
            guard let categoryID = nonEmptyString(category["id"]) else {
                continue
            }

            let existingCategory = try String.fetchOne(
                db,
                sql: "SELECT category_id FROM categories WHERE category_id = ?",
                arguments: [categoryID]
            )
            try db.execute(
                sql: """
                INSERT INTO categories (
                    category_id, name, plural_name, short_name, icon_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(category_id) DO UPDATE SET
                    name = excluded.name,
                    plural_name = excluded.plural_name,
                    short_name = excluded.short_name,
                    icon_json = excluded.icon_json,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    categoryID,
                    nonEmptyString(category["name"]),
                    nonEmptyString(category["pluralName"]),
                    nonEmptyString(category["shortName"]),
                    try jsonString(category["icon"]),
                    updatedAt
                ]
            )
            counts.categoriesUpserted += 1
            counts.categoriesInserted += existingCategory == nil ? 1 : 0

            try db.execute(
                sql: """
                INSERT INTO checkin_categories (
                    checkin_id, category_id, venue_id, account, raw_file_id, ordinal
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(checkin_id, category_id) DO UPDATE SET
                    venue_id = excluded.venue_id,
                    account = excluded.account,
                    raw_file_id = excluded.raw_file_id,
                    ordinal = excluded.ordinal
                """,
                arguments: [
                    checkinID,
                    categoryID,
                    venueID,
                    account,
                    rawFileID,
                    index
                ]
            )
        }
    }

    private static func jsonString(_ object: Any?) throws -> String? {
        guard let object else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        return string.isEmpty ? nil : string
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func iso8601String(timestamp: Int) -> String {
        iso8601String(Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private struct V2CheckinsEnvelope {
    let items: [[String: Any]]
}

private struct ImportAccumulator {
    var rawFilesImported = 0
    var rawFilesInserted = 0
    var checkinsUpserted = 0
    var checkinsInserted = 0
    var venuesUpserted = 0
    var venuesInserted = 0
    var categoriesUpserted = 0
    var categoriesInserted = 0
    var skippedFiles = 0
    var skippedCheckins = 0
    var warnings: [String] = []
}

private struct ManifestImportCounts {
    var rawFileInserted: Bool
    var checkinsUpserted = 0
    var checkinsInserted = 0
    var venuesUpserted = 0
    var venuesInserted = 0
    var categoriesUpserted = 0
    var categoriesInserted = 0
    var skippedCheckins = 0
}

private struct RawImportSkip: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
