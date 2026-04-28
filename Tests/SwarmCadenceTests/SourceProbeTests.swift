import Foundation
import XCTest
@testable import SwarmCadenceCore

final class SourceProbeTests: XCTestCase {

    func testCLIVersionComesFromSyncedVersionFile() throws {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["--version"],
            output: { output = $0 },
            errorOutput: { _ in }
        )
        let versionPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("VERSION")
        let versionFile = try String(contentsOf: versionPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(output, SwarmCadenceVersion.current)
        XCTAssertEqual(output, versionFile)
    }

    func testBareCLIShowsOnlyTopLevelVerbs() {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("swarm-cadence \(SwarmCadenceVersion.current)"))
        XCTAssertTrue(output.contains("SUBCOMMANDS:"))
        XCTAssertTrue(output.contains("auth"))
        XCTAssertTrue(output.contains("query"))
        XCTAssertTrue(output.contains("Run `swarm-cadence --help`"))
        XCTAssertLessThan(output.split(separator: "\n").count, 25)
        XCTAssertFalse(output.contains("Examples:"))
        XCTAssertFalse(output.contains("OVERVIEW:"))
    }


    func testBareGroupShowsGroupHelp() {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["ingest"],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("swarm-cadence ingest"))
        XCTAssertTrue(output.contains("SUBCOMMANDS:"))
        XCTAssertTrue(output.contains("update"))
        XCTAssertTrue(output.contains("swarm-cadence ingest update --help"))
        XCTAssertFalse(output.contains("unsupported command"))
    }


    func testFriendlyDashHelpIsAcceptedForBareGroups() {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["ingest", "—help"],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("swarm-cadence ingest"))
        XCTAssertTrue(output.contains("update"))
    }

    func testCLIHelpIncludesVersionAndConciseTaskSurface() {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["--help"],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("swarm-cadence \(SwarmCadenceVersion.current)"))
        XCTAssertTrue(output.contains("swarm-cadence --version"))
        XCTAssertTrue(output.contains("OVERVIEW: Build and query local Foursquare/Swarm check-in evidence."))
        XCTAssertTrue(output.contains("SUBCOMMANDS:"))
        XCTAssertTrue(output.contains("For detailed command options"))
        XCTAssertLessThan(output.split(separator: "\n").count, 80)
        XCTAssertFalse(output.contains("swarm-cadence evidence packet --account <label> --date <YYYY-MM-DD> --baseline-from <time>"))
    }

    func testV2ProbeReportsExternalSetupWhenTokenMissing() {
        let result = SourceProbe.probe(
            account: "julian",
            adapter: .v2,
            environment: [:]
        )

        XCTAssertEqual(result.status, .externalSetupRequired)
        XCTAssertTrue(result.externalSetupRequired)
        XCTAssertFalse(result.networkPerformed)
        XCTAssertEqual(result.requiredMissing, ["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"])
    }

    func testHistorysearchProbeRedactsConfiguredSecrets() {
        let result = SourceProbe.probe(
            account: "julian",
            adapter: .historysearch,
            environment: [
                "SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID": "actual-user-id",
                "SWARM_CADENCE_JULIAN_HISTORYSEARCH_WSID": "actual-wsid",
                "SWARM_CADENCE_JULIAN_HISTORYSEARCH_OAUTH_TOKEN": "actual-oauth-token"
            ]
        )

        XCTAssertEqual(result.status, .readyForLiveProbe)
        XCTAssertFalse(result.externalSetupRequired)
        XCTAssertTrue(result.requiredMissing.isEmpty)
        XCTAssertTrue(result.checkedInputs.allSatisfy { input in
            input.state == .missing || input.value == "<redacted>"
        })
    }

    func testJSONOutputDoesNotLeakSecrets() throws {
        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: ["source", "probe", "--account", "julian", "--adapter", "v2", "--format", "json"],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "super-secret-token"]),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertFalse(rendered.contains("super-secret-token"))
        XCTAssertTrue(rendered.contains("<redacted>"))
        XCTAssertTrue(rendered.contains("\"network_performed\" : false"))
    }

    func testDryProbeDoesNotUseLiveTransportByDefault() {
        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: ["source", "probe", "--account", "julian", "--adapter", "v2", "--format", "json"],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "dry-secret-token"]),
            liveTransport: FailingTransport(),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(rendered.contains("\"probe_kind\" : \"dry_config_validation\""))
        XCTAssertTrue(rendered.contains("\"network_performed\" : false"))
        XCTAssertFalse(rendered.contains("dry-secret-token"))
    }

    func testJSONConfigFileCanProvideInputsWithoutLeakingValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "alice": {
              "v2": {
                "access_token": "alice-secret-token",
                "client_id": "alice-client-id"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "source", "probe",
                "--account", "alice",
                "--adapter", "v2",
                "--format", "json",
                "--config", config.path
            ],
            environment: [:],
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertFalse(rendered.contains("alice-secret-token"))
        XCTAssertFalse(rendered.contains("alice-client-id"))
        XCTAssertTrue(rendered.contains("\"source\" : \"config_file\""))
    }

    func testDefaultApplicationSupportJSONConfigIsUsedWhenPresent() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("swarm-cadence", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let config = appSupport.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "julian": {
              "v2": {
                "access_token": "default-config-token"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "source", "probe",
                "--account", "julian",
                "--adapter", "v2",
                "--format", "json"
            ],
            environment: ["HOME": home.path],
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(rendered.contains("\"status\" : \"ready_for_live_probe\""))
        XCTAssertTrue(rendered.contains("\"source\" : \"config_file\""))
        XCTAssertFalse(rendered.contains("default-config-token"))
    }

    func testPlaceholderValuesDoNotSatisfyRequiredInputs() {
        let result = SourceProbe.probe(
            account: "julian",
            adapter: .v2,
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "replace-with-oauth-access-token"
            ]
        )

        XCTAssertEqual(result.status, .externalSetupRequired)
        XCTAssertEqual(result.requiredMissing, ["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"])
        XCTAssertEqual(result.checkedInputs.first?.state, .placeholder)
        XCTAssertNil(result.checkedInputs.first?.value)
    }

    func testV2RequestConstructionUsesMinimalCheckinsProbe() throws {
        let request = try V2CheckinsProbe.makeRequest(accessToken: "request-secret-token", apiVersion: "20260427")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.foursquare.com")
        XCTAssertEqual(components.path, "/v2/users/self/checkins")
        XCTAssertEqual(queryItems["limit"], "1")
        XCTAssertEqual(queryItems["v"], "20260427")
        XCTAssertEqual(queryItems["oauth_token"], "request-secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testV2ResponseParsingReportsFieldCoverageAndHints() throws {
        let sample = """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": 42,
              "items": [
                {
                  "id": "checkin-1",
                  "createdAt": 1700000000,
                  "venue": {
                    "id": "venue-1",
                    "name": "Cafe Example",
                    "location": { "lat": 37.1, "lng": -122.2 },
                    "categories": [
                      { "id": "cat-1", "name": "Coffee Shop" }
                    ]
                  },
                  "photos": { "count": 1, "items": [ { "id": "photo-1" } ] }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let result = V2CheckinsProbe.parse(data: sample, httpStatusCode: 200)

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.networkPerformed)
        XCTAssertEqual(result.httpStatusCode, 200)
        XCTAssertEqual(result.apiMetaCode, 200)
        XCTAssertEqual(result.fieldCoverage?.sampleReturned, true)
        XCTAssertEqual(result.fieldCoverage?.checkinID, true)
        XCTAssertEqual(result.fieldCoverage?.createdAt, true)
        XCTAssertEqual(result.fieldCoverage?.venueID, true)
        XCTAssertEqual(result.fieldCoverage?.venueName, true)
        XCTAssertEqual(result.fieldCoverage?.latitude, true)
        XCTAssertEqual(result.fieldCoverage?.longitude, true)
        XCTAssertEqual(result.fieldCoverage?.categories, true)
        XCTAssertEqual(result.fieldCoverage?.photosObject, true)
        XCTAssertEqual(result.fieldCoverage?.photosPresent, true)
        XCTAssertEqual(result.countDateHints?.totalCount, 42)
        XCTAssertEqual(result.countDateHints?.returnedCount, 1)
        XCTAssertEqual(result.countDateHints?.sampleCreatedAt, 1_700_000_000)
        XCTAssertEqual(result.countDateHints?.categoryCount, 1)
        XCTAssertEqual(result.countDateHints?.photoCount, 1)
    }

    func testV2UnauthorizedErrorIsRedactedInLiveOutput() throws {
        let body = """
        {
          "meta": {
            "code": 401,
            "errorType": "invalid_auth",
            "errorDetail": "token live-secret-token is invalid"
          },
          "response": {}
        }
        """.data(using: .utf8)!

        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "source", "probe",
                "--account", "julian",
                "--adapter", "v2",
                "--format", "json",
                "--live"
            ],
            environment: isolatedEnvironment(["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "live-secret-token"]),
            liveTransport: StaticTransport(statusCode: 401, data: body),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(rendered.contains("\"status\" : \"unauthorized\""))
        XCTAssertTrue(rendered.contains("\"network_performed\" : true"))
        XCTAssertTrue(rendered.contains("<redacted>"))
        XCTAssertFalse(rendered.contains("live-secret-token"))
    }

    func testLiveV2CanReadTokenFromConfigFileWithoutLeakingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "julian": {
              "v2": {
                "access_token": "config-live-token"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        let transport = CapturingTransport(
            response: ProbeHTTPResponse(statusCode: 200, data: """
            {
              "meta": { "code": 200 },
              "response": { "checkins": { "count": 0, "items": [] } }
            }
            """.data(using: .utf8)!)
        )

        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "source", "probe",
                "--account", "julian",
                "--adapter", "v2",
                "--format", "json",
                "--config", config.path,
                "--live"
            ],
            environment: [:],
            liveTransport: transport,
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let requestURL = try XCTUnwrap(transport.request?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(queryItems["oauth_token"], "config-live-token")
        XCTAssertTrue(rendered.contains("\"status\" : \"success\""))
        XCTAssertFalse(rendered.contains("config-live-token"))
    }

    func testV2TransportErrorIsRedacted() {
        let result = SourceProbe.liveProbe(
            account: "julian",
            adapter: .v2,
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "network-secret-token"
            ],
            transport: ThrowingTransport(message: "request failed with network-secret-token")
        )

        XCTAssertEqual(result.status, .networkError)
        XCTAssertEqual(result.liveProbe?.status, .networkError)
        XCTAssertEqual(result.liveProbe?.message, "request failed with <redacted>")
    }

    private func isolatedEnvironment(_ values: [String: String] = [:]) -> [String: String] {
        var environment = ["HOME": FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path]
        for (key, value) in values {
            environment[key] = value
        }
        return environment
    }
}

private struct StaticTransport: ProbeHTTPTransport {
    let statusCode: Int
    let data: Data

    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        ProbeHTTPResponse(statusCode: statusCode, data: data)
    }
}

private struct ThrowingTransport: ProbeHTTPTransport {
    let message: String

    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        throw ProbeTransportError(message)
    }
}

private struct FailingTransport: ProbeHTTPTransport {
    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        XCTFail("Dry probe should not perform live transport.")
        return ProbeHTTPResponse(statusCode: 500, data: Data())
    }
}

private final class CapturingTransport: ProbeHTTPTransport {
    let response: ProbeHTTPResponse
    var request: URLRequest?

    init(response: ProbeHTTPResponse) {
        self.response = response
    }

    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        self.request = request
        return response
    }
}
