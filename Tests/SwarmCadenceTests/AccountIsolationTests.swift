import Foundation
import XCTest
@testable import SwarmCadenceCore

final class AccountIsolationTests: XCTestCase {
    func testExactJSONLabelsDoNotShareCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config.json")
        try Data(#"{"accounts":{"a-b":{"v2":{"access_token":"fixture-only"}},"a_b":{}}}"#.utf8).write(to: config)
        let status = try SourceStatus.status(account: "a_b", configPath: config.path, environment: [:])
        XCTAssertFalse(status.accounts[0].v2AccessTokenPresent)
        let other = try SourceStatus.status(account: "a-b", configPath: config.path, environment: [:])
        XCTAssertTrue(other.accounts[0].v2AccessTokenPresent)
    }

    func testAmbiguousEnvironmentMappingRejectedBeforeNetwork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config.json")
        try Data(#"{"accounts":{"a-b":{},"a_b":{}}}"#.utf8).write(to: config)
        XCTAssertThrowsError(try SourceStatus.status(account: "a_b", configPath: config.path,
            environment: ["SWARM_CADENCE_A_B_V2_ACCESS_TOKEN": "fixture-only"])) { error in
            XCTAssertFalse(String(describing: error).contains("fixture-only"))
        }
        XCTAssertThrowsError(try SourceStatus.status(account: "a-b", configPath: directory.appendingPathComponent("missing.json").path,
            environment: ["SWARM_CADENCE_A_B_V2_ACCESS_TOKEN": "fixture-only"]))
    }
}
