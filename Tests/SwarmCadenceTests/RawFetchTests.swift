import Foundation
import XCTest
@testable import SwarmCadenceCore

final class RawFetchTests: XCTestCase {
    func testRawFetchRequestUsesBoundedLimitOffsetAndSingleTransportCall() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let transport = CapturingRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody))

        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch",
                "--account", "julian",
                "--adapter", "v2",
                "--out", outputDirectory.path,
                "--limit", "25",
                "--offset", "250",
                "--format", "json"
            ],
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            liveTransport: transport,
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let requestURL = try XCTUnwrap(transport.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(components.path, "/v2/users/self/checkins")
        XCTAssertEqual(queryItems["limit"], "25")
        XCTAssertEqual(queryItems["offset"], "250")
        XCTAssertEqual(queryItems["v"], "20260427")
        XCTAssertEqual(queryItems["oauth_token"], "raw-secret-token")
        XCTAssertFalse(rendered.contains("raw-secret-token"))
        XCTAssertTrue(rendered.contains("\"request_count\" : 1"))
        XCTAssertTrue(rendered.contains("\"offset\" : 250"))
    }

    func testRawFetchRejectsLimitAboveHardMaxBeforeTransport() {
        let transport = CapturingRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody))
        var error = ""

        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch",
                "--account", "julian",
                "--adapter", "v2",
                "--out", "/tmp/raw-fetch-unused",
                "--limit", "251"
            ],
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            liveTransport: transport,
            output: { _ in },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(error.contains("hard max of 250"))
        XCTAssertFalse(error.contains("raw-secret-token"))
    }

    func testRawFetchRejectsNegativeOffsetBeforeTransport() {
        let transport = CapturingRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody))
        var error = ""

        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch",
                "--account", "julian",
                "--adapter", "v2",
                "--out", "/tmp/raw-fetch-unused",
                "--offset", "-1"
            ],
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            liveTransport: transport,
            output: { _ in },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(error.contains("--offset must be at least 0"))
        XCTAssertFalse(error.contains("raw-secret-token"))
    }

    func testRawFetchRejectsNonIntegerLimitBeforeTransport() {
        let transport = CapturingRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody))
        var error = ""

        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch",
                "--account", "julian",
                "--adapter", "v2",
                "--out", "/tmp/raw-fetch-unused",
                "--limit", "not-a-number"
            ],
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            liveTransport: transport,
            output: { _ in },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(error.contains("invalid for '--limit"))
        XCTAssertFalse(error.contains("raw-secret-token"))
    }

    func testRawFetchWritesUnalteredResponseAndAdjacentManifest() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000.123)

        let result = try RawFetch.fetch(
            account: "julian",
            adapter: .v2,
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            outputDirectory: outputDirectory.path,
            limit: 25,
            offset: 500,
            transport: StaticRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody)),
            fetchedAt: fetchedAt
        )

        let rawURL = URL(fileURLWithPath: result.rawFilePath)
        let manifestURL = URL(fileURLWithPath: result.manifestFilePath)
        let rawData = try Data(contentsOf: rawURL)
        let manifest = try JSONDecoder.snakeCase.decode(RawFetchManifest.self, from: Data(contentsOf: manifestURL))

        XCTAssertEqual(rawData, successBody)
        XCTAssertTrue(rawURL.lastPathComponent.contains("20231114T221320.123Z-v2-julian-checkins-offset500-limit25"))
        XCTAssertEqual(result.limit, 25)
        XCTAssertEqual(result.offset, 500)
        XCTAssertEqual(manifest.rawFileName, rawURL.lastPathComponent)
        XCTAssertEqual(manifest.limit, 25)
        XCTAssertEqual(manifest.offset, 500)
        XCTAssertEqual(manifest.pageMarker, "offset500")
        XCTAssertEqual(manifest.rawBytes, successBody.count)
        XCTAssertEqual(manifest.rawSha256, RawFetch.sha256Hex(successBody))
        XCTAssertEqual(manifest.httpStatusCode, 200)
        XCTAssertEqual(manifest.apiMetaCode, 200)
        XCTAssertEqual(manifest.returnedCount, 2)
        XCTAssertEqual(manifest.totalCount, 42)
        XCTAssertFalse(String(data: try Data(contentsOf: manifestURL), encoding: .utf8)?.contains("raw-secret-token") ?? true)
    }

    func testRawFetchOutputAndManifestDoNotLeakTokenFromErrorResponse() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let body = """
        {
          "meta": {
            "code": 401,
            "errorType": "invalid_auth",
            "errorDetail": "token raw-secret-token is invalid"
          },
          "response": {}
        }
        """.data(using: .utf8)!

        var rendered = ""
        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch",
                "--account", "julian",
                "--adapter", "v2",
                "--out", outputDirectory.path,
                "--limit", "1",
                "--format", "json"
            ],
            environment: [
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            liveTransport: StaticRawTransport(response: ProbeHTTPResponse(statusCode: 401, data: body)),
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(RawFetchResult.self, from: Data(rendered.utf8))
        let manifestData = try Data(contentsOf: URL(fileURLWithPath: result.manifestFilePath))

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(result.status, .unauthorized)
        XCTAssertEqual(result.requestCount, 1)
        XCTAssertFalse(rendered.contains("raw-secret-token"))
        XCTAssertFalse(String(data: manifestData, encoding: .utf8)?.contains("raw-secret-token") ?? true)
    }

    func testRawFetchDefaultsToLimit250Offset0AndApplicationSupportOutputDirectory() throws {
        let home = try makeTemporaryDirectory()
        let transport = CapturingRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody))
        var rendered = ""

        let defaultLimitExit = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch",
                "--account", "julian",
                "--adapter", "v2",
                "--format", "json"
            ],
            environment: [
                "HOME": home.path,
                "SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"
            ],
            liveTransport: transport,
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let requestURL = transport.requests.first?.url
        let components = requestURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let result = try JSONDecoder.snakeCase.decode(RawFetchResult.self, from: Data(rendered.utf8))

        XCTAssertEqual(defaultLimitExit, 0)
        XCTAssertEqual(queryItems["limit"], "250")
        XCTAssertEqual(queryItems["offset"], "0")
        XCTAssertTrue(result.rawFilePath.contains("Library/Application Support/swarm-cadence/accounts/julian/raw/v2/checkins"))
    }


    func testRawFetchPagesFetchesSequentialOffsetsAndStopsOnShortPage() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let transport = SequenceRawTransport(responses: [
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 3, ids: ["a", "b"])),
            ProbeHTTPResponse(statusCode: 200, data: pageBody(total: 3, ids: ["c"]))
        ])
        var rendered = ""

        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch-pages",
                "--account", "julian",
                "--adapter", "v2",
                "--out", outputDirectory.path,
                "--limit", "2",
                "--start-offset", "4",
                "--pages", "3",
                "--delay-ms", "0",
                "--format", "json"
            ],
            environment: ["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"],
            liveTransport: transport,
            output: { rendered = $0 },
            errorOutput: { _ in }
        )

        let result = try JSONDecoder.snakeCase.decode(RawFetchPagesResult.self, from: Data(rendered.utf8))
        let offsets = try transport.requests.map { request -> String in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            return queryItems["offset"] ?? ""
        }

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(offsets, ["4", "6"])
        XCTAssertEqual(result.command, "raw fetch-pages")
        XCTAssertEqual(result.requestCount, 2)
        XCTAssertEqual(result.fetchedPages, 2)
        XCTAssertEqual(result.nextOffset, 8)
        XCTAssertTrue(result.stoppedEarly)
        XCTAssertTrue(result.stopReason?.contains("returned 1 below limit 2") ?? false)
        XCTAssertFalse(rendered.contains("raw-secret-token"))
    }

    func testRawFetchPagesRejectsAboveHardMaxBeforeTransport() {
        let transport = CapturingRawTransport(response: ProbeHTTPResponse(statusCode: 200, data: successBody))
        var error = ""

        let exitCode = SwarmCadenceCommand.run(
            arguments: [
                "raw", "fetch-pages",
                "--account", "julian",
                "--adapter", "v2",
                "--out", "/tmp/raw-fetch-unused",
                "--pages", "201"
            ],
            environment: ["SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN": "raw-secret-token"],
            liveTransport: transport,
            output: { _ in },
            errorOutput: { error = $0 }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(error.contains("hard max of 200"))
    }

    private func pageBody(total: Int, ids: [String]) -> Data {
        let items = ids.map { "{ \"id\": \"\($0)\" }" }.joined(separator: ",")
        return """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": \(total),
              "items": [\(items)]
            }
          }
        }
        """.data(using: .utf8)!
    }

    private var successBody: Data {
        """
        {
          "meta": { "code": 200 },
          "response": {
            "checkins": {
              "count": 42,
              "items": [
                { "id": "checkin-1" },
                { "id": "checkin-2" }
              ]
            }
          }
        }
        """.data(using: .utf8)!
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

private struct StaticRawTransport: ProbeHTTPTransport {
    let response: ProbeHTTPResponse

    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        response
    }
}

private final class CapturingRawTransport: ProbeHTTPTransport {
    let response: ProbeHTTPResponse
    private(set) var requests: [URLRequest] = []

    init(response: ProbeHTTPResponse) {
        self.response = response
    }

    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        requests.append(request)
        return response
    }
}


private final class SequenceRawTransport: ProbeHTTPTransport {
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
