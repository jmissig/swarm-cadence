import Foundation
import GRDB

public struct RawImportResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String?
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
    public let qualityReportPath: String?
    public let qualityIssueCount: Int
    public let warnings: [String]
}

public struct ImportQualityIssue: Codable, Equatable {
    public let checkinID: String
    public let field: String
    public let createdAt: String?
    public let source: String
    public let file: String
    public let latitude: Double?
    public let longitude: Double?
}

public enum FileImportSource: String, Codable, Equatable {
    case foursquareExport = "foursquare-export"
}


public struct DatabaseMigrateResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String?
    public let dbPath: String
    public let migrationsApplied: [String]
    public let annotationsTablePresent: Bool
}

public struct DatabaseStatsResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String?
    public let dbPath: String
    public let rawFiles: Int
    public let checkins: Int
    public let venues: Int
    public let categories: Int
    public let lastFetchedAtISO8601: String?
    public let lastImportedAtISO8601: String?
    public let currentThroughISO8601: String?
    public let minCreatedAt: Int?
    public let maxCreatedAt: Int?
    public let oldestCreatedAtISO8601: String?
    public let latestCreatedAtISO8601: String?
}

public struct DatabaseFreshness: Codable, Equatable {
    public let account: String?
    public let adapter: String?
    public let lastFetchedAtISO8601: String?
    public let lastImportedAtISO8601: String?
    public let oldestCreatedAt: Int?
    public let oldestCreatedAtISO8601: String?
    public let latestCreatedAt: Int?
    public let latestCreatedAtISO8601: String?
    public let currentThroughISO8601: String?
}

public enum SwarmDatabase {

    public static func migrateDatabase(dbPath: String, account: String? = nil) throws -> DatabaseMigrateResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try account.map(AccountLabel.validate)
        let dbQueue = try openDatabase(path: dbPath)
        try migrate(dbQueue)
        return try dbQueue.read { db in
            let migrations = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"
            )
            let annotationsPresent = try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'annotations'
                )
                """
            ) ?? false
            return DatabaseMigrateResult(
                schemaVersion: 1,
                command: "db migrate",
                account: account,
                dbPath: dbPath,
                migrationsApplied: migrations,
                annotationsTablePresent: annotationsPresent
            )
        }
    }

    public static func importRawV2Checkins(
        dbPath: String,
        rawDirectory: String,
        account: String? = nil,
        importedAt: Date = Date()
    ) throws -> RawImportResult {
        try importRawV2Checkins(
            dbPath: dbPath,
            rawDirectory: rawDirectory,
            account: account,
            importedAt: importedAt,
            manifestFileNames: nil
        )
    }

    static func importRawV2Checkins(
        dbPath: String,
        rawDirectory: String,
        account: String? = nil,
        importedAt: Date = Date(),
        manifestFileNames: Set<String>?
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
            .filter { manifestFileNames?.contains($0.lastPathComponent) ?? true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let importedAtString = iso8601String(importedAt)
        var accumulator = ImportAccumulator()

        let expectedAccount = try account.map(AccountLabel.validate)

        try dbQueue.write { db in
            for manifestURL in manifestURLs {
                do {
                    let imported = try importOneManifest(
                        db: db,
                        manifestURL: manifestURL,
                        rawDirectoryURL: rawDirectoryURL,
                        expectedAccount: expectedAccount,
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
            account: account,
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
            qualityReportPath: nil,
            qualityIssueCount: 0,
            warnings: accumulator.warnings
        )
    }


    public static func importFiles(
        dbPath: String,
        path: String,
        account: String,
        source: FileImportSource = .foursquareExport,
        importedAt: Date = Date()
    ) throws -> RawImportResult {
        switch source {
        case .foursquareExport:
            return try importFoursquareExportCheckins(
                dbPath: dbPath,
                exportDirectory: path,
                account: account,
                importedAt: importedAt
            )
        }
    }

    private static func importFoursquareExportCheckins(
        dbPath: String,
        exportDirectory: String,
        account: String,
        importedAt: Date = Date()
    ) throws -> RawImportResult {
        guard !dbPath.isEmpty else { throw CLIError("missing required --db <path>.") }
        guard !exportDirectory.isEmpty else { throw CLIError("missing required --path <dir>.") }
        let account = try AccountLabel.validate(account)
        let exportDirectoryURL = URL(fileURLWithPath: exportDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: exportDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError("--path does not exist or is not a directory: \(exportDirectory).")
        }

        let dbQueue = try openDatabase(path: dbPath)
        try migrate(dbQueue)
        let importedAtString = iso8601String(importedAt)
        let checkinFiles = try FileManager.default
            .contentsOfDirectory(at: exportDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.range(of: #"^checkins\d+\.json$"#, options: .regularExpression) != nil }
            .sorted { exportCheckinsFileOrdinal($0.lastPathComponent) < exportCheckinsFileOrdinal($1.lastPathComponent) }

        var accumulator = ImportAccumulator()
        var qualityIssues: [ImportQualityIssue] = []
        try dbQueue.write { db in
            for fileURL in checkinFiles {
                do {
                    let imported = try importOneExportCheckinsFile(
                        db: db,
                        fileURL: fileURL,
                        exportDirectoryURL: exportDirectoryURL,
                        account: account,
                        importedAt: importedAtString,
                        qualityIssues: &qualityIssues
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
                    accumulator.warnings.append("skipped export file: \(error.message)")
                }
            }
        }

        let qualityReportPath = try writeQualityReportIfNeeded(
            issues: qualityIssues,
            dbPath: dbPath
        )

        return RawImportResult(
            schemaVersion: 1,
            command: "db import-files",
            account: account,
            dbPath: dbPath,
            rawDirectory: exportDirectory,
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
            qualityReportPath: qualityReportPath,
            qualityIssueCount: qualityIssues.count,
            warnings: accumulator.warnings
        )
    }

    public static func stats(dbPath: String, account: String? = nil) throws -> DatabaseStatsResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }

        let account = try account.map(AccountLabel.validate)
        let dbQueue = try openReadOnlyDatabase(path: dbPath)

        return try dbQueue.read { db in
            let minCreatedAt = try Int.fetchOne(
                db,
                sql: "SELECT MIN(created_at_unix) FROM checkins WHERE (? IS NULL OR account = ?)",
                arguments: [account, account]
            )
            let maxCreatedAt = try Int.fetchOne(
                db,
                sql: "SELECT MAX(created_at_unix) FROM checkins WHERE (? IS NULL OR account = ?)",
                arguments: [account, account]
            )

            let freshness = try freshness(db: db, account: account, adapter: nil)

            return DatabaseStatsResult(
                schemaVersion: 1,
                command: "db stats",
                account: account,
                dbPath: dbPath,
                rawFiles: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM raw_files WHERE (? IS NULL OR account = ?)",
                    arguments: [account, account]
                ) ?? 0,
                checkins: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM checkins WHERE (? IS NULL OR account = ?)",
                    arguments: [account, account]
                ) ?? 0,
                venues: try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(DISTINCT v.venue_id)
                    FROM venues v
                    JOIN checkins c ON c.venue_id = v.venue_id
                    WHERE (? IS NULL OR c.account = ?)
                    """,
                    arguments: [account, account]
                ) ?? 0,
                categories: try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(DISTINCT cat.category_id)
                    FROM categories cat
                    JOIN checkin_categories cc ON cc.category_id = cat.category_id
                    WHERE (? IS NULL OR cc.account = ?)
                    """,
                    arguments: [account, account]
                ) ?? 0,
                lastFetchedAtISO8601: freshness.lastFetchedAtISO8601,
                lastImportedAtISO8601: freshness.lastImportedAtISO8601,
                currentThroughISO8601: freshness.currentThroughISO8601,
                minCreatedAt: minCreatedAt,
                maxCreatedAt: maxCreatedAt,
                oldestCreatedAtISO8601: minCreatedAt.map(iso8601String(timestamp:)),
                latestCreatedAtISO8601: maxCreatedAt.map(iso8601String(timestamp:))
            )
        }
    }

    public static func freshness(
        dbPath: String,
        account: String? = nil,
        adapter: String? = nil
    ) throws -> DatabaseFreshness {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }

        let account = try account.map(AccountLabel.validate)
        let dbQueue = try openReadOnlyDatabase(path: dbPath)

        return try dbQueue.read { db in
            try freshness(db: db, account: account, adapter: adapter)
        }
    }

    public static func existingCheckinIDs(dbPath: String, account: String, adapter: String? = nil) throws -> Set<String> {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }

        let account = try AccountLabel.validate(account)
        let dbQueue = try openDatabase(path: dbPath)
        try migrate(dbQueue)

        return try dbQueue.read { db in
            Set(try String.fetchAll(
                db,
                sql: """
                SELECT c.checkin_id
                FROM checkins c
                WHERE c.account = ?
                  AND (
                    ? IS NULL
                    OR EXISTS (
                      SELECT 1
                      FROM raw_files rf
                      WHERE rf.id = c.raw_file_id
                        AND rf.adapter = ?
                    )
                  )
                """,
                arguments: [account, adapter, adapter]
            ))
        }
    }

    static func openReadOnlyDatabase(path: String) throws -> DatabaseQueue {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError("SQLite DB does not exist: \(path). Run `db import-raw` first.")
        }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try DatabaseQueue(path: path, configuration: configuration)
    }

    static func openDatabase(path: String) throws -> DatabaseQueue {
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

    static func migrate(_ dbQueue: DatabaseQueue) throws {
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
        migrator.registerMigration("v2_checkin_local_time") { db in
            try db.execute(sql: """
            ALTER TABLE checkins ADD COLUMN local_timezone_id TEXT;
            ALTER TABLE checkins ADD COLUMN local_timezone_offset_minutes INTEGER;
            ALTER TABLE checkins ADD COLUMN local_created_at TEXT;
            ALTER TABLE checkins ADD COLUMN local_date TEXT;
            ALTER TABLE checkins ADD COLUMN local_hour INTEGER;
            ALTER TABLE checkins ADD COLUMN local_weekday_iso INTEGER;
            CREATE INDEX idx_checkins_account_local_date ON checkins(account, local_date);
            CREATE INDEX idx_checkins_account_local_hour ON checkins(account, local_hour);
            """)
        }
        migrator.registerMigration("v3_venue_location_fields") { db in
            try db.execute(sql: """
            ALTER TABLE venues ADD COLUMN locality TEXT;
            ALTER TABLE venues ADD COLUMN region TEXT;
            ALTER TABLE venues ADD COLUMN postal_code TEXT;
            ALTER TABLE venues ADD COLUMN country_code TEXT;
            ALTER TABLE venues ADD COLUMN country TEXT;
            ALTER TABLE venues ADD COLUMN neighborhood TEXT;
            CREATE INDEX idx_venues_location_fields ON venues(locality, region, postal_code, country_code);
            """)

            let rows = try Row.fetchAll(db, sql: "SELECT venue_id, raw_json FROM venues")
            for row in rows {
                let venueID: String = row["venue_id"]
                let rawJSON: String? = row["raw_json"]
                guard
                    let rawJSON,
                    let data = rawJSON.data(using: .utf8),
                    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let location = object["location"] as? [String: Any]
                else { continue }
                try updateVenueLocationFields(db: db, venueID: venueID, location: location)
            }
        }
        migrator.registerMigration("v4_annotations") { db in
            try db.execute(sql: """
            CREATE TABLE annotations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account TEXT NOT NULL,
                target_kind TEXT NOT NULL,
                target_id TEXT NOT NULL,
                body TEXT NOT NULL,
                source TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX idx_annotations_account_target ON annotations(account, target_kind, target_id);
            CREATE INDEX idx_annotations_account_updated_at ON annotations(account, updated_at);
            """)
        }
        try migrator.migrate(dbQueue)
    }

    private static func importOneManifest(
        db: Database,
        manifestURL: URL,
        rawDirectoryURL: URL,
        expectedAccount: String?,
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
        if let expectedAccount, manifest.account != expectedAccount {
            throw RawImportSkip("manifest account \(manifest.account) does not match requested account \(expectedAccount)")
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
            let localTime = localTimeEvidence(createdAt: createdAt, item: item, venue: venue)
            try db.execute(
                sql: """
                INSERT INTO checkins (
                    checkin_id, account, source_adapter, created_at_unix,
                    created_at_iso, local_timezone_id, local_timezone_offset_minutes,
                    local_created_at, local_date, local_hour, local_weekday_iso,
                    venue_id, raw_file_id, raw_json, imported_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(checkin_id) DO UPDATE SET
                    account = excluded.account,
                    source_adapter = excluded.source_adapter,
                    created_at_unix = excluded.created_at_unix,
                    created_at_iso = excluded.created_at_iso,
                    local_timezone_id = excluded.local_timezone_id,
                    local_timezone_offset_minutes = excluded.local_timezone_offset_minutes,
                    local_created_at = excluded.local_created_at,
                    local_date = excluded.local_date,
                    local_hour = excluded.local_hour,
                    local_weekday_iso = excluded.local_weekday_iso,
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
                    localTime.timezoneID,
                    localTime.offsetMinutes,
                    localTime.localCreatedAt,
                    localTime.localDate,
                    localTime.localHour,
                    localTime.localWeekdayISO,
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


    private static func importOneExportCheckinsFile(
        db: Database,
        fileURL: URL,
        exportDirectoryURL: URL,
        account: String,
        importedAt: String,
        qualityIssues: inout [ImportQualityIssue]
    ) throws -> ManifestImportCounts {
        let rawData = try Data(contentsOf: fileURL)
        guard let object = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else {
            throw RawImportSkip("export checkins file could not be decoded")
        }
        let sha = RawFetch.sha256Hex(rawData)
        let relativePath = fileURL.lastPathComponent
        let existingRawFileID = try Int.fetchOne(db, sql: "SELECT id FROM raw_files WHERE relative_path = ?", arguments: [relativePath])
        let ordinal = exportCheckinsFileOrdinal(fileURL.lastPathComponent)
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
                relativePath,
                fileURL.lastPathComponent,
                "",
                sha,
                rawData.count,
                importedAt,
                "export",
                account,
                "foursquare-export/checkins",
                "export",
                items.count,
                max(0, (ordinal - 1) * 1_000),
                0,
                nil,
                items.count,
                object["count"] as? Int ?? items.count,
                importedAt
            ]
        )
        let rawFileID = try Int.fetchOne(db, sql: "SELECT id FROM raw_files WHERE relative_path = ?", arguments: [relativePath])
            .orThrow("raw file row was not available after export import.")
        var counts = ManifestImportCounts(rawFileInserted: existingRawFileID == nil)

        for item in items {
            guard let checkinID = nonEmptyString(item["id"]) else {
                counts.skippedCheckins += 1
                continue
            }
            let existingCheckin = try String.fetchOne(db, sql: "SELECT checkin_id FROM checkins WHERE checkin_id = ?", arguments: [checkinID])

            let exportVenue = item["venue"] as? [String: Any]
            let venueID = nonEmptyString(exportVenue?["id"])
            if venueID == nil {
                qualityIssues.append(ImportQualityIssue(
                    checkinID: checkinID,
                    field: "venue",
                    createdAt: nonEmptyString(item["createdAt"]),
                    source: "foursquare-export",
                    file: fileURL.lastPathComponent,
                    latitude: doubleValue(item["lat"]),
                    longitude: doubleValue(item["lng"])
                ))
            }
            if existingCheckin != nil {
                counts.skippedCheckins += 1
                continue
            }

            if let venueID, var venue = exportVenue {
                if venue["location"] == nil {
                    var location: [String: Any] = [:]
                    if let lat = doubleValue(item["lat"]) { location["lat"] = lat }
                    if let lng = doubleValue(item["lng"]) { location["lng"] = lng }
                    if !location.isEmpty { venue["location"] = location }
                }
                let existingVenue = try String.fetchOne(db, sql: "SELECT venue_id FROM venues WHERE venue_id = ?", arguments: [venueID])
                try upsertVenuePreservingExisting(db: db, venueID: venueID, venue: venue, categories: [], updatedAt: importedAt)
                counts.venuesUpserted += 1
                counts.venuesInserted += existingVenue == nil ? 1 : 0
            }

            let createdAt = exportCreatedAtUnix(item["createdAt"])
            let localTime = localTimeEvidence(createdAt: createdAt, item: item, venue: exportVenue)
            try db.execute(
                sql: """
                INSERT INTO checkins (
                    checkin_id, account, source_adapter, created_at_unix,
                    created_at_iso, local_timezone_id, local_timezone_offset_minutes,
                    local_created_at, local_date, local_hour, local_weekday_iso,
                    venue_id, raw_file_id, raw_json, imported_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    checkinID,
                    account,
                    "export",
                    createdAt,
                    createdAt.map(iso8601String(timestamp:)),
                    localTime.timezoneID,
                    localTime.offsetMinutes,
                    localTime.localCreatedAt,
                    localTime.localDate,
                    localTime.localHour,
                    localTime.localWeekdayISO,
                    venueID,
                    rawFileID,
                    try jsonString(item),
                    importedAt
                ]
            )
            counts.checkinsUpserted += 1
            counts.checkinsInserted += 1
        }
        return counts
    }

    private static func upsertVenuePreservingExisting(
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
                venue_id, name, lat, lng, locality, region, postal_code, country_code, country, neighborhood, categories_json, raw_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(venue_id) DO UPDATE SET
                name = COALESCE(venues.name, excluded.name),
                lat = COALESCE(venues.lat, excluded.lat),
                lng = COALESCE(venues.lng, excluded.lng),
                locality = COALESCE(venues.locality, excluded.locality),
                region = COALESCE(venues.region, excluded.region),
                postal_code = COALESCE(venues.postal_code, excluded.postal_code),
                country_code = COALESCE(venues.country_code, excluded.country_code),
                country = COALESCE(venues.country, excluded.country),
                neighborhood = COALESCE(venues.neighborhood, excluded.neighborhood),
                categories_json = COALESCE(venues.categories_json, excluded.categories_json),
                raw_json = COALESCE(venues.raw_json, excluded.raw_json),
                updated_at = excluded.updated_at
            """,
            arguments: [
                venueID,
                nonEmptyString(venue["name"]),
                doubleValue(location?["lat"]),
                doubleValue(location?["lng"]),
                nonEmptyString(location?["city"]),
                nonEmptyString(location?["state"]),
                nonEmptyString(location?["postalCode"]),
                nonEmptyString(location?["cc"]),
                nonEmptyString(location?["country"]),
                nonEmptyString(location?["neighborhood"]),
                try jsonString(categories),
                try jsonString(venue),
                updatedAt
            ]
        )
    }

    private static func updateVenueLocationFields(db: Database, venueID: String, location: [String: Any]) throws {
        try db.execute(
            sql: """
            UPDATE venues
            SET locality = ?,
                region = ?,
                postal_code = ?,
                country_code = ?,
                country = ?,
                neighborhood = ?
            WHERE venue_id = ?
            """,
            arguments: [
                nonEmptyString(location["city"]),
                nonEmptyString(location["state"]),
                nonEmptyString(location["postalCode"]),
                nonEmptyString(location["cc"]),
                nonEmptyString(location["country"]),
                nonEmptyString(location["neighborhood"]),
                venueID
            ]
        )
    }

    private static func exportCreatedAtUnix(_ value: Any?) -> Int? {
        if let int = intValue(value) { return int }
        guard let string = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        if let date = formatter.date(from: string) { return Int(date.timeIntervalSince1970) }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string).map { Int($0.timeIntervalSince1970) }
    }

    private static func writeQualityReportIfNeeded(
        issues: [ImportQualityIssue],
        dbPath: String
    ) throws -> String? {
        guard !issues.isEmpty else { return nil }
        let dbURL = URL(fileURLWithPath: dbPath)
        let qualityDirectory = dbURL.deletingLastPathComponent().appendingPathComponent("quality", isDirectory: true)
        try FileManager.default.createDirectory(at: qualityDirectory, withIntermediateDirectories: true)
        let reportURL = qualityDirectory.appendingPathComponent("checkins-missing-values.csv")
        var lines = ["checkin_id,field,created_at,source,file,lat,lng"]
        for issue in issues {
            let row: [String] = [
                issue.checkinID,
                issue.field,
                issue.createdAt ?? "",
                issue.source,
                issue.file,
                issue.latitude.map { String($0) } ?? "",
                issue.longitude.map { String($0) } ?? ""
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        return reportURL.path
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func exportCheckinsFileOrdinal(_ name: String) -> Int {
        let digits = name.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)
        return Int(digits) ?? 0
    }

    private struct LocalTimeEvidence {
        let timezoneID: String?
        let offsetMinutes: Int?
        let localCreatedAt: String?
        let localDate: String?
        let localHour: Int?
        let localWeekdayISO: Int?
    }

    private static func localTimeEvidence(
        createdAt: Int?,
        item: [String: Any],
        venue: [String: Any]?
    ) -> LocalTimeEvidence {
        let timezoneID = nonEmptyString(venue?["timeZone"])
        let offsetMinutes = intValue(item["timeZoneOffset"])
        guard let createdAt else {
            return LocalTimeEvidence(
                timezoneID: timezoneID,
                offsetMinutes: offsetMinutes,
                localCreatedAt: nil,
                localDate: nil,
                localHour: nil,
                localWeekdayISO: nil
            )
        }

        let timeZone = timezoneID.flatMap(TimeZone.init(identifier:))
            ?? offsetMinutes.flatMap { TimeZone(secondsFromGMT: $0 * 60) }
        guard let timeZone else {
            return LocalTimeEvidence(
                timezoneID: timezoneID,
                offsetMinutes: offsetMinutes,
                localCreatedAt: nil,
                localDate: nil,
                localHour: nil,
                localWeekdayISO: nil
            )
        }

        let date = Date(timeIntervalSince1970: TimeInterval(createdAt))
        let createdFormatter = DateFormatter()
        createdFormatter.calendar = Calendar(identifier: .gregorian)
        createdFormatter.locale = Locale(identifier: "en_US_POSIX")
        createdFormatter.timeZone = timeZone
        createdFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let weekdayISO = ((weekday + 5) % 7) + 1

        return LocalTimeEvidence(
            timezoneID: timezoneID,
            offsetMinutes: offsetMinutes,
            localCreatedAt: createdFormatter.string(from: date),
            localDate: dateFormatter.string(from: date),
            localHour: hour,
            localWeekdayISO: weekdayISO
        )
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
                venue_id, name, lat, lng, locality, region, postal_code, country_code, country, neighborhood, categories_json, raw_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(venue_id) DO UPDATE SET
                name = excluded.name,
                lat = excluded.lat,
                lng = excluded.lng,
                locality = excluded.locality,
                region = excluded.region,
                postal_code = excluded.postal_code,
                country_code = excluded.country_code,
                country = excluded.country,
                neighborhood = excluded.neighborhood,
                categories_json = excluded.categories_json,
                raw_json = excluded.raw_json,
                updated_at = excluded.updated_at
            """,
            arguments: [
                venueID,
                nonEmptyString(venue["name"]),
                doubleValue(location?["lat"]),
                doubleValue(location?["lng"]),
                nonEmptyString(location?["city"]),
                nonEmptyString(location?["state"]),
                nonEmptyString(location?["postalCode"]),
                nonEmptyString(location?["cc"]),
                nonEmptyString(location?["country"]),
                nonEmptyString(location?["neighborhood"]),
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

    static func freshness(
        db: Database,
        account: String?,
        adapter: String?
    ) throws -> DatabaseFreshness {
        let minCreatedAt = try Int.fetchOne(
            db,
            sql: """
            SELECT MIN(c.created_at_unix)
            FROM checkins c
            WHERE (? IS NULL OR c.account = ?)
              AND (
                ? IS NULL
                OR EXISTS (
                  SELECT 1
                  FROM raw_files rf
                  WHERE rf.id = c.raw_file_id
                    AND rf.adapter = ?
                )
              )
            """,
            arguments: [account, account, adapter, adapter]
        )
        let maxCreatedAt = try Int.fetchOne(
            db,
            sql: """
            SELECT MAX(c.created_at_unix)
            FROM checkins c
            WHERE (? IS NULL OR c.account = ?)
              AND (
                ? IS NULL
                OR EXISTS (
                  SELECT 1
                  FROM raw_files rf
                  WHERE rf.id = c.raw_file_id
                    AND rf.adapter = ?
                )
              )
            """,
            arguments: [account, account, adapter, adapter]
        )
        let lastFetchedAt = try String.fetchOne(
            db,
            sql: """
            SELECT MAX(fetched_at)
            FROM raw_files
            WHERE (? IS NULL OR account = ?)
              AND (? IS NULL OR adapter = ?)
            """,
            arguments: [account, account, adapter, adapter]
        )
        let lastImportedAt = try String.fetchOne(
            db,
            sql: """
            SELECT MAX(imported_at)
            FROM raw_files
            WHERE (? IS NULL OR account = ?)
              AND (? IS NULL OR adapter = ?)
            """,
            arguments: [account, account, adapter, adapter]
        )

        return DatabaseFreshness(
            account: account,
            adapter: adapter,
            lastFetchedAtISO8601: lastFetchedAt,
            lastImportedAtISO8601: lastImportedAt,
            oldestCreatedAt: minCreatedAt,
            oldestCreatedAtISO8601: minCreatedAt.map(iso8601String(timestamp:)),
            latestCreatedAt: maxCreatedAt,
            latestCreatedAtISO8601: maxCreatedAt.map(iso8601String(timestamp:)),
            currentThroughISO8601: maxCreatedAt.map(iso8601String(timestamp:))
        )
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
