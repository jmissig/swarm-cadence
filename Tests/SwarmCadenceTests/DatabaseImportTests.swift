import Foundation
import XCTest
@testable import SwarmCadenceCore

final class DatabaseImportTests: XCTestCase {
    func testImportRawV2ManifestAndRawFileIntoSQLite() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        let result = try SwarmDatabase.importRawV2Checkins(
            dbPath: dbURL.path,
            rawDirectory: rawDirectory.path,
            importedAt: Date(timeIntervalSince1970: 1_700_000_999)
        )
        let stats = try SwarmDatabase.stats(dbPath: dbURL.path)

        XCTAssertEqual(result.rawFilesImported, 1)
        XCTAssertEqual(result.rawFilesInserted, 1)
        XCTAssertEqual(result.checkinsUpserted, 2)
        XCTAssertEqual(result.checkinsInserted, 2)
        XCTAssertEqual(result.venuesUpserted, 1)
        XCTAssertEqual(result.venuesInserted, 1)
        XCTAssertEqual(result.categoriesUpserted, 1)
        XCTAssertEqual(result.categoriesInserted, 1)
        XCTAssertEqual(result.skippedFiles, 0)
        XCTAssertEqual(result.skippedCheckins, 1)
        XCTAssertEqual(stats.rawFiles, 1)
        XCTAssertEqual(stats.checkins, 2)
        XCTAssertEqual(stats.venues, 1)
        XCTAssertEqual(stats.categories, 1)
        XCTAssertEqual(stats.minCreatedAt, 1_700_000_000)
        XCTAssertEqual(stats.maxCreatedAt, 1_700_000_100)
        XCTAssertEqual(stats.oldestCreatedAtISO8601, "2023-11-14T22:13:20Z")
        XCTAssertEqual(stats.latestCreatedAtISO8601, "2023-11-14T22:15:00Z")
    }

    func testImportIsIdempotent() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        _ = try SwarmDatabase.importRawV2Checkins(dbPath: dbURL.path, rawDirectory: rawDirectory.path)
        let second = try SwarmDatabase.importRawV2Checkins(dbPath: dbURL.path, rawDirectory: rawDirectory.path)
        let stats = try SwarmDatabase.stats(dbPath: dbURL.path)

        XCTAssertEqual(second.rawFilesImported, 1)
        XCTAssertEqual(second.rawFilesInserted, 0)
        XCTAssertEqual(second.checkinsUpserted, 2)
        XCTAssertEqual(second.checkinsInserted, 0)
        XCTAssertEqual(second.venuesUpserted, 1)
        XCTAssertEqual(second.venuesInserted, 0)
        XCTAssertEqual(second.categoriesUpserted, 1)
        XCTAssertEqual(second.categoriesInserted, 0)
        XCTAssertEqual(stats.rawFiles, 1)
        XCTAssertEqual(stats.checkins, 2)
        XCTAssertEqual(stats.venues, 1)
        XCTAssertEqual(stats.categories, 1)
    }

    func testImportSkipsRawFilesWhenManifestShaDoesNotMatch() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody,
            shaOverride: String(repeating: "0", count: 64)
        )

        let result = try SwarmDatabase.importRawV2Checkins(dbPath: dbURL.path, rawDirectory: rawDirectory.path)
        let stats = try SwarmDatabase.stats(dbPath: dbURL.path)

        XCTAssertEqual(result.rawFilesImported, 0)
        XCTAssertEqual(result.skippedFiles, 1)
        XCTAssertTrue(result.warnings.first?.contains("sha256") ?? false)
        XCTAssertEqual(stats.rawFiles, 0)
        XCTAssertEqual(stats.checkins, 0)
    }

    func testCLIImportRawAndStatsRenderAggregateOnlyJSON() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        var importOutput = ""
        let importExit = SwarmCadenceCommand.run(
            arguments: [
                "db", "import-raw",
                "--account", "julian",
                "--db", dbURL.path,
                "--raw-dir", rawDirectory.path,
                "--format", "json"
            ],
            output: { importOutput = $0 },
            errorOutput: { _ in }
        )

        var statsOutput = ""
        let statsExit = SwarmCadenceCommand.run(
            arguments: [
                "db", "stats",
                "--account", "julian",
                "--db", dbURL.path,
                "--json"
            ],
            output: { statsOutput = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(importExit, 0)
        XCTAssertEqual(statsExit, 0)
        XCTAssertTrue(importOutput.contains("\"network\"") == false)
        XCTAssertTrue(importOutput.contains("\"checkins_upserted\" : 2"))
        XCTAssertTrue(statsOutput.contains("\"checkins\" : 2"))
        XCTAssertFalse(importOutput.contains("Cafe Example"))
        XCTAssertFalse(statsOutput.contains("Cafe Example"))
    }


    func testCLIDefaultsKeepJulianAndAliceInParallelEvidenceStores() throws {
        let home = try makeTemporaryDirectory()
        let appRoot = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("swarm-cadence", isDirectory: true)
        let julianRawDirectory = appRoot
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("julian", isDirectory: true)
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("checkins", isDirectory: true)
        let aliceRawDirectory = appRoot
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("alice", isDirectory: true)
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("checkins", isDirectory: true)
        try FileManager.default.createDirectory(at: julianRawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliceRawDirectory, withIntermediateDirectories: true)

        try writeRawPair(
            rawDirectory: julianRawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody,
            account: "julian"
        )
        try writeRawPair(
            rawDirectory: aliceRawDirectory,
            baseName: "fixture-v2-alice-checkins-offset0-limit250",
            rawBody: rawBody,
            account: "alice"
        )

        var julianImportOutput = ""
        let julianImportExit = SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--format", "json"],
            environment: ["HOME": home.path],
            output: { julianImportOutput = $0 },
            errorOutput: { _ in }
        )
        var aliceImportOutput = ""
        let aliceImportExit = SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "alice", "--format", "json"],
            environment: ["HOME": home.path],
            output: { aliceImportOutput = $0 },
            errorOutput: { _ in }
        )

        var julianStatsOutput = ""
        let julianStatsExit = SwarmCadenceCommand.run(
            arguments: ["db", "stats", "--account", "julian", "--format", "json"],
            environment: ["HOME": home.path],
            output: { julianStatsOutput = $0 },
            errorOutput: { _ in }
        )
        var aliceStatsOutput = ""
        let aliceStatsExit = SwarmCadenceCommand.run(
            arguments: ["db", "stats", "--account", "alice", "--format", "json"],
            environment: ["HOME": home.path],
            output: { aliceStatsOutput = $0 },
            errorOutput: { _ in }
        )

        let julianDB = appRoot
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("julian", isDirectory: true)
            .appendingPathComponent("swarm-cadence.sqlite")
        let aliceDB = appRoot
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("alice", isDirectory: true)
            .appendingPathComponent("swarm-cadence.sqlite")

        XCTAssertEqual(julianImportExit, 0)
        XCTAssertEqual(aliceImportExit, 0)
        XCTAssertEqual(julianStatsExit, 0)
        XCTAssertEqual(aliceStatsExit, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: julianDB.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliceDB.path))
        XCTAssertTrue(julianImportOutput.contains("\"account\" : \"julian\""))
        XCTAssertTrue(aliceImportOutput.contains("\"account\" : \"alice\""))
        XCTAssertTrue(julianImportOutput.contains("accounts"))
        XCTAssertTrue(julianImportOutput.contains("julian"))
        XCTAssertTrue(julianImportOutput.contains("raw"))
        XCTAssertTrue(aliceImportOutput.contains("accounts"))
        XCTAssertTrue(aliceImportOutput.contains("alice"))
        XCTAssertTrue(aliceImportOutput.contains("raw"))
        var julianVenuesOutput = ""
        let julianVenuesExit = SwarmCadenceCommand.run(
            arguments: ["query", "venues", "--account", "julian", "--format", "json"],
            environment: ["HOME": home.path],
            output: { julianVenuesOutput = $0 },
            errorOutput: { _ in }
        )
        var aliceVenuesOutput = ""
        let aliceVenuesExit = SwarmCadenceCommand.run(
            arguments: ["query", "venues", "--account", "alice", "--format", "json"],
            environment: ["HOME": home.path],
            output: { aliceVenuesOutput = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(julianVenuesExit, 0)
        XCTAssertEqual(aliceVenuesExit, 0)
        XCTAssertTrue(julianStatsOutput.contains("\"db_path\" : \"\(escapedJSONPath(julianDB.path))\""))
        XCTAssertTrue(aliceStatsOutput.contains("\"db_path\" : \"\(escapedJSONPath(aliceDB.path))\""))
        XCTAssertTrue(julianStatsOutput.contains("\"checkins\" : 2"))
        XCTAssertTrue(aliceStatsOutput.contains("\"checkins\" : 2"))
        XCTAssertTrue(julianVenuesOutput.contains("\"account\" : \"julian\""))
        XCTAssertTrue(aliceVenuesOutput.contains("\"account\" : \"alice\""))
        XCTAssertTrue(julianVenuesOutput.contains("\"db_path\" : \"\(escapedJSONPath(julianDB.path))\""))
        XCTAssertTrue(aliceVenuesOutput.contains("\"db_path\" : \"\(escapedJSONPath(aliceDB.path))\""))
        XCTAssertTrue(julianVenuesOutput.contains("\"total_matching_venues\" : 1"))
        XCTAssertTrue(aliceVenuesOutput.contains("\"total_matching_venues\" : 1"))
    }


    func testCLIQueryVenuesAndVisitsRenderAggregateEvidenceJSON() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        let importExit = SwarmCadenceCommand.run(
            arguments: [
                "db", "import-raw",
                "--account", "julian",
                "--db", dbURL.path,
                "--raw-dir", rawDirectory.path,
                "--format", "json"
            ],
            output: { _ in },
            errorOutput: { _ in }
        )

        var venuesOutput = ""
        let venuesExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", dbURL.path,
                "--from", "2023-11-14T22:00:00Z",
                "--to", "2023-11-15",
                "--limit", "10",
                "--format", "json"
            ],
            output: { venuesOutput = $0 },
            errorOutput: { _ in }
        )

        var categoriesOutput = ""
        let categoriesExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "categories",
                "--account", "julian",
                "--db", dbURL.path,
                "--limit", "10",
                "--format", "json"
            ],
            output: { categoriesOutput = $0 },
            errorOutput: { _ in }
        )

        var visitsOutput = ""
        let visitsExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "visits",
                "--account", "julian",
                "--db", dbURL.path,
                "--venue-id", "venue-1",
                "--format", "json"
            ],
            output: { visitsOutput = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(importExit, 0)
        XCTAssertEqual(venuesExit, 0)
        XCTAssertEqual(categoriesExit, 0)
        XCTAssertEqual(visitsExit, 0)
        XCTAssertTrue(venuesOutput.contains("\"command\" : \"query venues\""))
        XCTAssertTrue(venuesOutput.contains("\"account\" : \"julian\""))
        XCTAssertTrue(venuesOutput.contains("\"total_matching_venues\" : 1"))
        XCTAssertTrue(venuesOutput.contains("\"visit_count\" : 1"))
        XCTAssertTrue(venuesOutput.contains("\"name\" : \"Cafe Example\""))
        XCTAssertTrue(venuesOutput.contains("\"Coffee Shop\""))
        XCTAssertTrue(venuesOutput.contains("\"drill_down\""))
        XCTAssertTrue(categoriesOutput.contains("\"command\" : \"query categories\""))
        XCTAssertTrue(categoriesOutput.contains("\"total_matching_categories\" : 1"))
        XCTAssertTrue(categoriesOutput.contains("\"name\" : \"Coffee Shop\""))
        XCTAssertTrue(categoriesOutput.contains("\"checkin_count\" : 1"))
        XCTAssertTrue(categoriesOutput.contains("\"venue_count\" : 1"))
        XCTAssertTrue(visitsOutput.contains("\"command\" : \"query visits\""))
        XCTAssertTrue(visitsOutput.contains("\"venue_id\" : \"venue-1\""))
        XCTAssertTrue(visitsOutput.contains("\"total_matching_visits\" : 1"))
        XCTAssertTrue(visitsOutput.contains("\"created_at_iso8601\" : \"2023-11-14T22:13:20Z\""))
        XCTAssertTrue(visitsOutput.contains("\"local_timezone_id\""))
        XCTAssertTrue(visitsOutput.contains("America"))
        XCTAssertTrue(visitsOutput.contains("Los_Angeles"))
        XCTAssertTrue(visitsOutput.contains("\"local_timezone_offset_minutes\" : -480"))
        XCTAssertTrue(visitsOutput.contains("\"local_created_at\" : \"2023-11-14T14:13:20\""))
        XCTAssertTrue(visitsOutput.contains("\"local_date\" : \"2023-11-14\""))
        XCTAssertTrue(visitsOutput.contains("\"local_hour\" : 14"))
        XCTAssertTrue(visitsOutput.contains("\"local_weekday_iso\" : 2"))
        XCTAssertFalse(venuesOutput.contains("network"))
        XCTAssertFalse(visitsOutput.contains("network"))
    }

    func testCLIQueryVenuesSupportsNearnessFiltersAndDistanceEvidence() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        let importExit = SwarmCadenceCommand.run(
            arguments: [
                "db", "import-raw",
                "--account", "julian",
                "--db", dbURL.path,
                "--raw-dir", rawDirectory.path,
                "--format", "json"
            ],
            output: { _ in },
            errorOutput: { _ in }
        )

        var venuesOutput = ""
        let venuesExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", dbURL.path,
                "--near-lat", "37.1",
                "--near-lng", "-122.2",
                "--radius-meters", "100",
                "--limit", "10",
                "--format", "json"
            ],
            output: { venuesOutput = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(importExit, 0)
        XCTAssertEqual(venuesExit, 0)
        XCTAssertTrue(venuesOutput.contains("\"near_latitude\" : 37.1"))
        XCTAssertTrue(venuesOutput.contains("\"near_longitude\" : -122.2"))
        XCTAssertTrue(venuesOutput.contains("\"radius_meters\" : 100"))
        XCTAssertTrue(venuesOutput.contains("\"distance_meters\""))
        XCTAssertTrue(venuesOutput.contains("\"name\" : \"Cafe Example\""))
        XCTAssertTrue(venuesOutput.contains("\"total_matching_venues\" : 1"))

        var localityOutput = ""
        let localityExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", dbURL.path,
                "--locality", "San Mateo",
                "--region", "CA",
                "--country-code", "US",
                "--limit", "10",
                "--format", "json"
            ],
            output: { localityOutput = $0 },
            errorOutput: { _ in }
        )
        XCTAssertEqual(localityExit, 0)
        XCTAssertTrue(localityOutput.contains("\"locality\" : \"San Mateo\""))
        XCTAssertTrue(localityOutput.contains("\"region\" : \"CA\""))
        XCTAssertTrue(localityOutput.contains("\"country_code\" : \"US\""))
        XCTAssertTrue(localityOutput.contains("\"total_matching_venues\" : 1"))

        var categoryOutput = ""
        let categoryExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", dbURL.path,
                "--category", "Coffee Shop",
                "--limit", "10",
                "--format", "json"
            ],
            output: { categoryOutput = $0 },
            errorOutput: { _ in }
        )
        XCTAssertEqual(categoryExit, 0)
        XCTAssertTrue(categoryOutput.contains("\"category_names\" : ["))
        XCTAssertTrue(categoryOutput.contains("Coffee Shop"))
        XCTAssertTrue(categoryOutput.contains("\"total_matching_venues\" : 1"))
    }

    func testCLIQueryRejectsPartialAndInvalidGeoFiltersBeforeReadingDB() throws {
        var partialErrorOutput = ""
        let partialExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", "/tmp/does-not-matter.sqlite",
                "--near-lat", "37.1",
                "--near-lng", "-122.2",
                "--format", "json"
            ],
            output: { _ in },
            errorOutput: { partialErrorOutput = $0 }
        )

        var invalidErrorOutput = ""
        let invalidExit = SwarmCadenceCommand.run(
            arguments: [
                "query", "compare",
                "--account", "julian",
                "--db", "/tmp/does-not-matter.sqlite",
                "--baseline-from", "2020-01-01",
                "--recent-from", "2023-01-01",
                "--near-lat", "91",
                "--near-lng", "-122.2",
                "--radius-meters", "100",
                "--format", "json"
            ],
            output: { _ in },
            errorOutput: { invalidErrorOutput = $0 }
        )

        XCTAssertEqual(partialExit, 2)
        XCTAssertTrue(partialErrorOutput.contains("--near-lat, --near-lng, and --radius-meters must be used together"))
        XCTAssertEqual(invalidExit, 2)
        XCTAssertTrue(invalidErrorOutput.contains("--near-lat must be between -90 and 90"))
    }

    func testCLIQueryRejectsInvalidDateWindowBeforeReadingDB() throws {
        var errorOutput = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", "/tmp/does-not-matter.sqlite",
                "--from", "2023-11-15",
                "--to", "2023-11-14",
                "--format", "json"
            ],
            output: { _ in },
            errorOutput: { errorOutput = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(errorOutput.contains("--from must be less than or equal to --to"))
    }


    func testCLIImportRawSkipsManifestForDifferentRequestedAccount() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-alice-checkins-offset0-limit250",
            rawBody: aliceRawBody,
            account: "alice"
        )

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "db", "import-raw",
                "--account", "julian",
                "--db", dbURL.path,
                "--raw-dir", rawDirectory.path,
                "--format", "json"
            ],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"raw_files_imported\" : 0"))
        XCTAssertTrue(output.contains("\"skipped_files\" : 1"))
        XCTAssertTrue(output.contains("manifest account alice does not match requested account julian"))
    }

    func testDBStatsCanBeAccountScopedInsideSharedExplicitDB() throws {
        let directory = try makeTemporaryDirectory()
        let julianRawDirectory = directory.appendingPathComponent("julian-raw", isDirectory: true)
        let aliceRawDirectory = directory.appendingPathComponent("alice-raw", isDirectory: true)
        try FileManager.default.createDirectory(at: julianRawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliceRawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("shared.sqlite")

        try writeRawPair(
            rawDirectory: julianRawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody,
            account: "julian"
        )
        try writeRawPair(
            rawDirectory: aliceRawDirectory,
            baseName: "fixture-v2-alice-checkins-offset0-limit250",
            rawBody: aliceRawBody,
            account: "alice"
        )

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", julianRawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "alice", "--db", dbURL.path, "--raw-dir", aliceRawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        var julianStats = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "stats", "--account", "julian", "--db", dbURL.path, "--format", "json"],
            output: { julianStats = $0 },
            errorOutput: { _ in }
        ), 0)
        var aliceStats = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "stats", "--account", "alice", "--db", dbURL.path, "--format", "json"],
            output: { aliceStats = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(julianStats.contains("\"account\" : \"julian\""))
        XCTAssertTrue(aliceStats.contains("\"account\" : \"alice\""))
        XCTAssertTrue(julianStats.contains("\"raw_files\" : 1"))
        XCTAssertTrue(aliceStats.contains("\"raw_files\" : 1"))
        XCTAssertTrue(julianStats.contains("\"checkins\" : 2"))
        XCTAssertTrue(aliceStats.contains("\"checkins\" : 2"))
        XCTAssertTrue(julianStats.contains("\"venues\" : 1"))
        XCTAssertTrue(aliceStats.contains("\"venues\" : 1"))
    }


    func testCLIAuditOverlapComparesRawV2AndExportSources() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        let exportDirectory = directory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )
        try exportBody.write(to: exportDirectory.appendingPathComponent("checkins1.json"), atomically: true, encoding: .utf8)

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "audit", "overlap",
                "--account", "julian",
                "--raw-dir", rawDirectory.path,
                "--path", exportDirectory.path,
                "--format", "json"
            ],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"command\" : \"audit overlap\""))
        XCTAssertTrue(output.contains("\"v2_checkins\" : 2"))
        XCTAssertTrue(output.contains("\"export_checkins\" : 2"))
        XCTAssertTrue(output.contains("\"overlapping_checkins\" : 1"))
        XCTAssertTrue(output.contains("\"v2_only_checkins\" : 1"))
        XCTAssertTrue(output.contains("\"export_only_checkins\" : 1"))
        XCTAssertTrue(output.contains("\"timestamp_matches\" : 1"))
        XCTAssertTrue(output.contains("\"venue_id_mismatches\" : 1"))
        XCTAssertTrue(output.contains("\"field\" : \"venue_id\""))
    }


    func testCLIQueryDoesNotCreateSQLiteDBWhenMissing() throws {
        let directory = try makeTemporaryDirectory()
        let dbURL = directory.appendingPathComponent("missing.sqlite")
        var errorOutput = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["query", "venues", "--account", "julian", "--db", dbURL.path, "--format", "json"],
            output: { _ in },
            errorOutput: { errorOutput = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        XCTAssertTrue(errorOutput.contains("SQLite DB does not exist"))
    }





    func testCLIImportFilesAddsHistoricalCheckinsWithoutOverwritingV2Overlap() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        let exportDirectory = directory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )
        try exportBody.write(to: exportDirectory.appendingPathComponent("checkins1.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", rawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["db", "import-files", "--account", "julian", "--db", dbURL.path, "--path", exportDirectory.path, "--format", "json"],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"command\" : \"db import-files\""))
        XCTAssertTrue(output.contains("\"raw_files_imported\" : 1"))
        XCTAssertTrue(output.contains("\"checkins_inserted\" : 1"))
        XCTAssertTrue(output.contains("\"skipped_checkins\" : 1"))
        XCTAssertTrue(output.contains("\"quality_issue_count\" : 1"))
        XCTAssertTrue(output.contains("checkins-missing-values.csv"))
        let qualityURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("quality", isDirectory: true)
            .appendingPathComponent("checkins-missing-values.csv")
        let qualityCSV = try String(contentsOf: qualityURL, encoding: .utf8)
        XCTAssertTrue(qualityCSV.contains("checkin_id,field,created_at,source,file,lat,lng"))
        XCTAssertTrue(qualityCSV.contains("checkin-1,venue"))

        var statsOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "stats", "--account", "julian", "--db", dbURL.path, "--format", "json"],
            output: { statsOutput = $0 },
            errorOutput: { _ in }
        ), 0)
        XCTAssertTrue(statsOutput.contains("\"raw_files\" : 2"))
        XCTAssertTrue(statsOutput.contains("\"checkins\" : 3"))
    }

    func testCLIQueryCompareRendersVenueCadenceFacts() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-compare-offset0-limit250",
            rawBody: compareRawBody
        )

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", rawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "query", "compare",
                "--account", "julian",
                "--db", dbURL.path,
                "--baseline-from", "2020-01-01",
                "--recent-from", "2023-01-01",
                "--as-of", "2023-11-14T22:13:20Z",
                "--min-baseline-visits", "2",
                "--format", "json"
            ],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"command\" : \"query compare\""))
        XCTAssertTrue(output.contains("\"compare_by\" : \"venue\""))
        XCTAssertTrue(output.contains("\"Lapsed Diner\""))
        XCTAssertTrue(output.contains("\"baseline_visit_count\" : 2"))
        XCTAssertTrue(output.contains("\"recent_visit_count\" : 0"))
        XCTAssertTrue(output.contains("\"previous_visit_count\" : 2"))
        XCTAssertTrue(output.contains("\"days_since_last_visit\""))
        XCTAssertTrue(output.contains("\"drill_down\""))
        XCTAssertFalse(output.contains("best lunch"))
    }

    func testCLIQueryCompareRequiresExplicitWindows() throws {
        var errorOutput = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["query", "compare", "--account", "julian", "--recent-from", "2023-01-01"],
            output: { _ in },
            errorOutput: { errorOutput = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(errorOutput.contains("missing required --baseline-from"))
    }

    func testCLIEvidenceWindowBuildsGenericSourceBundleFromExplicitWindow() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", rawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "evidence", "window",
                "--account", "julian",
                "--db", dbURL.path,
                "--date", "2023-11-14",
                "--hour-from", "14",
                "--hour-to", "14",
                "--format", "json"
            ],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"schema\" : \"swarm_window_evidence_packet.v0\""))
        XCTAssertTrue(output.contains("\"command\" : \"evidence window\""))
        XCTAssertTrue(output.contains("\"date\" : \"2023-11-14\""))
        XCTAssertTrue(output.contains("\"hour_from\" : 14"))
        XCTAssertTrue(output.contains("\"candidate_venues\""))
        XCTAssertTrue(output.contains("\"Cafe Example\""))
        XCTAssertTrue(output.contains("\"sources\""))
        XCTAssertTrue(output.contains("swarm_checkins"))
        XCTAssertFalse(output.contains("visible_joins"))
        XCTAssertFalse(output.contains("not_joined"))
        XCTAssertFalse(output.contains("external_context"))
        XCTAssertTrue(output.contains("Check-ins are evidence of visits"))
        XCTAssertFalse(output.contains("best lunch"))
    }

    func testCLIEvidencePacketComposesVenueSupportAndCadenceFacts() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", rawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "evidence", "packet",
                "--account", "julian",
                "--db", dbURL.path,
                "--date", "2026-04-27",
                "--hour-from", "14",
                "--hour-to", "14",
                "--locality", "San Mateo",
                "--region", "CA",
                "--category", "Coffee Shop",
                "--baseline-from", "2023-01-01",
                "--recent-from", "2024-01-01",
                "--format", "json"
            ],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"schema\" : \"swarm_experimental_packet\""))
        XCTAssertTrue(output.contains("\"command\" : \"evidence packet\""))
        XCTAssertTrue(output.contains("\"target_window\""))
        XCTAssertTrue(output.contains("\"geography\""))
        XCTAssertTrue(output.contains("factual venue-location filters"))
        XCTAssertTrue(output.contains("\"category_names\" : ["))
        XCTAssertTrue(output.contains("\"venue_support\""))
        XCTAssertTrue(output.contains("\"cadence_comparison\""))
        XCTAssertTrue(output.contains("Cafe Example"))
        XCTAssertTrue(output.contains("Check-ins are evidence of visits"))
        XCTAssertFalse(output.contains("best lunch"))
        XCTAssertFalse(output.contains("open_now"))
        XCTAssertFalse(output.contains("external_context"))
    }

    func testCLIEvidenceWindowRequiresDate() throws {
        var errorOutput = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["evidence", "window", "--account", "julian", "--db", "/tmp/does-not-matter.sqlite", "--format", "json"],
            output: { _ in },
            errorOutput: { errorOutput = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(errorOutput.contains("missing required --date"))
    }

    func testCLIQueryDateAndHourFiltersUseImportedLocalSidecarFields() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit250",
            rawBody: rawBody
        )

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", rawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        var visitsOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: [
                "query", "visits",
                "--account", "julian",
                "--db", dbURL.path,
                "--date", "2023-11-14",
                "--hour-from", "14",
                "--hour-to", "14",
                "--format", "json"
            ],
            output: { visitsOutput = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(visitsOutput.contains("\"date\" : \"2023-11-14\""))
        XCTAssertTrue(visitsOutput.contains("\"hour_from\" : 14"))
        XCTAssertTrue(visitsOutput.contains("\"hour_to\" : 14"))
        XCTAssertTrue(visitsOutput.contains("\"total_matching_visits\" : 1"))
        XCTAssertTrue(visitsOutput.contains("\"checkin_id\" : \"checkin-1\""))
        XCTAssertFalse(visitsOutput.contains("checkin-2"))

        var venuesOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: [
                "query", "venues",
                "--account", "julian",
                "--db", dbURL.path,
                "--date", "2023-11-14",
                "--hour-from", "14",
                "--hour-to", "14",
                "--format", "json"
            ],
            output: { venuesOutput = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(venuesOutput.contains("\"total_matching_venues\" : 1"))
        XCTAssertTrue(venuesOutput.contains("--date"))
        XCTAssertTrue(venuesOutput.contains("2023-11-14"))
        XCTAssertTrue(venuesOutput.contains("--hour-from"))
    }

    func testCLIQueryRejectsInvalidCalendarFilters() throws {
        var errorOutput = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "query", "visits",
                "--account", "julian",
                "--db", "/tmp/does-not-matter.sqlite",
                "--date", "2023-99-99",
                "--hour-from", "20",
                "--hour-to", "10",
                "--format", "json"
            ],
            output: { _ in },
            errorOutput: { errorOutput = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(errorOutput.contains("--date must use YYYY-MM-DD") || errorOutput.contains("--hour-from"))
    }

    func testDateOnlyToBoundIncludesWholeUTCDay() throws {
        let parsed = try SwarmDatabase.parseQueryTimestamp("2023-11-14", optionName: "--to")
        XCTAssertEqual(parsed, 1_700_006_399)
    }

    private var rawBody: Data {
        """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": 3,
              "items": [
                {
                  "id": "checkin-1",
                  "createdAt": 1700000000,
                  "timeZoneOffset": -480,
                  "venue": {
                    "id": "venue-1",
                    "name": "Cafe Example",
                    "timeZone": "America/Los_Angeles",
                    "location": { "lat": 37.1, "lng": -122.2, "city": "San Mateo", "state": "CA", "postalCode": "94401", "cc": "US", "country": "United States" },
                    "categories": [
                      {
                        "id": "cat-1",
                        "name": "Coffee Shop",
                        "pluralName": "Coffee Shops",
                        "shortName": "Coffee"
                      }
                    ]
                  }
                },
                {
                  "id": "checkin-2",
                  "createdAt": 1700000100,
                  "timeZoneOffset": 0
                },
                {
                  "createdAt": 1700000200,
                  "venue": { "id": "venue-skipped", "name": "Skipped Venue" }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
    }


    private var exportBody: String {
        """
        {
          "count": 2,
          "items": [
            {
              "id": "checkin-1",
              "createdAt": "2023-11-14 22:13:20.000000",
              "type": "checkin",
              "timeZoneOffset": -480,
              "venue": null,
              "comments": { "count": 0 },
              "lat": 37.9,
              "lng": -122.9
            },
            {
              "id": "export-only-1",
              "createdAt": "2020-01-01 12:00:00.000000",
              "type": "checkin",
              "timeZoneOffset": -480,
              "venue": {
                "id": "venue-export-only",
                "name": "Export Only Cafe",
                "url": "https://app.foursquare.com/v/export-only-cafe/venue-export-only"
              },
              "comments": { "count": 0 },
              "lat": 37.3,
              "lng": -122.4
            }
          ]
        }
        """
    }


    private var compareRawBody: Data {
        """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": 4,
              "items": [
                {
                  "id": "lapsed-1",
                  "createdAt": 1577908800,
                  "timeZoneOffset": -480,
                  "venue": {
                    "id": "venue-lapsed",
                    "name": "Lapsed Diner",
                    "timeZone": "America/Los_Angeles",
                    "location": { "lat": 37.2, "lng": -122.3 },
                    "categories": [{ "id": "cat-diner", "name": "Diner" }]
                  }
                },
                {
                  "id": "lapsed-2",
                  "createdAt": 1609444800,
                  "timeZoneOffset": -480,
                  "venue": {
                    "id": "venue-lapsed",
                    "name": "Lapsed Diner",
                    "timeZone": "America/Los_Angeles",
                    "location": { "lat": 37.2, "lng": -122.3 },
                    "categories": [{ "id": "cat-diner", "name": "Diner" }]
                  }
                },
                {
                  "id": "current-1",
                  "createdAt": 1700000000,
                  "timeZoneOffset": -480,
                  "venue": {
                    "id": "venue-current",
                    "name": "Current Cafe",
                    "timeZone": "America/Los_Angeles",
                    "location": { "lat": 37.1, "lng": -122.2 },
                    "categories": [{ "id": "cat-cafe", "name": "Coffee Shop" }]
                  }
                },
                {
                  "id": "current-2",
                  "createdAt": 1700000100,
                  "timeZoneOffset": -480,
                  "venue": {
                    "id": "venue-current",
                    "name": "Current Cafe",
                    "timeZone": "America/Los_Angeles",
                    "location": { "lat": 37.1, "lng": -122.2 },
                    "categories": [{ "id": "cat-cafe", "name": "Coffee Shop" }]
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
    }


    private var aliceRawBody: Data {        String(decoding: rawBody, as: UTF8.self)
            .replacingOccurrences(of: "checkin-1", with: "alice-checkin-1")
            .replacingOccurrences(of: "checkin-2", with: "alice-checkin-2")
            .replacingOccurrences(of: "venue-1", with: "alice-venue-1")
            .replacingOccurrences(of: "venue-skipped", with: "alice-venue-skipped")
            .replacingOccurrences(of: "Cafe Example", with: "Alice Cafe Example")
            .replacingOccurrences(of: "cat-1", with: "alice-cat-1")
            .data(using: .utf8)!
    }

    private func writeRawPair(
        rawDirectory: URL,
        baseName: String,
        rawBody: Data,
        account: String = "julian",
        shaOverride: String? = nil
    ) throws {
        let rawURL = rawDirectory.appendingPathComponent(baseName).appendingPathExtension("raw.json")
        try rawBody.write(to: rawURL, options: [.atomic])

        let manifest = RawFetchManifest(
            schemaVersion: 1,
            command: "raw fetch",
            adapter: .v2,
            account: account,
            endpoint: "https://api.foursquare.com/v2/users/self/checkins",
            method: "GET",
            apiVersion: "20260427",
            limit: 250,
            offset: 0,
            pageMarker: "offset0",
            fetchedAt: "2026-04-27T00:00:00.000Z",
            httpStatusCode: 200,
            apiMetaCode: 200,
            returnedCount: 3,
            totalCount: 3,
            rateLimitLimit: nil,
            rateLimitRemaining: nil,
            rateLimitReset: nil,
            rawFileName: rawURL.lastPathComponent,
            rawBytes: rawBody.count,
            rawSha256: shaOverride ?? RawFetch.sha256Hex(rawBody)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let manifestURL = rawDirectory.appendingPathComponent(baseName).appendingPathExtension("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL, options: [.atomic])
    }

    private func escapedJSONPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "\\/")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
