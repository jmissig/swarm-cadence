import Foundation
import XCTest
@testable import SwarmCadenceCore

final class GeographyPresetTests: XCTestCase {
    func testAccountSpecificPresetOverridesSharedPreset() throws {
        let config = try writeConfig(
            """
            {
              "geographies": {
                "home": {
                  "kind": "anchor",
                  "display_name": "Shared Home",
                  "latitude": 37.0,
                  "longitude": -122.0,
                  "default_radius_meters": 500
                }
              },
              "accounts": {
                "julian": {
                  "geographies": {
                    "home": {
                      "kind": "anchor",
                      "display_name": "Julian Home",
                      "latitude": 37.1,
                      "longitude": -122.2,
                      "default_radius_meters": 700
                    }
                  }
                }
              }
            }
            """
        )

        let result = try GeographyPresetResolver.resolve(
            account: "julian",
            configPath: config.path,
            environment: [:],
            nearPlace: "home",
            area: nil,
            locality: nil,
            region: nil,
            postalCode: nil,
            countryCode: nil,
            nearLatitude: nil,
            nearLongitude: nil,
            radiusMeters: nil
        )

        XCTAssertEqual(result.nearLatitude, 37.1)
        XCTAssertEqual(result.nearLongitude, -122.2)
        XCTAssertEqual(result.radiusMeters, 700)
        XCTAssertEqual(result.geography.resolved?.scope, "account")
        XCTAssertEqual(result.geography.resolved?.displayName, "Julian Home")
    }

    func testUnknownPresetFailsClearly() throws {
        let config = try writeConfig(#"{ "geographies": {} }"#)

        XCTAssertThrowsError(try GeographyPresetResolver.resolve(
            account: "julian",
            configPath: config.path,
            environment: [:],
            nearPlace: "missing",
            area: nil,
            locality: nil,
            region: nil,
            postalCode: nil,
            countryCode: nil,
            nearLatitude: nil,
            nearLongitude: nil,
            radiusMeters: nil
        )) { error in
            XCTAssertTrue(String(describing: error).contains("unknown geography preset missing"))
        }
    }

    func testInvalidAnchorLatitudeAndRadiusFailClearly() throws {
        let invalidLatitude = try writeConfig(
            """
            {
              "geographies": {
                "bad": {
                  "kind": "anchor",
                  "latitude": 91,
                  "longitude": -122.2,
                  "default_radius_meters": 700
                }
              }
            }
            """
        )

        XCTAssertThrowsError(try resolveNearPlace("bad", config: invalidLatitude)) { error in
            XCTAssertTrue(String(describing: error).contains("latitude must be between -90 and 90"))
        }

        let missingRadius = try writeConfig(
            """
            {
              "geographies": {
                "no-radius": {
                  "kind": "anchor",
                  "latitude": 37.1,
                  "longitude": -122.2
                }
              }
            }
            """
        )

        XCTAssertThrowsError(try resolveNearPlace("no-radius", config: missingRadius)) { error in
            XCTAssertTrue(String(describing: error).contains("requires --radius-meters"))
        }
    }

    func testNearPlaceDefaultRadiusAndOverride() throws {
        let config = try writeConfig(
            """
            {
              "geographies": {
                "jackson-square": {
                  "kind": "anchor",
                  "display_name": "Jackson Square",
                  "latitude": 37.7979,
                  "longitude": -122.4016,
                  "default_radius_meters": 900
                }
              }
            }
            """
        )

        let defaulted = try resolveNearPlace("jackson-square", config: config)
        let overridden = try resolveNearPlace("jackson-square", config: config, radiusMeters: 1200)

        XCTAssertEqual(defaulted.radiusMeters, 900)
        XCTAssertEqual(overridden.radiusMeters, 1200)
        XCTAssertEqual(overridden.geography.resolved?.radiusMeters, 1200)
    }

    func testAreaMultipleLocalities() throws {
        let config = try writeConfig(
            """
            {
              "geographies": {
                "peninsula": {
                  "kind": "area",
                  "display_name": "Peninsula",
                  "localities": [
                    { "locality": "San Carlos", "region": "CA", "country_code": "US" },
                    { "locality": "Redwood City", "region": "CA", "country_code": "US" }
                  ]
                }
              }
            }
            """
        )

        let result = try GeographyPresetResolver.resolve(
            account: "julian",
            configPath: config.path,
            environment: [:],
            nearPlace: nil,
            area: "peninsula",
            locality: nil,
            region: nil,
            postalCode: nil,
            countryCode: nil,
            nearLatitude: nil,
            nearLongitude: nil,
            radiusMeters: nil
        )

        XCTAssertEqual(result.areaLocalities.count, 2)
        XCTAssertEqual(result.areaLocalities.map(\.locality), ["San Carlos", "Redwood City"])
        XCTAssertEqual(result.geography.resolved?.kind, "area")
        XCTAssertTrue(result.geography.semantics.contains("any listed place selector"))
    }

    private func resolveNearPlace(_ name: String, config: URL, radiusMeters: Double? = nil) throws -> GeographyExpansion {
        try GeographyPresetResolver.resolve(
            account: "julian",
            configPath: config.path,
            environment: [:],
            nearPlace: name,
            area: nil,
            locality: nil,
            region: nil,
            postalCode: nil,
            countryCode: nil,
            nearLatitude: nil,
            nearLongitude: nil,
            radiusMeters: radiusMeters
        )
    }

    private func writeConfig(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-cadence-geography-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        try body.data(using: .utf8)!.write(to: url)
        return url
    }
}
