import Foundation
import GRDB
import XCTest
@testable import SwarmCadenceCore
@testable import SwarmCadenceCommands

struct EvidenceFixture {
    let root: URL
    var db: String { root.appendingPathComponent("evidence.sqlite").path }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func item(_ id: String, time: Int = 1_705_320_000, category: String = "Coffee Shop") -> [String: Any] {
        ["id": id, "createdAt": time, "timeZoneOffset": 0,
         "venue": ["id": "v1", "name": "Fixture Cafe", "categories": [["id": category, "name": category]]]]
    }
    func raw(_ name: String, account: String = "review", items: [[String: Any]], directory: String = "raw") throws -> URL {
        let folder = root.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["meta": ["code": 200], "response": ["checkins": ["items": items, "count": items.count]]])
        try data.write(to: folder.appendingPathComponent(name + ".raw.json"))
        let manifest = RawFetchManifest(schemaVersion: 1, command: "raw fetch", adapter: .v2, account: account,
            endpoint: "fixture", method: "GET", apiVersion: "20260427", limit: 250, offset: 0,
            pageMarker: "offset0", fetchedAt: "2026-09-01T00:00:00Z", httpStatusCode: 200,
            apiMetaCode: 200, returnedCount: items.count, totalCount: items.count,
            rateLimitLimit: nil, rateLimitRemaining: nil, rateLimitReset: nil,
            rawFileName: name + ".raw.json", rawBytes: data.count, rawSha256: RawFetch.sha256Hex(data))
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(name + ".manifest.json"))
        return folder
    }
    func export(_ name: String, items: [[String: Any]]) throws -> String {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["items": items], options: [.sortedKeys]).write(to: folder.appendingPathComponent("checkins1.json"))
        return folder.path
    }
}

final class EvidenceCorrectnessTests: XCTestCase {
    func testExportBasenamesCannotOverwriteProvenanceAcrossAccountsOrSnapshots() throws {
        let f = try EvidenceFixture()
        for (account, name, id) in [("review", "one", "c1"), ("review", "two", "c2"), ("partner", "three", "c3")] {
            let path = try f.export(name, items: [f.item(id)])
            _ = try SwarmDatabase.importFiles(dbPath: f.db, path: path, account: account)
            _ = try SwarmDatabase.importFiles(dbPath: f.db, path: path, account: account)
        }
        let queue = try DatabaseQueue(path: f.db)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM raw_files"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM checkins c JOIN raw_files r ON r.id=c.raw_file_id WHERE c.account != r.account"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM checkins"), 3)
        }
    }
    func testAuditRejectsOtherAccountManifest() throws {
        let f = try EvidenceFixture()
        let raw = try f.raw("one", items: [f.item("c1")])
        let exported = try f.export("export", items: [f.item("c1")])
        XCTAssertThrowsError(try SourceAudit.overlap(account: "partner", v2RawDirectory: raw.path, exportPath: exported))
    }
    func testCheckinCannotBeReassignedToAnotherAccount() throws {
        let f = try EvidenceFixture()
        let first = try f.raw("one", items: [f.item("c1")])
        _ = try SwarmDatabase.importRawV2Checkins(dbPath: f.db, rawDirectory: first.path, account: "review")
        let other = try f.raw("two", account: "partner", items: [f.item("c1")], directory: "partner")
        XCTAssertThrowsError(try SwarmDatabase.importRawV2Checkins(dbPath: f.db, rawDirectory: other.path, account: "partner"))
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: f.db, account: "review").checkins, 1)
    }
}

extension EvidenceCorrectnessTests {
    func testDisjointWindowsAndEndDatesIncludeIndependentRecentVisits() throws {
        let f = try EvidenceFixture()
        let raw = try f.raw("visits", items: [f.item("old"), f.item("recent", time: 1_736_942_400)])
        _ = try SwarmDatabase.importRawV2Checkins(dbPath: f.db, rawDirectory: raw.path, account: "review")
        let result = try SwarmDatabase.queryCompare(dbPath: f.db, account: "review", baselineFromCreatedAt: 1_704_067_200,
            baselineToCreatedAt: 1_735_603_199, recentFromCreatedAt: 1_735_689_600, recentToCreatedAt: 1_767_225_599)
        XCTAssertEqual(result.venues[0].baselineVisitCount, 1)
        XCTAssertEqual(result.venues[0].recentVisitCount, 1)
        XCTAssertEqual(try SwarmDatabase.parseQueryTimestamp("2025-01-15", optionName: "--recent-to"), 1_736_985_599)
        XCTAssertThrowsError(try SwarmDatabase.parseQueryTimestamp("2025-02-30", optionName: "--baseline-to"))
    }
    func testCategoryDrillDownReproducesSummarySupport() throws {
        let f = try EvidenceFixture()
        let raw = try f.raw("visits", items: [f.item("coffee"), f.item("bakery", time: 1_736_942_400, category: "Bakery")])
        _ = try SwarmDatabase.importRawV2Checkins(dbPath: f.db, rawDirectory: raw.path, account: "review")
        let result = try SwarmDatabase.queryVenues(dbPath: f.db, account: "review", categoryNames: ["Bakery"])
        var output = ""
        let code = SwarmCadenceCommand.run(arguments: result.venues[0].drillDown.arguments + ["--format", "json"], environment: [:], output: { output = $0 })
        XCTAssertEqual(code, 0)
        let resultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(resultJSON["total_matching_visits"] as? Int, result.venues[0].visitCount)
        XCTAssertEqual((resultJSON["visits"] as? [[String: Any]])?.compactMap { $0["checkin_id"] as? String }, ["bakery"])
    }
}

extension EvidenceCorrectnessTests {
    func testLegacyMigrationPreservesReferencesAndAnnotationsWithoutCertifyingHistory() throws {
        let f = try EvidenceFixture()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/legacy-v4.sql")
        let queue = try DatabaseQueue(path: f.db)
        try queue.write { db in
            try db.execute(sql: String(contentsOf: fixture))
            try db.execute(sql: """
                INSERT INTO raw_files(id,relative_path,raw_file_name,manifest_file_name,sha256,bytes,fetched_at,adapter,account,endpoint,api_version,"limit","offset",http_status,imported_at)
                VALUES (7,'checkins1.json','checkins1.json','','legacy-overwritten',1,'2020-01-01T00:00:00Z','export','partner','fixture','export',1,0,0,'2020-01-01T00:00:00Z');
                INSERT INTO checkins(checkin_id,account,source_adapter,raw_file_id,raw_json,imported_at)
                VALUES ('old','review','export',7,'{}','2020-01-01T00:00:00Z');
                INSERT INTO annotations(id,account,target_kind,target_id,body,source,created_at,updated_at)
                VALUES (11,'review','checkin','old','Keep this annotation','human','2020-01-01','2020-01-01');
                """)
        }
        _ = try SwarmDatabase.migrateDatabase(dbPath: f.db, account: "review")
        _ = try SwarmDatabase.migrateDatabase(dbPath: f.db, account: "review")
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT raw_file_id FROM checkins WHERE checkin_id='old'"), 7)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT body FROM annotations WHERE id=11"), "Keep this annotation")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT provenance_verified FROM raw_files WHERE id=7"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source_observations"), 0)
        }
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: f.db, account: "partner").unverifiedSourceFiles, 1)
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: f.db, account: "review").sync.historyCoverage, "unknown")
    }

    func testRelocatedIdenticalExportReusesContentIdentity() throws {
        let f = try EvidenceFixture()
        for folder in ["original", "relocated"] {
            let path = try f.export(folder, items: [f.item("c1")])
            _ = try SwarmDatabase.importFiles(dbPath: f.db, path: path, account: "review")
        }
        XCTAssertEqual(try SwarmDatabase.stats(dbPath: f.db, account: "review").rawFiles, 1)
        let queue = try DatabaseQueue(path: f.db)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source_observations"), 2)
        }
    }

    func testComparisonWindowDrillDownsAreIndependent() throws {
        let f = try EvidenceFixture()
        let raw = try f.raw("visits", items: [f.item("old"), f.item("new", time: 1_736_942_400)])
        _ = try SwarmDatabase.importRawV2Checkins(dbPath: f.db, rawDirectory: raw.path, account: "review")
        for baselineEnd in [1_735_603_199, 1_767_225_599] {
            let result = try SwarmDatabase.queryCompare(dbPath: f.db, account: "review", baselineFromCreatedAt: 1_704_067_200,
                baselineToCreatedAt: baselineEnd, recentFromCreatedAt: 1_735_689_600)
            let venue = result.venues[0]
            for (drill, expected) in [(venue.baselineDrillDown, venue.baselineVisitCount), (venue.recentDrillDown, venue.recentVisitCount)] {
                var output = ""
                XCTAssertEqual(SwarmCadenceCommand.run(arguments: drill.arguments + ["--format", "json"], environment: [:], output: { output = $0 }), 0)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
                XCTAssertEqual(json["total_matching_visits"] as? Int, expected)
            }
        }
    }
}

extension EvidenceCorrectnessTests {
    func testFailedSchemaMigrationRollsBackItsChanges() throws {
        let f = try EvidenceFixture()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/legacy-v4.sql")
        let queue = try DatabaseQueue(path: f.db)
        try queue.write { db in
            try db.execute(sql: String(contentsOf: fixture))
            // Simulate a conflicting locally created object: v5 must not leave
            // half of its schema applied when creation of its second object fails.
            try db.execute(sql: "CREATE TABLE source_observations (id INTEGER PRIMARY KEY)")
        }
        XCTAssertThrowsError(try SwarmDatabase.migrateDatabase(dbPath: f.db, account: "review"))
        try queue.read { db in
            XCTAssertFalse(try db.columns(in: "raw_files").contains { $0.name == "provenance_verified" })
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier='v5_source_artifacts'"), 0)
            XCTAssertTrue(try db.tableExists("annotations"))
        }
    }
}
