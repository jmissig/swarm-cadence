import Foundation
import XCTest
@testable import SwarmCadenceCore
@testable import SwarmCadenceCommands

private final class ReentrantTransport: ProbeHTTPTransport {
    let inner: () -> Void
    init(inner: @escaping () -> Void) { self.inner = inner }
    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        inner()
        return ProbeHTTPResponse(statusCode: 401, data: Data(#"{"meta":{"code":401}}"#.utf8))
    }
}

final class CommandIsolationTests: XCTestCase {
    func testNestedInvocationCannotReplaceOuterOutputOrExitCode() throws {
        let f = try EvidenceFixture()
        var outer = "", inner = ""
        let transport = ReentrantTransport {
            XCTAssertEqual(SwarmCadenceCommand.run(arguments: ["source", "status", "--account", "inner", "--config", f.root.appendingPathComponent("missing.json").path, "--format", "json"],
                environment: [:], output: { inner = $0 }), 0)
        }
        let exit = SwarmCadenceCommand.run(arguments: ["ingest", "--account", "outer", "--raw-dir", f.root.appendingPathComponent("raw").path, "--db", f.db, "--format", "json"],
            environment: ["HOME": f.root.path, "SWARM_CADENCE_OUTER_V2_ACCESS_TOKEN": "fixture-only"],
            liveTransport: transport, output: { outer = $0 })
        XCTAssertEqual(exit, 1)
        XCTAssertTrue(outer.contains("source_blocked"))
        XCTAssertTrue(outer.contains("\"account\" : \"outer\""))
        XCTAssertFalse(outer.contains("inner"))
        XCTAssertTrue(inner.contains("\"account\" : \"inner\""))
        XCTAssertFalse(inner.contains("source_blocked"))
    }
}
