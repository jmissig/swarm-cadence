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
                  "venue": {
                    "id": "venue-1",
                    "name": "Cafe Example",
                    "location": { "lat": 37.1, "lng": -122.2 },
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
                  "createdAt": 1700000100
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

    private func writeRawPair(
        rawDirectory: URL,
        baseName: String,
        rawBody: Data,
        shaOverride: String? = nil
    ) throws {
        let rawURL = rawDirectory.appendingPathComponent(baseName).appendingPathExtension("raw.json")
        try rawBody.write(to: rawURL, options: [.atomic])

        let manifest = RawFetchManifest(
            schemaVersion: 1,
            command: "raw fetch",
            adapter: .v2,
            account: "julian",
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
