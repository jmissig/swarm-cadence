import Foundation
import XCTest
@testable import SwarmCadenceCore

final class AppSupportDefaultsTests: XCTestCase {
    func testDefaultUsesFoundationSearchDirectory() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let expected = base.appendingPathComponent("swarm-cadence", isDirectory: true).path
        XCTAssertEqual(AppSupportDefaults.appSupportDirectory(environment: [:]), expected)
        XCTAssertEqual(AppSupportDefaults.appSupportDirectory(environment: ["SWARM_CADENCE_APP_SUPPORT_DIR": ""]), expected)
    }

    func testInjectedRootKeepsConfigAndAccountsTogetherWithoutCreatingDirectories() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = ["SWARM_CADENCE_APP_SUPPORT_DIR": root.path]

        XCTAssertEqual(AppSupportDefaults.configPath(environment: environment), root.appendingPathComponent("config.json").path)
        XCTAssertEqual(AppSupportDefaults.sqlitePath(account: "first", environment: environment), root.appendingPathComponent("accounts/first/swarm-cadence.sqlite").path)
        XCTAssertEqual(AppSupportDefaults.rawCheckinsDirectory(account: "second", environment: environment), root.appendingPathComponent("accounts/second/raw/v2/checkins").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
