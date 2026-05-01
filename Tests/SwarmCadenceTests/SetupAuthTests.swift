import Foundation
import XCTest
@testable import SwarmCadenceCore

final class SetupAuthTests: XCTestCase {
    func testAuthStatusReportsMissingConfigWithoutCreatingDefaultPaths() throws {
        let home = temporaryDirectory()
        let config = home.appendingPathComponent("missing-config.json")

        var rendered = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["auth", "status", "--account", "julian", "--config", config.path, "--format", "json"],
            environment: ["HOME": home.path],
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
        XCTAssertTrue(rendered.contains("\"config_exists\" : false"))
        XCTAssertTrue(rendered.contains("\"status\" : \"needs_setup\""))
        XCTAssertTrue(rendered.contains("\"v2_access_token_present\" : false"))
    }

    func testInteractiveSetupTokenPathWritesConfigAndRedactsOutput() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        var output = ""
        var inputs = ["setup-secret-token"]

        let exit = SwarmCadenceCommand.run(
            arguments: ["setup", "--account", "julian", "--config", config.path],
            environment: ["HOME": directory.path],
            input: { inputs.removeFirst() },
            output: { output += $0 + "\n" },
            errorOutput: { output += $0 + "\n" }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertFalse(output.contains("setup-secret-token"))
        XCTAssertTrue(output.contains("V2 access token: present"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.path))

        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"], "setup-secret-token")

        let permissions = try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSetupMergePreservesOtherAccountAndHistorysearchConfig() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "alice": {
              "v2": {
                "access_token": "alice-existing-token"
              }
            },
            "julian": {
              "historysearch": {
                "userid": "julian-user",
                "wsid": "julian-wsid",
                "oauth_token": "julian-history-token"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        var rendered = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "setup",
                "--account", "julian",
                "--config", config.path,
                "--access-token", "julian-new-token"
            ],
            environment: ["HOME": directory.path],
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertFalse(rendered.contains("julian-new-token"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"], "julian-new-token")
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID"], "julian-user")
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_HISTORYSEARCH_WSID"], "julian-wsid")
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_HISTORYSEARCH_OAUTH_TOKEN"], "julian-history-token")
        XCTAssertEqual(flattened["SWARM_CADENCE_ALICE_V2_ACCESS_TOKEN"], "alice-existing-token")
    }

    func testOAuthCodeSetupGeneratesAuthorizationURLAndExchangesCodeWithFakeTransport() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        let transport = CapturingSetupTransport(response: ProbeHTTPResponse(
            statusCode: 200,
            data: #"{"access_token":"oauth-exchanged-token"}"#.data(using: .utf8)!
        ))
        var output = ""
        var inputs = [
            "",
            "test-client-id",
            "test-client-secret",
            "http://localhost:17342/foursquare/callback",
            "test-auth-code"
        ]

        let exit = SwarmCadenceCommand.run(
            arguments: ["setup", "--account", "julian", "--config", config.path],
            environment: ["HOME": directory.path],
            liveTransport: transport,
            input: { inputs.removeFirst() },
            output: { output += $0 + "\n" },
            errorOutput: { output += $0 + "\n" }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("https://foursquare.com/oauth2/authenticate"))
        XCTAssertTrue(output.contains("response_type=code"))
        XCTAssertFalse(output.contains("test-client-secret"))
        XCTAssertFalse(output.contains("test-auth-code"))
        XCTAssertFalse(output.contains("oauth-exchanged-token"))

        let request = try XCTUnwrap(transport.request)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "foursquare.com")
        XCTAssertEqual(components.path, "/oauth2/access_token")
        XCTAssertEqual(queryItems["client_id"], "test-client-id")
        XCTAssertEqual(queryItems["client_secret"], "test-client-secret")
        XCTAssertEqual(queryItems["grant_type"], "authorization_code")
        XCTAssertEqual(queryItems["redirect_uri"], "http://localhost:17342/foursquare/callback")
        XCTAssertEqual(queryItems["code"], "test-auth-code")

        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"], "oauth-exchanged-token")
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_CLIENT_ID"], "test-client-id")
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_CLIENT_SECRET"], "test-client-secret")
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_REDIRECT_URI"], "http://localhost:17342/foursquare/callback")
    }


    func testSetupKeepsExistingTokenWhenPresent() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "julian": {
              "v2": {
                "access_token": "existing-token"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["setup", "--account", "julian", "--config", config.path],
            environment: ["HOME": directory.path],
            input: { XCTFail("setup should not prompt when an existing token is present"); return nil },
            output: { output += $0 + "\n" },
            errorOutput: { output += $0 + "\n" }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("Existing v2 access token found"))
        XCTAssertFalse(output.contains("existing-token"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"], "existing-token")
    }

    func testJSONSetupWithPartialOAuthOptionsFailsWithoutPrompting() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        var error = ""
        let exit = SwarmCadenceCommand.run(
            arguments: [
                "setup",
                "--account", "julian",
                "--config", config.path,
                "--format", "json",
                "--client-id", "partial-client-id"
            ],
            environment: ["HOME": directory.path],
            input: { XCTFail("JSON setup should not prompt"); return nil },
            output: { _ in },
            errorOutput: { error += $0 + "\n" }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(error.contains("complete OAuth code-flow options"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testAuthClearRemovesStoredV2CredentialsOnlyWithForce() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "julian": {
              "v2": {
                "access_token": "token-to-clear"
              },
              "historysearch": {
                "userid": "julian-user"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["auth", "clear", "--account", "julian", "--config", config.path],
            environment: ["HOME": directory.path],
            output: { _ in },
            errorOutput: { _ in }
        ), 2)

        var output = ""
        XCTAssertEqual(SwarmCadenceCommand.run(
            arguments: ["auth", "clear", "--account", "julian", "--config", config.path, "--force"],
            environment: ["HOME": directory.path],
            output: { output += $0 + "\n" },
            errorOutput: { _ in }
        ), 0)

        XCTAssertTrue(output.contains("Auth clear: cleared"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertNil(flattened["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN"])
        XCTAssertEqual(flattened["SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID"], "julian-user")
    }


    func testAuthLoginPromptsForAccountLabelOnFirstRun() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        var output = ""
        var inputs = ["", "first-token"]

        let exit = SwarmCadenceCommand.run(
            arguments: ["auth", "login", "--config", config.path],
            environment: ["HOME": directory.path],
            input: { inputs.removeFirst() },
            output: { output += $0 + "\n" },
            errorOutput: { output += $0 + "\n" }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("Account label [default]:"))
        XCTAssertTrue(output.contains("Account: default"))
        XCTAssertFalse(output.contains("first-token"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_DEFAULT_V2_ACCESS_TOKEN"], "first-token")
    }

    func testAuthLoginWithoutAccountUsesOnlyConfiguredAccount() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "primary": {
              "v2": {
                "access_token": "primary-token"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["auth", "login", "--config", config.path, "--access-token", "replacement-token"],
            environment: ["HOME": directory.path],
            input: { XCTFail("single-account auth login should not prompt for an account label"); return nil },
            output: { output += $0 + "\n" },
            errorOutput: { output += $0 + "\n" }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("Account: primary"))
        XCTAssertFalse(output.contains("replacement-token"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_PRIMARY_V2_ACCESS_TOKEN"], "replacement-token")
    }

    func testAuthLoginWithoutAccountFailsWhenMultipleAccountsConfigured() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "primary": { "v2": { "access_token": "primary-token" } },
            "secondary": { "v2": { "access_token": "secondary-token" } }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)
        var error = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["auth", "login", "--config", config.path, "--access-token", "replacement-token"],
            environment: ["HOME": directory.path],
            input: { XCTFail("multi-account auth login should not prompt"); return nil },
            output: { _ in },
            errorOutput: { error += $0 + "\n" }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(error.contains("missing required --account <label>"))
        XCTAssertTrue(error.contains("primary, secondary"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_PRIMARY_V2_ACCESS_TOKEN"], "primary-token")
        XCTAssertEqual(flattened["SWARM_CADENCE_SECONDARY_V2_ACCESS_TOKEN"], "secondary-token")
    }

    func testJSONAuthLoginRequiresExplicitAccountWhenNoAccountExists() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        var error = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["auth", "login", "--config", config.path, "--format", "json", "--access-token", "token"],
            environment: ["HOME": directory.path],
            input: { XCTFail("JSON login should not prompt"); return nil },
            output: { _ in },
            errorOutput: { error += $0 + "\n" }
        )

        XCTAssertEqual(exit, 2)
        XCTAssertTrue(error.contains("requires --account <label>"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testJSONAuthLoginWithoutAccountUsesOnlyConfiguredAccount() throws {
        let directory = temporaryDirectory()
        let config = directory.appendingPathComponent("config.json")
        try """
        {
          "accounts": {
            "primary": {
              "historysearch": {
                "userid": "kept-user"
              }
            }
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)
        var output = ""

        let exit = SwarmCadenceCommand.run(
            arguments: ["auth", "login", "--config", config.path, "--format", "json", "--access-token", "new-token"],
            environment: ["HOME": directory.path],
            input: { XCTFail("JSON login should not prompt"); return nil },
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("\"account\" : \"primary\""))
        XCTAssertFalse(output.contains("new-token"))
        let flattened = try JSONConfig.load(path: config.path)
        XCTAssertEqual(flattened["SWARM_CADENCE_PRIMARY_V2_ACCESS_TOKEN"], "new-token")
        XCTAssertEqual(flattened["SWARM_CADENCE_PRIMARY_HISTORYSEARCH_USERID"], "kept-user")
    }

    func testHelpIncludesSetupAndAuthCommands() {
        var output = ""
        let exit = SwarmCadenceCommand.run(
            arguments: ["--help"],
            output: { output = $0 },
            errorOutput: { _ in }
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(output.contains("swarm-cadence setup [--account <label>]"))
        XCTAssertTrue(output.contains("swarm-cadence auth status --account <label>"))
        XCTAssertTrue(output.contains("swarm-cadence auth login [--account <label>]"))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class CapturingSetupTransport: ProbeHTTPTransport {
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
