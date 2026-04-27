import Foundation

public struct SourceOverlapAuditResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let v2RawDirectory: String
    public let exportPath: String
    public let v2Checkins: Int
    public let exportCheckins: Int
    public let overlappingCheckins: Int
    public let v2OnlyCheckins: Int
    public let exportOnlyCheckins: Int
    public let timestampMatches: Int
    public let timestampMismatches: Int
    public let venueIDMatches: Int
    public let venueIDMismatches: Int
    public let venueNameMatches: Int
    public let venueNameMismatches: Int
    public let latitudeLongitudeMatches: Int
    public let latitudeLongitudeMismatches: Int
    public let v2RowsWithCategories: Int
    public let exportRowsWithCategories: Int
    public let overlappingV2RowsWithCategories: Int
    public let overlappingExportRowsWithCategories: Int
    public let examples: [SourceOverlapMismatchExample]
}

public struct SourceOverlapMismatchExample: Codable, Equatable {
    public let checkinID: String
    public let field: String
    public let v2Value: String?
    public let exportValue: String?
}

private struct AuditCheckin: Equatable {
    let id: String
    let createdAtUnix: Int?
    let venueID: String?
    let venueName: String?
    let latitude: Double?
    let longitude: Double?
    let categoryCount: Int
}

public enum SourceAudit {
    public static let defaultExampleLimit = 25

    public static func overlap(
        account: String,
        v2RawDirectory: String,
        exportPath: String,
        exampleLimit: Int = defaultExampleLimit
    ) throws -> SourceOverlapAuditResult {
        let account = try AccountLabel.validate(account)
        guard exampleLimit >= 0 else { throw CLIError("--examples must be at least 0.") }
        let v2URL = URL(fileURLWithPath: v2RawDirectory, isDirectory: true)
        let exportURL = URL(fileURLWithPath: exportPath, isDirectory: true)
        try requireDirectory(v2URL, option: "--raw-dir")
        try requireDirectory(exportURL, option: "--path")

        let v2 = try readV2Checkins(directory: v2URL)
        let exported = try readExportCheckins(directory: exportURL)
        let v2IDs = Set(v2.keys)
        let exportIDs = Set(exported.keys)
        let overlapIDs = v2IDs.intersection(exportIDs).sorted()

        var timestampMatches = 0
        var timestampMismatches = 0
        var venueIDMatches = 0
        var venueIDMismatches = 0
        var venueNameMatches = 0
        var venueNameMismatches = 0
        var latLngMatches = 0
        var latLngMismatches = 0
        var overlappingV2RowsWithCategories = 0
        var overlappingExportRowsWithCategories = 0
        var examples: [SourceOverlapMismatchExample] = []

        for id in overlapIDs {
            guard let left = v2[id], let right = exported[id] else { continue }
            compare(
                id: id,
                field: "created_at",
                left: left.createdAtUnix.map(String.init),
                right: right.createdAtUnix.map(String.init),
                matches: &timestampMatches,
                mismatches: &timestampMismatches,
                examples: &examples,
                exampleLimit: exampleLimit
            )
            compare(
                id: id,
                field: "venue_id",
                left: left.venueID,
                right: right.venueID,
                matches: &venueIDMatches,
                mismatches: &venueIDMismatches,
                examples: &examples,
                exampleLimit: exampleLimit
            )
            compare(
                id: id,
                field: "venue_name",
                left: left.venueName,
                right: right.venueName,
                matches: &venueNameMatches,
                mismatches: &venueNameMismatches,
                examples: &examples,
                exampleLimit: exampleLimit
            )
            compare(
                id: id,
                field: "lat_lng",
                left: coordinateValue(lat: left.latitude, lng: left.longitude),
                right: coordinateValue(lat: right.latitude, lng: right.longitude),
                matches: &latLngMatches,
                mismatches: &latLngMismatches,
                examples: &examples,
                exampleLimit: exampleLimit
            )
            if left.categoryCount > 0 { overlappingV2RowsWithCategories += 1 }
            if right.categoryCount > 0 { overlappingExportRowsWithCategories += 1 }
        }

        return SourceOverlapAuditResult(
            schemaVersion: 1,
            command: "audit overlap",
            account: account,
            v2RawDirectory: v2RawDirectory,
            exportPath: exportPath,
            v2Checkins: v2.count,
            exportCheckins: exported.count,
            overlappingCheckins: overlapIDs.count,
            v2OnlyCheckins: v2IDs.subtracting(exportIDs).count,
            exportOnlyCheckins: exportIDs.subtracting(v2IDs).count,
            timestampMatches: timestampMatches,
            timestampMismatches: timestampMismatches,
            venueIDMatches: venueIDMatches,
            venueIDMismatches: venueIDMismatches,
            venueNameMatches: venueNameMatches,
            venueNameMismatches: venueNameMismatches,
            latitudeLongitudeMatches: latLngMatches,
            latitudeLongitudeMismatches: latLngMismatches,
            v2RowsWithCategories: v2.values.filter { $0.categoryCount > 0 }.count,
            exportRowsWithCategories: exported.values.filter { $0.categoryCount > 0 }.count,
            overlappingV2RowsWithCategories: overlappingV2RowsWithCategories,
            overlappingExportRowsWithCategories: overlappingExportRowsWithCategories,
            examples: examples
        )
    }

    private static func compare(
        id: String,
        field: String,
        left: String?,
        right: String?,
        matches: inout Int,
        mismatches: inout Int,
        examples: inout [SourceOverlapMismatchExample],
        exampleLimit: Int
    ) {
        if left == right {
            matches += 1
        } else {
            mismatches += 1
            if examples.count < exampleLimit {
                examples.append(SourceOverlapMismatchExample(checkinID: id, field: field, v2Value: left, exportValue: right))
            }
        }
    }

    private static func coordinateValue(lat: Double?, lng: Double?) -> String? {
        guard let lat, let lng else { return nil }
        return String(format: "%.6f,%.6f", lat, lng)
    }

    private static func requireDirectory(_ url: URL, option: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError("\(option) does not exist or is not a directory: \(url.path).")
        }
    }

    private static func readV2Checkins(directory: URL) throws -> [String: AuditCheckin] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".raw.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var checkins: [String: AuditCheckin] = [:]
        for file in files {
            let data = try Data(contentsOf: file)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = object["response"] as? [String: Any],
                  let envelope = response["checkins"] as? [String: Any],
                  let items = envelope["items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                guard let id = nonEmptyString(item["id"]) else { continue }
                let venue = item["venue"] as? [String: Any]
                let location = venue?["location"] as? [String: Any]
                let categories = venue?["categories"] as? [[String: Any]]
                checkins[id] = AuditCheckin(
                    id: id,
                    createdAtUnix: intValue(item["createdAt"]),
                    venueID: nonEmptyString(venue?["id"]),
                    venueName: nonEmptyString(venue?["name"]),
                    latitude: doubleValue(location?["lat"]),
                    longitude: doubleValue(location?["lng"]),
                    categoryCount: categories?.count ?? 0
                )
            }
        }
        return checkins
    }

    private static func readExportCheckins(directory: URL) throws -> [String: AuditCheckin] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.range(of: #"^checkins\d+\.json$"#, options: .regularExpression) != nil }
            .sorted { exportCheckinsFileOrdinal($0.lastPathComponent) < exportCheckinsFileOrdinal($1.lastPathComponent) }
        var checkins: [String: AuditCheckin] = [:]
        for file in files {
            let data = try Data(contentsOf: file)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = object["items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                guard let id = nonEmptyString(item["id"]) else { continue }
                let venue = item["venue"] as? [String: Any]
                let location = venue?["location"] as? [String: Any]
                let categories = venue?["categories"] as? [[String: Any]]
                checkins[id] = AuditCheckin(
                    id: id,
                    createdAtUnix: exportTimestamp(nonEmptyString(item["createdAt"])),
                    venueID: nonEmptyString(venue?["id"]),
                    venueName: nonEmptyString(venue?["name"]),
                    latitude: doubleValue(item["lat"]) ?? doubleValue(location?["lat"]),
                    longitude: doubleValue(item["lng"]) ?? doubleValue(location?["lng"]),
                    categoryCount: categories?.count ?? 0
                )
            }
        }
        return checkins
    }

    private static func exportTimestamp(_ string: String?) -> Int? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        if let date = formatter.date(from: string) { return Int(date.timeIntervalSince1970) }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string).map { Int($0.timeIntervalSince1970) }
    }

    private static func exportCheckinsFileOrdinal(_ name: String) -> Int {
        let digits = name.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)
        return Int(digits) ?? 0
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }
}
