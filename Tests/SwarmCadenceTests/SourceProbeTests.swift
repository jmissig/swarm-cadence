import XCTest
@testable import SwarmCadenceCore

final class SourceProbeTests: XCTestCase {
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
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "super-secret-token"
            ],
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertFalse(rendered.contains("super-secret-token"))
        XCTAssertTrue(rendered.contains("<redacted>"))
        XCTAssertTrue(rendered.contains("\"network_performed\" : false"))
    }

    func testConfigFileCanProvideInputsWithoutLeakingValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("probe.env")
        try """
        SWARM_CADENCE_ALICE_V2_ACCESS_TOKEN=alice-secret-token
        SWARM_CADENCE_ALICE_V2_CLIENT_ID=alice-client-id
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
}
