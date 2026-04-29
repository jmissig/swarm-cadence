import Foundation
import XCTest
@testable import SwarmCadenceCore

final class AnnotationsTests: XCTestCase {
    func testAddAndListAnnotationsByTarget() throws {
        let directory = try makeTemporaryDirectory()
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        let first = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "venue",
            targetID: "venue-1",
            body: "Good for a quick coffee, not a lunch plan.",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "context",
            targetID: "with-kids",
            body: "Only useful when the whole family is nearby.",
            source: "human",
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let venueAnnotations = try SwarmDatabase.listAnnotations(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "venue",
            targetID: "venue-1"
        )
        let allAnnotations = try SwarmDatabase.listAnnotations(dbPath: dbURL.path, account: "julian")

        XCTAssertEqual(first.command, "annotations add")
        XCTAssertEqual(first.annotation.account, "julian")
        XCTAssertEqual(first.annotation.targetKind, "venue")
        XCTAssertEqual(first.annotation.targetID, "venue-1")
        XCTAssertEqual(first.annotation.body, "Good for a quick coffee, not a lunch plan.")
        XCTAssertEqual(first.annotation.source, "human")
        XCTAssertEqual(first.annotation.createdAtISO8601, "2023-11-14T22:13:20Z")
        XCTAssertEqual(venueAnnotations.command, "annotations list")
        XCTAssertEqual(venueAnnotations.totalMatchingAnnotations, 1)
        XCTAssertEqual(venueAnnotations.returnedAnnotations, 1)
        XCTAssertEqual(venueAnnotations.annotations.first?.id, first.annotation.id)
        XCTAssertEqual(allAnnotations.totalMatchingAnnotations, 2)
        XCTAssertEqual(allAnnotations.returnedAnnotations, 2)
        XCTAssertEqual(allAnnotations.annotations.first?.targetKind, "context")
    }


    func testAnnotationsNormalizeTargetKindAndRejectUnknownKinds() throws {
        let directory = try makeTemporaryDirectory()
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        let added = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: " Geography ",
            targetID: "burlingame-lunch-radius",
            body: "This geography can carry flexible local meaning.",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(added.annotation.targetKind, "geography")
        XCTAssertEqual(added.annotation.targetID, "burlingame-lunch-radius")

        XCTAssertThrowsError(try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "favorite",
            targetID: "venue-1",
            body: "Do not make target kinds into preference labels."
        )) { error in
            XCTAssertTrue(String(describing: error).contains("unsupported --target-kind"))
        }
    }

    func testCLIAnnotationsAddAndListRenderJSON() throws {
        let directory = try makeTemporaryDirectory()
        let dbURL = directory.appendingPathComponent("swarm.sqlite")

        var addOutput = ""
        let addExit = SwarmCadenceCommand.run(
            arguments: [
                "annotations", "add",
                "--account", "julian",
                "--db", dbURL.path,
                "--target-kind", "category",
                "--target-id", "Coffee Shop",
                "--body", "Coffee category annotations are attached context, not source evidence.",
                "--format", "json"
            ],
            output: { addOutput = $0 },
            errorOutput: { _ in }
        )

        var listOutput = ""
        let listExit = SwarmCadenceCommand.run(
            arguments: [
                "annotations", "list",
                "--account", "julian",
                "--db", dbURL.path,
                "--target-kind", "category",
                "--target-id", "Coffee Shop",
                "--format", "json"
            ],
            output: { listOutput = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(addExit, 0)
        XCTAssertEqual(listExit, 0)
        XCTAssertTrue(addOutput.contains("\"command\" : \"annotations add\""))
        XCTAssertTrue(addOutput.contains("\"target_kind\" : \"category\""))
        XCTAssertTrue(addOutput.contains("\"target_id\" : \"Coffee Shop\""))
        XCTAssertTrue(addOutput.contains("\"body\" : \"Coffee category annotations are attached context, not source evidence.\""))
        XCTAssertTrue(listOutput.contains("\"command\" : \"annotations list\""))
        XCTAssertTrue(listOutput.contains("\"total_matching_annotations\" : 1"))
        XCTAssertTrue(listOutput.contains("\"returned_annotations\" : 1"))
        XCTAssertTrue(listOutput.contains("\"kind\" : \"category\""))
        XCTAssertTrue(listOutput.contains("\"id\" : \"Coffee Shop\""))
        XCTAssertFalse(listOutput.contains("checkins_upserted"))
    }

    func testCLIAnnotationsKindsAndTargetsSupportDiscovery() throws {
        let dbURL = try makeEvidenceDatabaseWithAnnotations()

        var kindsOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["annotations", "kinds", "--format", "json"],
            output: { kindsOutput = $0 },
            errorOutput: { _ in }
        ), 0)

        var targetsOutput = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["annotations", "targets", "--account", "julian", "--db", dbURL.path, "--kind", "category", "--format", "json"],
            output: { targetsOutput = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(kindsOutput.contains("\"geography\""))
        XCTAssertTrue(kindsOutput.contains("\"context\""))
        XCTAssertTrue(targetsOutput.contains("\"command\" : \"annotations targets\""))
        XCTAssertTrue(targetsOutput.contains("\"kind\" : \"category\""))
        XCTAssertTrue(targetsOutput.contains("\"id\" : \"Coffee Shop\""))
        XCTAssertTrue(targetsOutput.contains("\"annotation_count\" : 1"))
    }

    func testCLIAnnotationsListRequiresTargetKindAndIDTogether() throws {
        let directory = try makeTemporaryDirectory()
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        var errorOutput = ""

        let exit = SwarmCadenceCommand.run(
            arguments: [
                "annotations", "list",
                "--account", "julian",
                "--db", dbURL.path,
                "--target-kind", "venue"
            ],
            output: { _ in },
            errorOutput: { errorOutput = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(errorOutput.contains("--target-kind requires --target-id."))
    }

    func testQueryEntitiesIncludeAnnotationsInlineByDefault() throws {
        let dbURL = try makeEvidenceDatabaseWithAnnotations()

        var venuesJSON = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "venues", "--account", "julian", "--db", dbURL.path, "--format", "json"],
            output: { venuesJSON = $0 },
            errorOutput: { _ in }
        ), 0)

        var visitsJSON = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "visits", "--account", "julian", "--db", dbURL.path, "--venue-id", "venue-1", "--format", "json"],
            output: { visitsJSON = $0 },
            errorOutput: { _ in }
        ), 0)

        var categoriesJSON = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "categories", "--account", "julian", "--db", dbURL.path, "--format", "json"],
            output: { categoriesJSON = $0 },
            errorOutput: { _ in }
        ), 0)

        var venuesText = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "venues", "--account", "julian", "--db", dbURL.path, "--format", "text"],
            output: { venuesText = $0 },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(venuesJSON.contains("\"annotations\""))
        XCTAssertTrue(venuesJSON.contains("Venue-level annotation."))
        XCTAssertTrue(visitsJSON.contains("\"annotations\""))
        XCTAssertTrue(visitsJSON.contains("Check-in-specific annotation."))
        XCTAssertTrue(visitsJSON.contains("Venue-level annotation."))
        XCTAssertTrue(categoriesJSON.contains("\"annotations\""))
        XCTAssertTrue(categoriesJSON.contains("Category ID annotation."))
        XCTAssertTrue(categoriesJSON.contains("Category name annotation."))
        XCTAssertTrue(venuesText.contains("annotations:"))
        XCTAssertTrue(venuesText.contains("Venue-level annotation."))
    }

    func testQueryNoAnnotationsOmitsInlineAnnotations() throws {
        let dbURL = try makeEvidenceDatabaseWithAnnotations()

        var venuesJSON = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "venues", "--account", "julian", "--db", dbURL.path, "--no-annotations", "--format", "json"],
            output: { venuesJSON = $0 },
            errorOutput: { _ in }
        ), 0)

        var visitsJSON = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "visits", "--account", "julian", "--db", dbURL.path, "--venue-id", "venue-1", "--no-annotations", "--format", "json"],
            output: { visitsJSON = $0 },
            errorOutput: { _ in }
        ), 0)

        var categoriesJSON = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["query", "categories", "--account", "julian", "--db", dbURL.path, "--no-annotations", "--format", "json"],
            output: { categoriesJSON = $0 },
            errorOutput: { _ in }
        ), 0)

        for output in [venuesJSON, visitsJSON, categoriesJSON] {
            XCTAssertFalse(output.contains("annotations"))
            XCTAssertFalse(output.contains("Venue-level annotation."))
            XCTAssertFalse(output.contains("Check-in-specific annotation."))
            XCTAssertFalse(output.contains("Category ID annotation."))
            XCTAssertFalse(output.contains("Category name annotation."))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeEvidenceDatabaseWithAnnotations() throws -> URL {
        let directory = try makeTemporaryDirectory()
        let rawDirectory = directory.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swarm.sqlite")
        try writeRawPair(rawDirectory: rawDirectory, baseName: "fixture-v2-julian-checkins-offset0-limit250", rawBody: rawBody)

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["db", "import-raw", "--account", "julian", "--db", dbURL.path, "--raw-dir", rawDirectory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 0)

        _ = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "venue",
            targetID: "venue-1",
            body: "Venue-level annotation.",
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )
        _ = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "checkin",
            targetID: "checkin-1",
            body: "Check-in-specific annotation.",
            now: Date(timeIntervalSince1970: 1_700_000_300)
        )
        _ = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "category",
            targetID: "cat-1",
            body: "Category ID annotation.",
            now: Date(timeIntervalSince1970: 1_700_000_400)
        )
        _ = try SwarmDatabase.addAnnotation(
            dbPath: dbURL.path,
            account: "julian",
            targetKind: "category",
            targetID: "Coffee Shop",
            body: "Category name annotation.",
            now: Date(timeIntervalSince1970: 1_700_000_500)
        )

        return dbURL
    }

    private var rawBody: Data {
        """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": 1,
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
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
    }

    private func writeRawPair(rawDirectory: URL, baseName: String, rawBody: Data) throws {
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
            returnedCount: 1,
            totalCount: 1,
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
}
