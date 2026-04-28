import Foundation
import XCTest
@testable import SwarmCadenceCore

final class SourceStatusTests: XCTestCase {
    func testFormatHumanIsRejectedInFavorOfText() throws {
        var output = ""
        var error = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["source", "status", "--format", "human"],
            environment: ["HOME": temporaryDirectory().path],
            liveTransport: FailingSourceStatusTransport(),
            output: { output = $0 },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertEqual(output, "")
        XCTAssertTrue(error.contains("unsupported --format. Use `text` or `json`."))
    }

    func testSourceStatusMissingConfigReturnsEmptyAccountList() throws {
        let home = temporaryDirectory()
        let config = home.appendingPathComponent("missing-config.json")

        var rendered = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["source", "status", "--config", config.path, "--format", "json"],
            environment: ["HOME": home.path],
            liveTransport: FailingSourceStatusTransport(),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let result = try decodeStatus(rendered)
        XCTAssertEqual(exit, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
        XCTAssertEqual(result.command, "source status")
        XCTAssertEqual(result.status, "ok")
        XCTAssertFalse(result.configExists)
        XCTAssertEqual(result.accountCount, 0)
        XCTAssertTrue(result.accounts.isEmpty)
        XCTAssertFalse(result.networkPerformed)
    }

    func testSourceStatusListsConfiguredAccountsWithoutLeakingSecrets() throws {
        let home = temporaryDirectory()
        let appSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("swarm-cadence", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let config = appSupport.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "alice": {
              "historysearch": {
                "userid": "alice-user",
                "wsid": "alice-wsid",
                "oauth_token": "alice-history-secret",
                "cookie": "alice-cookie-secret"
              }
            },
            "julian": {
              "v2": {
                "access_token": "julian-secret-token",
                "client_id": "julian-client-id"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        let julianRaw = appSupport
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("julian", isDirectory: true)
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("checkins", isDirectory: true)
        try FileManager.default.createDirectory(at: julianRaw, withIntermediateDirectories: true)
        let aliceDB = appSupport
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("alice", isDirectory: true)
            .appendingPathComponent("swarm-cadence.sqlite")
        try FileManager.default.createDirectory(at: aliceDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: aliceDB.path, contents: Data())

        var rendered = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["source", "status", "--format", "json"],
            environment: ["HOME": home.path],
            liveTransport: FailingSourceStatusTransport(),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let result = try decodeStatus(rendered)
        let accounts = Dictionary(uniqueKeysWithValues: result.accounts.map { ($0.label, $0) })
        let julian = try XCTUnwrap(accounts["julian"])
        let alice = try XCTUnwrap(accounts["alice"])

        XCTAssertEqual(exit, 0)
        XCTAssertFalse(rendered.contains("julian-secret-token"))
        XCTAssertFalse(rendered.contains("alice-history-secret"))
        XCTAssertFalse(rendered.contains("alice-cookie-secret"))
        XCTAssertEqual(result.accountCount, 2)
        XCTAssertTrue(julian.v2Configured)
        XCTAssertTrue(julian.v2AccessTokenPresent)
        XCTAssertFalse(julian.historysearchConfigured)
        XCTAssertTrue(julian.defaultRawV2PathExists)
        XCTAssertFalse(julian.defaultSqliteDbPathExists)
        XCTAssertTrue(julian.localEvidenceAvailable)
        XCTAssertFalse(alice.v2Configured)
        XCTAssertFalse(alice.v2AccessTokenPresent)
        XCTAssertTrue(alice.historysearchConfigured)
        XCTAssertFalse(alice.defaultRawV2PathExists)
        XCTAssertTrue(alice.defaultSqliteDbPathExists)
        XCTAssertTrue(alice.localEvidenceAvailable)
    }

    func testSourceStatusForExplicitAccountWorksWithoutConfiguredAccount() throws {
        let home = temporaryDirectory()
        let sqlite = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("swarm-cadence", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("static-only", isDirectory: true)
            .appendingPathComponent("swarm-cadence.sqlite")
        try FileManager.default.createDirectory(at: sqlite.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sqlite.path, contents: Data())

        var rendered = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["source", "status", "--account", "static-only", "--format", "json"],
            environment: ["HOME": home.path],
            liveTransport: FailingSourceStatusTransport(),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let result = try decodeStatus(rendered)
        let account = try XCTUnwrap(result.accounts.first)

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(result.accountCount, 1)
        XCTAssertEqual(account.label, "static-only")
        XCTAssertEqual(account.account, "static-only")
        XCTAssertFalse(account.v2AccessTokenPresent)
        XCTAssertFalse(account.historysearchConfigured)
        XCTAssertFalse(account.defaultRawV2PathExists)
        XCTAssertTrue(account.defaultSqliteDbPathExists)
        XCTAssertTrue(account.localEvidenceAvailable)
    }

    func testHelpMentionsSourceStatus() {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["--help"],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("swarm-cadence source status [--account <label>]"))
    }

    private func decodeStatus(_ rendered: String) throws -> SourceStatusResult {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SourceStatusResult.self, from: Data(rendered.utf8))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private struct FailingSourceStatusTransport: ProbeHTTPTransport {
    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        XCTFail("source status should not perform live transport.")
        return ProbeHTTPResponse(statusCode: 500, data: Data())
    }
}
