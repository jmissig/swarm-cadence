import Foundation
import XCTest
@testable import SwarmCadenceCore

final class IngestUpdateTests: XCTestCase {
    func testIngestUpdateAliasIsNotAccepted() throws {
        let transport = CapturingIngestTransport(responses: [])
        var output = ""
        var error = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["ingest", "update", "--account", "julian"],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"]),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertEqual(output, "")
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(error.contains("Unexpected argument 'update'"))
    }

    func testIngestUpdateRejectsInvalidPageCountBeforeTransport() throws {
        let directory = try makeTemporaryDirectory()
        let transport = CapturingIngestTransport(responses: [])
        var error = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", directory.appendingPathComponent("raw").path,
                "--db", directory.appendingPathComponent("swarm.sqlite").path,
                "--pages", "0",
                "--format", "json"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"]),
            liveTransport: transport,
            output: { _ in },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(error.contains("--pages must be at least 1"))
        XCTAssertFalse(error.contains("secret-token"))
    }

    func testIngestUpdateMissingTokenRendersStructuredJSONAndDoesNoNetwork() throws {
        let directory = try makeTemporaryDirectory()
        let transport = CapturingIngestTransport(responses: [])
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", directory.appendingPathComponent("raw").path,
                "--db", directory.appendingPathComponent("swarm.sqlite").path,
                "--format", "json"
            ],
            environment: isolatedEnvironment(home: directory),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(IngestUpdateResult.self, from: Data(output.utf8))
        XCTAssertEqual(exit, 1)
        XCTAssertEqual(result.command, "ingest")
        XCTAssertEqual(result.status, .configMissing)
        XCTAssertFalse(result.networkPerformed)
        XCTAssertEqual(result.requestCount, 0)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertEqual(result.missingInputs, ["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"])
        XCTAssertFalse(output.contains("secret-token"))
    }

    func testIngestUpdateFetchesImportsEachPageAndStopsOnShortPage() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        let transport = CapturingIngestTransport(responses: [
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 3, items: [
                checkinJSON(id: "new-1", createdAt: 1_700_000_000, venueID: "venue-1", venueName: "Cafe One"),
                checkinJSON(id: "new-2", createdAt: 1_700_000_100, venueID: "venue-2", venueName: "Cafe Two")
            ])),
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 3, items: [
                checkinJSON(id: "new-3", createdAt: 1_700_000_200, venueID: "venue-3", venueName: "Cafe Three")
            ]))
        ])
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", rawDirectory.path,
                "--db", dbURL.path,
                "--limit", "2",
                "--pages", "4",
                "--delay-ms", "0",
                "--format", "json"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"], home: directory),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(IngestUpdateResult.self, from: Data(output.utf8))
        let offsets = try requestOffsets(transport.requests)
        let stats = try SwarmDatabase.stats(dbPath: dbURL.path, account: "julian")

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(result.command, "ingest")
        XCTAssertEqual(result.status, .updated)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.requestCount, 2)
        XCTAssertEqual(result.fetchedPages, 2)
        XCTAssertEqual(result.importedPages, 2)
        XCTAssertEqual(result.checkinsInserted, 3)
        XCTAssertEqual(result.rawFilesInserted, 2)
        XCTAssertEqual(offsets, ["0", "2"])
        XCTAssertTrue(result.stopReason?.contains("returned 1 below limit 2") ?? false)
        XCTAssertEqual(stats.checkins, 3)
        XCTAssertEqual(stats.latestCreatedAtISO8601, "2023-11-14T22:16:40Z")
        XCTAssertFalse(output.contains("secret-token"))
    }

    func testIngestUpdateStopsAsNoNewWhenFetchedPageContainsExistingIDs() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit2",
            rawBody: pageBody(total: 2, items: [
                checkinJSON(id: "existing-1", createdAt: 1_700_000_000, venueID: "venue-1", venueName: "Cafe One"),
                checkinJSON(id: "existing-2", createdAt: 1_700_000_100, venueID: "venue-2", venueName: "Cafe Two")
            ]),
            limit: 2
        )
        _ = try SwarmDatabase.importRawV2Checkins(
            dbPath: dbURL.path,
            rawDirectory: rawDirectory.path,
            account: "julian",
            importedAt: Date(timeIntervalSince1970: 1_777_291_201)
        )

        let transport = CapturingIngestTransport(responses: [
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 2, items: [
                checkinJSON(id: "existing-1", createdAt: 1_700_000_000, venueID: "venue-1", venueName: "Cafe One"),
                checkinJSON(id: "existing-2", createdAt: 1_700_000_100, venueID: "venue-2", venueName: "Cafe Two")
            ]))
        ])
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", rawDirectory.path,
                "--db", dbURL.path,
                "--limit", "2",
                "--pages", "4",
                "--delay-ms", "0",
                "--format", "json"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"], home: directory),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(IngestUpdateResult.self, from: Data(output.utf8))
        XCTAssertEqual(exit, 0)
        XCTAssertEqual(result.status, .noNewCheckins)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.requestCount, 1)
        XCTAssertEqual(result.importedPages, 0)
        XCTAssertEqual(result.checkinsInserted, 0)
        XCTAssertEqual(result.rawFilesInserted, 0)
        XCTAssertEqual(result.pages.first?.existingCheckinIDsObserved, 2)
        XCTAssertTrue(result.stopReason?.contains("all observed check-in ids already exist locally") ?? false)
        let freshnessAfter = try SwarmDatabase.freshness(dbPath: dbURL.path, account: "julian", adapter: "v2")
        XCTAssertEqual(freshnessAfter.lastImportedAtISO8601, "2026-04-27T12:00:01Z")
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: dbURL.path, account: "julian").rawFiles, 1)
        XCTAssertEqual(try rawFileCount(in: rawDirectory), 2)
    }

    func testIngestUpdateImportsV2OverlapWhenExistingIDIsExportOnly() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        let exportDirectory = directory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        try """
        {
          "count": 1,
          "items": [
            {
              "id": "overlap-1",
              "createdAt": "2023-11-14 22:18:20.000000",
              "type": "checkin",
              "timeZoneOffset": -480,
              "venue": null,
              "comments": { "count": 0 },
              "lat": 37.3,
              "lng": -122.4
            }
          ]
        }
        """.write(to: exportDirectory.appendingPathComponent("checkins1.json"), atomically: true, encoding: .utf8)
        _ = try SwarmDatabase.importFiles(dbPath: dbURL.path, path: exportDirectory.path, account: "julian")

        XCTAssertEqual(try SwarmDatabase.existingCheckinIDs(dbPath: dbURL.path, account: "julian"), ["overlap-1"])
        XCTAssertEqual(try SwarmDatabase.existingCheckinIDs(dbPath: dbURL.path, account: "julian", adapter: "v2"), [])

        let transport = CapturingIngestTransport(responses: [
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 1, items: [
                checkinJSON(id: "overlap-1", createdAt: 1_700_000_300, venueID: "venue-v2", venueName: "V2 Cafe")
            ]))
        ])
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", rawDirectory.path,
                "--db", dbURL.path,
                "--limit", "2",
                "--pages", "4",
                "--delay-ms", "0",
                "--format", "json"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"], home: directory),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(IngestUpdateResult.self, from: Data(output.utf8))
        let v2Freshness = try SwarmDatabase.freshness(dbPath: dbURL.path, account: "julian", adapter: "v2")

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(result.status, .updated)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.requestCount, 1)
        XCTAssertEqual(result.importedPages, 1)
        XCTAssertEqual(result.checkinsInserted, 0)
        XCTAssertEqual(result.rawFilesInserted, 1)
        XCTAssertEqual(result.pages.first?.existingCheckinIDsObserved, 0)
        XCTAssertEqual(try SwarmDatabase.existingCheckinIDs(dbPath: dbURL.path, account: "julian", adapter: "v2"), ["overlap-1"])
        XCTAssertTrue(output.contains("\"current_through_iso8601\" : \"2023-11-14T22:18:20Z\""))
        XCTAssertEqual(v2Freshness.currentThroughISO8601, "2023-11-14T22:18:20Z")
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: dbURL.path, account: "julian").rawFiles, 2)
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: dbURL.path, account: "julian").checkins, 1)
    }

    func testIngestUpdateImportsMixedOverlapPageThenStopsComplete() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit1",
            rawBody: pageBody(total: 1, items: [
                checkinJSON(id: "existing-1", createdAt: 1_700_000_000, venueID: "venue-1", venueName: "Cafe One")
            ]),
            limit: 1
        )
        _ = try SwarmDatabase.importRawV2Checkins(dbPath: dbURL.path, rawDirectory: rawDirectory.path, account: "julian")

        let transport = CapturingIngestTransport(responses: [
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 2, items: [
                checkinJSON(id: "new-1", createdAt: 1_700_000_100, venueID: "venue-2", venueName: "Cafe Two"),
                checkinJSON(id: "existing-1", createdAt: 1_700_000_000, venueID: "venue-1", venueName: "Cafe One")
            ]))
        ])
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", rawDirectory.path,
                "--db", dbURL.path,
                "--limit", "2",
                "--pages", "4",
                "--delay-ms", "0",
                "--format", "json"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"], home: directory),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(IngestUpdateResult.self, from: Data(output.utf8))
        let stats = try SwarmDatabase.stats(dbPath: dbURL.path, account: "julian")

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(result.status, .updated)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.requestCount, 1)
        XCTAssertEqual(result.importedPages, 1)
        XCTAssertEqual(result.checkinsInserted, 1)
        XCTAssertEqual(result.rawFilesInserted, 1)
        XCTAssertEqual(result.pages.first?.existingCheckinIDsObserved, 1)
        XCTAssertTrue(result.stopReason?.contains("existing local check-in id") ?? false)
        XCTAssertEqual(stats.checkins, 2)
        XCTAssertEqual(stats.rawFiles, 2)
    }

    func testIngestUpdateSourceBlockedReturnsJSONAndNonZeroExit() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        let body = """
        {
          "meta": {
            "code": 401,
            "errorType": "invalid_auth",
            "errorDetail": "token secret-token is invalid"
          },
          "response": {}
        }
        """.data(using: .utf8)!
        let transport = CapturingIngestTransport(responses: [
            ProbeHTTPResponse(statusCode: 401, data: body)
        ])
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "ingest",
                "--account", "julian",
                "--adapter", "v2",
                "--raw-dir", rawDirectory.path,
                "--db", dbURL.path,
                "--format", "json"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "secret-token"], home: directory),
            liveTransport: transport,
            output: { output = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(IngestUpdateResult.self, from: Data(output.utf8))
        XCTAssertEqual(exit, 1)
        XCTAssertEqual(result.status, .sourceBlocked)
        XCTAssertEqual(result.sourceStatus, .unauthorized)
        XCTAssertTrue(result.networkPerformed)
        XCTAssertEqual(result.requestCount, 1)
        XCTAssertFalse(output.contains("secret-token"))
    }

    func testStatsAndEvidencePacketIncludeFreshnessFields() throws {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        try writeRawPair(
            rawDirectory: rawDirectory,
            baseName: "fixture-v2-julian-checkins-offset0-limit1",
            rawBody: pageBody(total: 1, items: [
                checkinJSON(id: "fresh-1", createdAt: 1_700_000_000, venueID: "venue-1", venueName: "Cafe One")
            ]),
            fetchedAt: "2026-04-27T12:00:00.000Z",
            limit: 1
        )
        _ = try SwarmDatabase.importRawV2Checkins(
            dbPath: dbURL.path,
            rawDirectory: rawDirectory.path,
            account: "julian",
            importedAt: Date(timeIntervalSince1970: 1_777_291_201)
        )

        var statsOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "stats", "--account", "julian", "--db", dbURL.path, "--format", "json"],
            output: { statsOutput = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(statsOutput.contains("\"last_fetched_at_iso8601\" : \"2026-04-27T12:00:00.000Z\""))
        XCTAssertTrue(statsOutput.contains("\"last_imported_at_iso8601\" : \"2026-04-27T12:00:01Z\""))
        XCTAssertTrue(statsOutput.contains("\"current_through_iso8601\" : \"2023-11-14T22:13:20Z\""))

        var evidenceOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: [
                "evidence", "packet",
                "--account", "julian",
                "--db", dbURL.path,
                "--date", "2026-04-27",
                "--baseline-from", "2023-01-01",
                "--recent-from", "2024-01-01",
                "--format", "json"
            ],
            output: { evidenceOutput = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(evidenceOutput.contains("\"source_coverage\""))
        XCTAssertTrue(evidenceOutput.contains("\"last_fetched_at_iso8601\" : \"2026-04-27T12:00:00.000Z\""))
        XCTAssertTrue(evidenceOutput.contains("\"last_imported_at_iso8601\" : \"2026-04-27T12:00:01Z\""))
        XCTAssertTrue(evidenceOutput.contains("\"current_through_iso8601\" : \"2023-11-14T22:13:20Z\""))
    }

    private func requestOffsets(_ requests: [URLRequest]) throws -> [String] {
        try requests.map { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            return queryItems["offset"] ?? ""
        }
    }

    private func rawFileCount(in directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".raw.json") }
            .count
    }

    private func isolatedEnvironment(_ values: [String: String] = [:], home: URL? = nil) -> [String: String] {
        var environment = ["HOME": (home ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)).path]
        for (key, value) in values {
            environment[key] = value
        }
        return environment
    }

    private func pageBody(total: Int, items: [String]) -> Data {
        """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": \(total),
              "items": [\(items.joined(separator: ","))]
            }
          }
        }
        """.data(using: .utf8)!
    }

    private func checkinJSON(id: String, createdAt: Int, venueID: String, venueName: String) -> String {
        """
        {
          "id": "\(id)",
          "createdAt": \(createdAt),
          "timeZoneOffset": -480,
          "venue": {
            "id": "\(venueID)",
            "name": "\(venueName)",
            "timeZone": "America/Los_Angeles",
            "location": { "lat": 37.1, "lng": -122.2, "city": "San Mateo", "state": "CA", "cc": "US" },
            "categories": [{ "id": "cat-coffee", "name": "Coffee Shop" }]
          }
        }
        """
    }

    private func writeRawPair(
        rawDirectory: URL,
        baseName: String,
        rawBody: Data,
        account: String = "julian",
        fetchedAt: String = "2026-04-27T00:00:00.000Z",
        limit: Int
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
            limit: limit,
            offset: 0,
            pageMarker: "offset0",
            fetchedAt: fetchedAt,
            httpStatusCode: 200,
            apiMetaCode: 200,
            returnedCount: limit,
            totalCount: limit,
            rateLimitLimit: nil,
            rateLimitRemaining: nil,
            rateLimitReset: nil,
            rawFileName: rawURL.lastPathComponent,
            rawBytes: rawBody.count,
            rawSha256: RawFetch.sha256Hex(rawBody)
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

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private final class CapturingIngestTransport: ProbeHTTPTransport {
    private var responses: [ProbeHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [ProbeHTTPResponse]) {
        self.responses = responses
    }

    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        requests.append(request)
        if responses.isEmpty {
            throw ProbeTransportError("unexpected extra request")
        }
        return responses.removeFirst()
    }
}
