import Foundation
import GRDB

struct EvidenceDateWindow {
    let from: Int?
    let through: Int?
    init(from: Int? = nil, through: Int? = nil) throws {
        if let from, let through, from > through { throw CLIError("--from must be less than or equal to --to.") }
        self.from = from; self.through = through
    }
    var predicate: String { "(? IS NULL OR c.created_at_unix >= ?) AND (? IS NULL OR c.created_at_unix <= ?)" }
    var arguments: StatementArguments { [from, from, through, through] }
}

struct VisitCalendarFilter {
    let date: String?
    let hourFrom: Int?
    let hourTo: Int?
}

struct VenueGeographyFilter {
    var locality: String? = nil
    var region: String? = nil
    var postalCode: String? = nil
    var countryCode: String? = nil
    var localities: [GeographyAreaLocality] = []
    var latitude: Double? = nil
    var longitude: Double? = nil
    var radius: Double? = nil
}

/// One membership contract for summary SQL and supporting-visit commands.
/// Sorting and output limits are deliberately not membership filters.
struct EvidenceSelection {
    let account: String
    var window: EvidenceDateWindow
    let calendar: VisitCalendarFilter
    let categories: [String]
    var venueID: String? = nil
    var geography = VenueGeographyFilter()

    func predicate() throws -> (sql: String, arguments: StatementArguments) {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let categoryJSON = categories.isEmpty ? nil : String(decoding: try encoder.encode(categories), as: UTF8.self)
        let areaJSON = geography.localities.isEmpty ? nil : String(decoding: try encoder.encode(geography.localities), as: UTF8.self)
        let sql = """
        c.account = ? AND (? IS NULL OR c.venue_id = ?)
        AND \(window.predicate)
        AND (? IS NULL OR c.local_date = ?)
        AND (? IS NULL OR c.local_hour >= ?) AND (? IS NULL OR c.local_hour <= ?)
        AND (? IS NULL OR EXISTS (
            SELECT 1 FROM checkin_categories cc JOIN categories cat ON cat.category_id = cc.category_id
            WHERE cc.checkin_id = c.checkin_id AND cc.account = c.account
              AND lower(cat.name) IN (SELECT lower(value) FROM json_each(?))))
        AND (? IS NULL OR lower(v.locality) = lower(?))
        AND (? IS NULL OR lower(v.region) = lower(?))
        AND (? IS NULL OR lower(v.postal_code) = lower(?))
        AND (? IS NULL OR lower(v.country_code) = lower(?))
        AND (? IS NULL OR EXISTS (SELECT 1 FROM json_each(?) area
            WHERE lower(v.locality) = lower(json_extract(area.value, '$.locality'))
              AND (json_extract(area.value, '$.region') IS NULL OR lower(v.region) = lower(json_extract(area.value, '$.region')))
              AND (json_extract(area.value, '$.postal_code') IS NULL OR lower(v.postal_code) = lower(json_extract(area.value, '$.postal_code')))
              AND (json_extract(area.value, '$.country_code') IS NULL OR lower(v.country_code) = lower(json_extract(area.value, '$.country_code')))))
        AND (? IS NULL OR (v.lat IS NOT NULL AND v.lng IS NOT NULL AND distance_meters(v.lat, v.lng, ?, ?) <= ?))
        """
        var args: StatementArguments = [account, venueID, venueID]
        args += window.arguments
        args += [calendar.date, calendar.date, calendar.hourFrom, calendar.hourFrom, calendar.hourTo, calendar.hourTo,
            categoryJSON, categoryJSON, geography.locality, geography.locality, geography.region, geography.region,
            geography.postalCode, geography.postalCode, geography.countryCode, geography.countryCode, areaJSON, areaJSON,
            geography.radius, geography.latitude, geography.longitude, geography.radius]
        return (sql, args)
    }

    func drillDown(dbPath: String, venueID: String) -> EvidenceDrillDown {
        var args = ["query", "visits", "--account", account, "--db", dbPath, "--venue-id", venueID]
        if let value = window.from { args += ["--from", String(value)] }
        if let value = window.through { args += ["--to", String(value)] }
        if let value = calendar.date { args += ["--date", value] }
        if let value = calendar.hourFrom { args += ["--hour-from", String(value)] }
        if let value = calendar.hourTo { args += ["--hour-to", String(value)] }
        for category in categories { args += ["--category", category] }
        // Geography already chose this exact venue; do not resolve mutable named
        // presets again. Visit output reports total count separately from its limit.
        return EvidenceDrillDown(command: "swarm-cadence", arguments: args)
    }
}

struct EvidenceComparisonWindows {
    let baseline: EvidenceDateWindow
    let recent: EvidenceDateWindow
}
