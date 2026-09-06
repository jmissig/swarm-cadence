import Foundation
import XCTest
@testable import SwarmCadenceCore

private struct SyncFixtureTransport: ProbeHTTPTransport {
    var items: [[String: Any]]
    var total: Int
    var status = 200
    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        ProbeHTTPResponse(statusCode: status, data: try JSONSerialization.data(withJSONObject:
            ["meta": ["code": status], "response": ["checkins": ["count": total, "items": items]]]))
    }
}

final class SyncStateTests: XCTestCase {
    func testNoNewDataAdvancesCheckButNotImportAndCannotCompletePartialHistory() throws {
        let f = try EvidenceFixture()
        let transport = SyncFixtureTransport(items: [f.item("c1"), f.item("c2")], total: 3)
        let environment = ["SWARM_CADENCE_REVIEW_V2_ACCESS_TOKEN": "fixture-only"]
        let first = try IngestUpdate.update(account: "review", adapter: .v2, environment: environment,
            rawDirectory: f.root.appendingPathComponent("raw").path, dbPath: f.db, pages: 1, limit: 2,
            transport: transport, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let second = try IngestUpdate.update(account: "review", adapter: .v2, environment: environment,
            rawDirectory: f.root.appendingPathComponent("raw").path, dbPath: f.db, pages: 2, limit: 2,
            transport: transport, now: { Date(timeIntervalSince1970: 1_800_086_400) })
        XCTAssertFalse(first.complete)
        XCTAssertTrue(second.complete)
        XCTAssertEqual(second.status, .noNewCheckins)
        XCTAssertEqual(second.checkinsInserted, 0)
        XCTAssertNotEqual(first.freshnessAfter?.lastFetchedAtISO8601, second.freshnessAfter?.lastFetchedAtISO8601)
        XCTAssertEqual(first.freshnessAfter?.lastImportedAtISO8601, second.freshnessAfter?.lastImportedAtISO8601)
        XCTAssertEqual(second.freshnessAfter?.sync.historyCoverage, "partial")
        let failed = try IngestUpdate.update(account: "review", adapter: .v2, environment: environment,
            rawDirectory: f.root.appendingPathComponent("raw").path, dbPath: f.db, pages: 1, limit: 2,
            transport: SyncFixtureTransport(items: [], total: 0, status: 401), now: { Date(timeIntervalSince1970: 1_800_172_800) })
        XCTAssertEqual(failed.freshnessAfter?.sync.lastSuccessfulCheckAt, second.freshnessAfter?.sync.lastSuccessfulCheckAt)
        XCTAssertEqual(failed.freshnessAfter?.sync.lastRunStatus, "source_blocked")
    }
    func testEmptySuccessfulAccountHasVerifiedAsOfCoverage() throws {
        let f = try EvidenceFixture()
        let result = try IngestUpdate.update(account: "review", adapter: .v2,
            environment: ["SWARM_CADENCE_REVIEW_V2_ACCESS_TOKEN": "fixture-only"],
            rawDirectory: f.root.appendingPathComponent("raw").path, dbPath: f.db, pages: 1,
            transport: SyncFixtureTransport(items: [], total: 0))
        XCTAssertEqual(result.freshnessAfter?.sync.historyCoverage, "verified_as_of")
        XCTAssertNil(result.freshnessAfter?.currentThroughISO8601)
    }
}

private struct MalformedSyncTransport: ProbeHTTPTransport {
    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        ProbeHTTPResponse(statusCode: 200, data: Data("{}".utf8))
    }
}

extension SyncStateTests {
    func testMalformedPageCannotAdvanceSuccessfulCheckOrCoverage() throws {
        let f = try EvidenceFixture()
        let result = try IngestUpdate.update(account: "review", adapter: .v2,
            environment: ["SWARM_CADENCE_REVIEW_V2_ACCESS_TOKEN": "fixture-only"],
            rawDirectory: f.root.appendingPathComponent("raw").path, dbPath: f.db, pages: 1,
            transport: MalformedSyncTransport())
        XCTAssertEqual(result.status, .importFailed)
        XCTAssertEqual(result.importedPages, 0)
        XCTAssertNil(result.freshnessAfter?.sync.lastSuccessfulCheckAt)
        XCTAssertEqual(result.freshnessAfter?.sync.historyCoverage, "partial")
    }
}

extension SyncStateTests {
    func testNoNewFetchAdvancesWithinSameSecondAcrossTimestampFormats() throws {
        let f = try EvidenceFixture()
        let raw = try f.raw("original", items: [f.item("c1")])
        _ = try SwarmDatabase.importRawV2Checkins(dbPath: f.db, rawDirectory: raw.path, account: "review")
        let base = ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!
        let result = try IngestUpdate.update(account: "review", adapter: .v2,
            environment: ["SWARM_CADENCE_REVIEW_V2_ACCESS_TOKEN": "fixture-only"],
            rawDirectory: raw.path, dbPath: f.db, pages: 1,
            transport: SyncFixtureTransport(items: [f.item("c1")], total: 1), now: { base.addingTimeInterval(0.5) })
        XCTAssertEqual(result.freshnessAfter?.lastFetchedAtISO8601, "2026-09-01T00:00:00.500Z")
    }
}
