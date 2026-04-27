import Foundation
import GRDB

public struct QueryDateBound: Codable, Equatable {
    public let unix: Int
    public let iso8601: String
}

public struct QueryGeoFilters: Codable, Equatable {
    public let nearLatitude: Double?
    public let nearLongitude: Double?
    public let radiusMeters: Double?
}

public struct QueryDateFilters: Codable, Equatable {
    public let fromCreatedAt: QueryDateBound?
    public let toCreatedAt: QueryDateBound?
    public let date: String?
    public let hourFrom: Int?
    public let hourTo: Int?
    public let locality: String?
    public let region: String?
    public let postalCode: String?
    public let countryCode: String?
    public let categoryName: String?
    public let nearLatitude: Double?
    public let nearLongitude: Double?
    public let radiusMeters: Double?
    public let limit: Int
}

public struct QueryVisitFilters: Codable, Equatable {
    public let fromCreatedAt: QueryDateBound?
    public let toCreatedAt: QueryDateBound?
    public let date: String?
    public let hourFrom: Int?
    public let hourTo: Int?
    public let venueID: String?
    public let limit: Int
}

public struct EvidenceDrillDown: Codable, Equatable {
    public let command: String
    public let arguments: [String]
}

public struct VenueEvidence: Codable, Equatable {
    public let venueID: String
    public let name: String?
    public let latitude: Double?
    public let longitude: Double?
    public let locality: String?
    public let region: String?
    public let postalCode: String?
    public let countryCode: String?
    public let distanceMeters: Double?
    public let visitCount: Int
    public let firstCreatedAt: Int?
    public let firstCreatedAtISO8601: String?
    public let lastCreatedAt: Int?
    public let lastCreatedAtISO8601: String?
    public let categories: [String]
    public let drillDown: EvidenceDrillDown
}

public struct VisitEvidence: Codable, Equatable {
    public let checkinID: String
    public let createdAt: Int?
    public let createdAtISO8601: String?
    public let localTimezoneID: String?
    public let localTimezoneOffsetMinutes: Int?
    public let localCreatedAt: String?
    public let localDate: String?
    public let localHour: Int?
    public let localWeekdayISO: Int?
    public let venueID: String?
    public let venueName: String?
    public let latitude: Double?
    public let longitude: Double?
    public let categories: [String]
    public let sourceAdapter: String
}


public struct CategoryEvidence: Codable, Equatable {
    public let categoryID: String
    public let name: String
    public let checkinCount: Int
    public let venueCount: Int
    public let firstCreatedAt: Int?
    public let firstCreatedAtISO8601: String?
    public let lastCreatedAt: Int?
    public let lastCreatedAtISO8601: String?
}

public struct QueryCategoriesResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let limit: Int
    public let totalMatchingCategories: Int
    public let returnedCategories: Int
    public let categories: [CategoryEvidence]
}

public struct QueryVenuesResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let filters: QueryDateFilters
    public let totalMatchingVenues: Int
    public let returnedVenues: Int
    public let venues: [VenueEvidence]
}

public struct QueryVisitsResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let filters: QueryVisitFilters
    public let totalMatchingVisits: Int
    public let returnedVisits: Int
    public let visits: [VisitEvidence]
}

public struct QueryCompareFilters: Codable, Equatable {
    public let baselineFromCreatedAt: QueryDateBound
    public let baselineToCreatedAt: QueryDateBound?
    public let recentFromCreatedAt: QueryDateBound
    public let recentToCreatedAt: QueryDateBound?
    public let asOfCreatedAt: QueryDateBound?
    public let hourFrom: Int?
    public let hourTo: Int?
    public let minBaselineVisits: Int
    public let locality: String?
    public let region: String?
    public let postalCode: String?
    public let countryCode: String?
    public let categoryName: String?
    public let nearLatitude: Double?
    public let nearLongitude: Double?
    public let radiusMeters: Double?
    public let limit: Int
}

public struct VenueComparisonEvidence: Codable, Equatable {
    public let venueID: String
    public let name: String?
    public let latitude: Double?
    public let longitude: Double?
    public let locality: String?
    public let region: String?
    public let postalCode: String?
    public let countryCode: String?
    public let distanceMeters: Double?
    public let baselineVisitCount: Int
    public let recentVisitCount: Int
    public let previousVisitCount: Int
    public let firstCreatedAt: Int?
    public let firstCreatedAtISO8601: String?
    public let lastCreatedAt: Int?
    public let lastCreatedAtISO8601: String?
    public let daysSinceLastVisit: Int?
    public let categories: [String]
    public let drillDown: EvidenceDrillDown
}

public struct QueryCompareResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let compareBy: String
    public let filters: QueryCompareFilters
    public let totalMatchingVenues: Int
    public let returnedVenues: Int
    public let venues: [VenueComparisonEvidence]
}

public extension SwarmDatabase {
    static let queryDefaultLimit = 25
    static let queryHardLimit = 250


    static func queryCategories(
        dbPath: String,
        account: String,
        limit: Int = queryDefaultLimit
    ) throws -> QueryCategoriesResult {
        _ = try AccountLabel.validate(account)
        try validateQueryLimit(limit)
        let dbQueue = try openReadOnlyDatabase(path: dbPath)
        return try dbQueue.read { db in
            let total = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(DISTINCT cat.category_id)
                FROM categories cat
                JOIN checkin_categories cc ON cc.category_id = cat.category_id
                JOIN checkins c ON c.checkin_id = cc.checkin_id
                WHERE c.account = ?
                """,
                arguments: [account]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    cat.category_id,
                    cat.name,
                    COUNT(DISTINCT c.checkin_id) AS checkin_count,
                    COUNT(DISTINCT c.venue_id) AS venue_count,
                    MIN(c.created_at_unix) AS first_created_at,
                    MAX(c.created_at_unix) AS last_created_at
                FROM categories cat
                JOIN checkin_categories cc ON cc.category_id = cat.category_id
                JOIN checkins c ON c.checkin_id = cc.checkin_id
                WHERE c.account = ?
                GROUP BY cat.category_id, cat.name
                ORDER BY checkin_count DESC, venue_count DESC, lower(cat.name) ASC
                LIMIT ?
                """,
                arguments: [account, limit]
            )

            let categories = rows.map { row in
                let firstCreatedAt: Int? = row["first_created_at"]
                let lastCreatedAt: Int? = row["last_created_at"]
                return CategoryEvidence(
                    categoryID: row["category_id"],
                    name: row["name"],
                    checkinCount: row["checkin_count"],
                    venueCount: row["venue_count"],
                    firstCreatedAt: firstCreatedAt,
                    firstCreatedAtISO8601: firstCreatedAt.map(queryISO8601String(timestamp:)),
                    lastCreatedAt: lastCreatedAt,
                    lastCreatedAtISO8601: lastCreatedAt.map(queryISO8601String(timestamp:))
                )
            }

            return QueryCategoriesResult(
                schemaVersion: 1,
                command: "query categories",
                account: account,
                dbPath: dbPath,
                limit: limit,
                totalMatchingCategories: total,
                returnedCategories: categories.count,
                categories: categories
            )
        }
    }

    static func queryVenues(
        dbPath: String,
        account: String,
        fromCreatedAt: Int? = nil,
        toCreatedAt: Int? = nil,
        date: String? = nil,
        hourFrom: Int? = nil,
        hourTo: Int? = nil,
        locality: String? = nil,
        region: String? = nil,
        postalCode: String? = nil,
        countryCode: String? = nil,
        categoryName: String? = nil,
        nearLatitude: Double? = nil,
        nearLongitude: Double? = nil,
        radiusMeters: Double? = nil,
        limit: Int = queryDefaultLimit
    ) throws -> QueryVenuesResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try AccountLabel.validate(account)
        try validateQueryLimit(limit)
        try validateDateWindow(fromCreatedAt: fromCreatedAt, toCreatedAt: toCreatedAt)
        try validateCalendarFilters(date: date, hourFrom: hourFrom, hourTo: hourTo)
        try validatePlaceFilters(locality: locality, region: region, postalCode: postalCode, countryCode: countryCode)
        try validateCategoryFilter(categoryName)
        try validateGeoFilters(nearLatitude: nearLatitude, nearLongitude: nearLongitude, radiusMeters: radiusMeters)

        let dbQueue = try openReadOnlyDatabase(path: dbPath)

        return try dbQueue.read { db in
            registerDistanceFunction(db)
            let total = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM (
                    SELECT c.venue_id
                    FROM checkins c
                    JOIN venues v ON v.venue_id = c.venue_id
                    WHERE c.account = ?
                      AND c.venue_id IS NOT NULL
                      AND (? IS NULL OR c.created_at_unix >= ?)
                      AND (? IS NULL OR c.created_at_unix <= ?)
                      AND (? IS NULL OR c.local_date = ?)
                      AND (? IS NULL OR c.local_hour >= ?)
                      AND (? IS NULL OR c.local_hour <= ?)
                      AND (? IS NULL OR lower(v.locality) = lower(?))
                      AND (? IS NULL OR lower(v.region) = lower(?))
                      AND (? IS NULL OR lower(v.postal_code) = lower(?))
                      AND (? IS NULL OR lower(v.country_code) = lower(?))
                      AND (? IS NULL OR EXISTS (
                          SELECT 1
                          FROM checkin_categories cc
                          JOIN categories cat ON cat.category_id = cc.category_id
                          WHERE cc.checkin_id = c.checkin_id
                            AND lower(cat.name) = lower(?)
                      ))
                      AND (? IS NULL OR (v.lat IS NOT NULL AND v.lng IS NOT NULL AND distance_meters(v.lat, v.lng, ?, ?) <= ?))
                    GROUP BY c.venue_id
                )
                """,
                arguments: [
                    account,
                    fromCreatedAt, fromCreatedAt,
                    toCreatedAt, toCreatedAt,
                    date, date,
                    hourFrom, hourFrom,
                    hourTo, hourTo,
                    locality, locality,
                    region, region,
                    postalCode, postalCode,
                    countryCode, countryCode,
                    categoryName, categoryName,
                    radiusMeters, nearLatitude, nearLongitude, radiusMeters
                ]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    v.venue_id,
                    v.name,
                    v.lat,
                    v.lng,
                    v.locality,
                    v.region,
                    v.postal_code,
                    v.country_code,
                    CASE WHEN ? IS NULL THEN NULL ELSE distance_meters(v.lat, v.lng, ?, ?) END AS distance_meters,
                    COUNT(c.checkin_id) AS visit_count,
                    MIN(c.created_at_unix) AS first_created_at,
                    MAX(c.created_at_unix) AS last_created_at
                FROM checkins c
                JOIN venues v ON v.venue_id = c.venue_id
                WHERE c.account = ?
                  AND c.venue_id IS NOT NULL
                  AND (? IS NULL OR c.created_at_unix >= ?)
                  AND (? IS NULL OR c.created_at_unix <= ?)
                  AND (? IS NULL OR c.local_date = ?)
                  AND (? IS NULL OR c.local_hour >= ?)
                  AND (? IS NULL OR c.local_hour <= ?)
                  AND (? IS NULL OR lower(v.locality) = lower(?))
                  AND (? IS NULL OR lower(v.region) = lower(?))
                  AND (? IS NULL OR lower(v.postal_code) = lower(?))
                  AND (? IS NULL OR lower(v.country_code) = lower(?))
                  AND (? IS NULL OR EXISTS (
                      SELECT 1
                      FROM checkin_categories cc
                      JOIN categories cat ON cat.category_id = cc.category_id
                      WHERE cc.checkin_id = c.checkin_id
                        AND lower(cat.name) = lower(?)
                  ))
                  AND (? IS NULL OR (v.lat IS NOT NULL AND v.lng IS NOT NULL AND distance_meters(v.lat, v.lng, ?, ?) <= ?))
                GROUP BY v.venue_id, v.name, v.lat, v.lng, v.locality, v.region, v.postal_code, v.country_code
                ORDER BY CASE WHEN ? IS NULL THEN 0 ELSE distance_meters END ASC, visit_count DESC, last_created_at DESC, COALESCE(v.name, '') ASC
                LIMIT ?
                """,
                arguments: [
                    nearLatitude, nearLatitude, nearLongitude,
                    account,
                    fromCreatedAt, fromCreatedAt,
                    toCreatedAt, toCreatedAt,
                    date, date,
                    hourFrom, hourFrom,
                    hourTo, hourTo,
                    locality, locality,
                    region, region,
                    postalCode, postalCode,
                    countryCode, countryCode,
                    categoryName, categoryName,
                    radiusMeters, nearLatitude, nearLongitude, radiusMeters,
                    radiusMeters,
                    limit
                ]
            )

            let venues = try rows.map { row in
                let venueID: String = row["venue_id"]
                let firstCreatedAt: Int? = row["first_created_at"]
                let lastCreatedAt: Int? = row["last_created_at"]
                return VenueEvidence(
                    venueID: venueID,
                    name: row["name"],
                    latitude: row["lat"],
                    longitude: row["lng"],
                    locality: row["locality"],
                    region: row["region"],
                    postalCode: row["postal_code"],
                    countryCode: row["country_code"],
                    distanceMeters: row["distance_meters"],
                    visitCount: row["visit_count"],
                    firstCreatedAt: firstCreatedAt,
                    firstCreatedAtISO8601: firstCreatedAt.map(queryISO8601String(timestamp:)),
                    lastCreatedAt: lastCreatedAt,
                    lastCreatedAtISO8601: lastCreatedAt.map(queryISO8601String(timestamp:)),
                    categories: try categoryNames(
                        db: db,
                        account: account,
                        venueID: venueID,
                        checkinID: nil,
                        fromCreatedAt: fromCreatedAt,
                        toCreatedAt: toCreatedAt,
                        date: date,
                        hourFrom: hourFrom,
                        hourTo: hourTo
                    ),
                    drillDown: venueDrillDown(
                        account: account,
                        dbPath: dbPath,
                        venueID: venueID,
                        fromCreatedAt: fromCreatedAt,
                        toCreatedAt: toCreatedAt,
                        date: date,
                        hourFrom: hourFrom,
                        hourTo: hourTo
                    )
                )
            }

            return QueryVenuesResult(
                schemaVersion: 1,
                command: "query venues",
                account: account,
                dbPath: dbPath,
                filters: QueryDateFilters(
                    fromCreatedAt: fromCreatedAt.map(queryDateBound(timestamp:)),
                    toCreatedAt: toCreatedAt.map(queryDateBound(timestamp:)),
                    date: date,
                    hourFrom: hourFrom,
                    hourTo: hourTo,
                    locality: locality,
                    region: region,
                    postalCode: postalCode,
                    countryCode: countryCode,
                    categoryName: categoryName,
                    nearLatitude: nearLatitude,
                    nearLongitude: nearLongitude,
                    radiusMeters: radiusMeters,
                    limit: limit
                ),
                totalMatchingVenues: total,
                returnedVenues: venues.count,
                venues: venues
            )
        }
    }

    static func queryVisits(
        dbPath: String,
        account: String,
        venueID: String? = nil,
        fromCreatedAt: Int? = nil,
        toCreatedAt: Int? = nil,
        date: String? = nil,
        hourFrom: Int? = nil,
        hourTo: Int? = nil,
        limit: Int = queryDefaultLimit
    ) throws -> QueryVisitsResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try AccountLabel.validate(account)
        try validateQueryLimit(limit)
        try validateDateWindow(fromCreatedAt: fromCreatedAt, toCreatedAt: toCreatedAt)
        try validateCalendarFilters(date: date, hourFrom: hourFrom, hourTo: hourTo)
        if let venueID, venueID.isEmpty {
            throw CLIError("--venue-id must not be empty.")
        }

        let dbQueue = try openReadOnlyDatabase(path: dbPath)

        return try dbQueue.read { db in
            let total = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM checkins c
                WHERE c.account = ?
                  AND (? IS NULL OR c.venue_id = ?)
                  AND (? IS NULL OR c.created_at_unix >= ?)
                  AND (? IS NULL OR c.created_at_unix <= ?)
                  AND (? IS NULL OR c.local_date = ?)
                  AND (? IS NULL OR c.local_hour >= ?)
                  AND (? IS NULL OR c.local_hour <= ?)
                """,
                arguments: [
                    account,
                    venueID, venueID,
                    fromCreatedAt, fromCreatedAt,
                    toCreatedAt, toCreatedAt,
                    date, date,
                    hourFrom, hourFrom,
                    hourTo, hourTo
                ]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    c.checkin_id,
                    c.created_at_unix,
                    c.local_timezone_id,
                    c.local_timezone_offset_minutes,
                    c.local_created_at,
                    c.local_date,
                    c.local_hour,
                    c.local_weekday_iso,
                    c.source_adapter,
                    v.venue_id,
                    v.name AS venue_name,
                    v.lat,
                    v.lng
                FROM checkins c
                LEFT JOIN venues v ON v.venue_id = c.venue_id
                WHERE c.account = ?
                  AND (? IS NULL OR c.venue_id = ?)
                  AND (? IS NULL OR c.created_at_unix >= ?)
                  AND (? IS NULL OR c.created_at_unix <= ?)
                  AND (? IS NULL OR c.local_date = ?)
                  AND (? IS NULL OR c.local_hour >= ?)
                  AND (? IS NULL OR c.local_hour <= ?)
                ORDER BY c.created_at_unix DESC, c.checkin_id DESC
                LIMIT ?
                """,
                arguments: [
                    account,
                    venueID, venueID,
                    fromCreatedAt, fromCreatedAt,
                    toCreatedAt, toCreatedAt,
                    date, date,
                    hourFrom, hourFrom,
                    hourTo, hourTo,
                    limit
                ]
            )

            let visits = try rows.map { row in
                let checkinID: String = row["checkin_id"]
                let createdAt: Int? = row["created_at_unix"]
                let rowVenueID: String? = row["venue_id"]
                return VisitEvidence(
                    checkinID: checkinID,
                    createdAt: createdAt,
                    createdAtISO8601: createdAt.map(queryISO8601String(timestamp:)),
                    localTimezoneID: row["local_timezone_id"],
                    localTimezoneOffsetMinutes: row["local_timezone_offset_minutes"],
                    localCreatedAt: row["local_created_at"],
                    localDate: row["local_date"],
                    localHour: row["local_hour"],
                    localWeekdayISO: row["local_weekday_iso"],
                    venueID: rowVenueID,
                    venueName: row["venue_name"],
                    latitude: row["lat"],
                    longitude: row["lng"],
                    categories: try categoryNames(
                        db: db,
                        account: account,
                        venueID: rowVenueID,
                        checkinID: checkinID,
                        fromCreatedAt: fromCreatedAt,
                        toCreatedAt: toCreatedAt,
                        date: date,
                        hourFrom: hourFrom,
                        hourTo: hourTo
                    ),
                    sourceAdapter: row["source_adapter"]
                )
            }

            return QueryVisitsResult(
                schemaVersion: 1,
                command: "query visits",
                account: account,
                dbPath: dbPath,
                filters: QueryVisitFilters(
                    fromCreatedAt: fromCreatedAt.map(queryDateBound(timestamp:)),
                    toCreatedAt: toCreatedAt.map(queryDateBound(timestamp:)),
                    date: date,
                    hourFrom: hourFrom,
                    hourTo: hourTo,
                    venueID: venueID,
                    limit: limit
                ),
                totalMatchingVisits: total,
                returnedVisits: visits.count,
                visits: visits
            )
        }
    }



    static func queryCompare(
        dbPath: String,
        account: String,
        baselineFromCreatedAt: Int,
        baselineToCreatedAt: Int? = nil,
        recentFromCreatedAt: Int,
        recentToCreatedAt: Int? = nil,
        asOfCreatedAt: Int? = nil,
        hourFrom: Int? = nil,
        hourTo: Int? = nil,
        locality: String? = nil,
        region: String? = nil,
        postalCode: String? = nil,
        countryCode: String? = nil,
        categoryName: String? = nil,
        nearLatitude: Double? = nil,
        nearLongitude: Double? = nil,
        radiusMeters: Double? = nil,
        minBaselineVisits: Int = 1,
        limit: Int = queryDefaultLimit
    ) throws -> QueryCompareResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try AccountLabel.validate(account)
        try validateQueryLimit(limit)
        try validateDateWindow(fromCreatedAt: baselineFromCreatedAt, toCreatedAt: baselineToCreatedAt)
        try validateDateWindow(fromCreatedAt: recentFromCreatedAt, toCreatedAt: recentToCreatedAt)
        try validateCalendarFilters(date: nil, hourFrom: hourFrom, hourTo: hourTo)
        try validatePlaceFilters(locality: locality, region: region, postalCode: postalCode, countryCode: countryCode)
        try validateCategoryFilter(categoryName)
        try validateGeoFilters(nearLatitude: nearLatitude, nearLongitude: nearLongitude, radiusMeters: radiusMeters)
        guard recentFromCreatedAt >= baselineFromCreatedAt else {
            throw CLIError("--recent-from must be greater than or equal to --baseline-from.")
        }
        if minBaselineVisits < 1 {
            throw CLIError("--min-baseline-visits must be at least 1.")
        }

        let dbQueue = try openReadOnlyDatabase(path: dbPath)

        return try dbQueue.read { db in
            registerDistanceFunction(db)
            let effectiveAsOf = try asOfCreatedAt ?? Int.fetchOne(
                db,
                sql: """
                SELECT MAX(c.created_at_unix)
                FROM checkins c
                WHERE c.account = ?
                  AND (? IS NULL OR c.local_hour >= ?)
                  AND (? IS NULL OR c.local_hour <= ?)
                """,
                arguments: [account, hourFrom, hourFrom, hourTo, hourTo]
            )

            let total = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM (
                    SELECT c.venue_id
                    FROM checkins c
                    WHERE c.account = ?
                      AND c.venue_id IS NOT NULL
                      AND c.created_at_unix >= ?
                      AND (? IS NULL OR c.created_at_unix <= ?)
                      AND (? IS NULL OR c.local_hour >= ?)
                      AND (? IS NULL OR c.local_hour <= ?)
                      AND (? IS NULL OR EXISTS (
                          SELECT 1 FROM venues v
                          WHERE v.venue_id = c.venue_id
                            AND lower(v.locality) = lower(?)
                      ))
                      AND (? IS NULL OR EXISTS (
                          SELECT 1 FROM venues v
                          WHERE v.venue_id = c.venue_id
                            AND lower(v.region) = lower(?)
                      ))
                      AND (? IS NULL OR EXISTS (
                          SELECT 1 FROM venues v
                          WHERE v.venue_id = c.venue_id
                            AND lower(v.postal_code) = lower(?)
                      ))
                      AND (? IS NULL OR EXISTS (
                          SELECT 1 FROM venues v
                          WHERE v.venue_id = c.venue_id
                            AND lower(v.country_code) = lower(?)
                      ))
                      AND (? IS NULL OR EXISTS (
                          SELECT 1
                          FROM checkin_categories cc
                          JOIN categories cat ON cat.category_id = cc.category_id
                          WHERE cc.checkin_id = c.checkin_id
                            AND lower(cat.name) = lower(?)
                      ))
                      AND (? IS NULL OR EXISTS (
                          SELECT 1 FROM venues v
                          WHERE v.venue_id = c.venue_id
                            AND v.lat IS NOT NULL
                            AND v.lng IS NOT NULL
                            AND distance_meters(v.lat, v.lng, ?, ?) <= ?
                      ))
                    GROUP BY c.venue_id
                    HAVING COUNT(c.checkin_id) >= ?
                )
                """,
                arguments: [
                    account,
                    baselineFromCreatedAt,
                    baselineToCreatedAt, baselineToCreatedAt,
                    hourFrom, hourFrom,
                    hourTo, hourTo,
                    locality, locality,
                    region, region,
                    postalCode, postalCode,
                    countryCode, countryCode,
                    categoryName, categoryName,
                    radiusMeters, nearLatitude, nearLongitude, radiusMeters,
                    minBaselineVisits
                ]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    v.venue_id,
                    v.name,
                    v.lat,
                    v.lng,
                    v.locality,
                    v.region,
                    v.postal_code,
                    v.country_code,
                    CASE WHEN ? IS NULL THEN NULL ELSE distance_meters(v.lat, v.lng, ?, ?) END AS distance_meters,
                    COUNT(c.checkin_id) AS baseline_visit_count,
                    SUM(CASE
                        WHEN c.created_at_unix >= ?
                         AND (? IS NULL OR c.created_at_unix <= ?)
                        THEN 1 ELSE 0 END) AS recent_visit_count,
                    SUM(CASE
                        WHEN c.created_at_unix < ?
                        THEN 1 ELSE 0 END) AS previous_visit_count,
                    MIN(c.created_at_unix) AS first_created_at,
                    MAX(c.created_at_unix) AS last_created_at
                FROM checkins c
                JOIN venues v ON v.venue_id = c.venue_id
                WHERE c.account = ?
                  AND c.venue_id IS NOT NULL
                  AND c.created_at_unix >= ?
                  AND (? IS NULL OR c.created_at_unix <= ?)
                  AND (? IS NULL OR c.local_hour >= ?)
                  AND (? IS NULL OR c.local_hour <= ?)
                  AND (? IS NULL OR lower(v.locality) = lower(?))
                  AND (? IS NULL OR lower(v.region) = lower(?))
                  AND (? IS NULL OR lower(v.postal_code) = lower(?))
                  AND (? IS NULL OR lower(v.country_code) = lower(?))
                  AND (? IS NULL OR EXISTS (
                      SELECT 1
                      FROM checkin_categories cc
                      JOIN categories cat ON cat.category_id = cc.category_id
                      WHERE cc.checkin_id = c.checkin_id
                        AND lower(cat.name) = lower(?)
                  ))
                  AND (? IS NULL OR (v.lat IS NOT NULL AND v.lng IS NOT NULL AND distance_meters(v.lat, v.lng, ?, ?) <= ?))
                GROUP BY v.venue_id, v.name, v.lat, v.lng, v.locality, v.region, v.postal_code, v.country_code
                HAVING baseline_visit_count >= ?
                ORDER BY CASE WHEN ? IS NULL THEN 0 ELSE distance_meters END ASC, recent_visit_count ASC, last_created_at ASC, baseline_visit_count DESC, COALESCE(v.name, '') ASC
                LIMIT ?
                """,
                arguments: [
                    nearLatitude, nearLatitude, nearLongitude,
                    recentFromCreatedAt,
                    recentToCreatedAt, recentToCreatedAt,
                    recentFromCreatedAt,
                    account,
                    baselineFromCreatedAt,
                    baselineToCreatedAt, baselineToCreatedAt,
                    hourFrom, hourFrom,
                    hourTo, hourTo,
                    locality, locality,
                    region, region,
                    postalCode, postalCode,
                    countryCode, countryCode,
                    categoryName, categoryName,
                    radiusMeters, nearLatitude, nearLongitude, radiusMeters,
                    minBaselineVisits,
                    radiusMeters,
                    limit
                ]
            )

            let venues = try rows.map { row in
                let venueID: String = row["venue_id"]
                let firstCreatedAt: Int? = row["first_created_at"]
                let lastCreatedAt: Int? = row["last_created_at"]
                let daysSinceLastVisit: Int? = {
                    guard let effectiveAsOf, let lastCreatedAt else { return nil }
                    return max(0, (effectiveAsOf - lastCreatedAt) / 86_400)
                }()
                return VenueComparisonEvidence(
                    venueID: venueID,
                    name: row["name"],
                    latitude: row["lat"],
                    longitude: row["lng"],
                    locality: row["locality"],
                    region: row["region"],
                    postalCode: row["postal_code"],
                    countryCode: row["country_code"],
                    distanceMeters: row["distance_meters"],
                    baselineVisitCount: row["baseline_visit_count"],
                    recentVisitCount: row["recent_visit_count"],
                    previousVisitCount: row["previous_visit_count"],
                    firstCreatedAt: firstCreatedAt,
                    firstCreatedAtISO8601: firstCreatedAt.map(queryISO8601String(timestamp:)),
                    lastCreatedAt: lastCreatedAt,
                    lastCreatedAtISO8601: lastCreatedAt.map(queryISO8601String(timestamp:)),
                    daysSinceLastVisit: daysSinceLastVisit,
                    categories: try categoryNames(
                        db: db,
                        account: account,
                        venueID: venueID,
                        checkinID: nil,
                        fromCreatedAt: baselineFromCreatedAt,
                        toCreatedAt: baselineToCreatedAt,
                        date: nil,
                        hourFrom: hourFrom,
                        hourTo: hourTo
                    ),
                    drillDown: venueDrillDown(
                        account: account,
                        dbPath: dbPath,
                        venueID: venueID,
                        fromCreatedAt: baselineFromCreatedAt,
                        toCreatedAt: baselineToCreatedAt,
                        date: nil,
                        hourFrom: hourFrom,
                        hourTo: hourTo
                    )
                )
            }

            return QueryCompareResult(
                schemaVersion: 1,
                command: "query compare",
                account: account,
                dbPath: dbPath,
                compareBy: "venue",
                filters: QueryCompareFilters(
                    baselineFromCreatedAt: queryDateBound(timestamp: baselineFromCreatedAt),
                    baselineToCreatedAt: baselineToCreatedAt.map(queryDateBound(timestamp:)),
                    recentFromCreatedAt: queryDateBound(timestamp: recentFromCreatedAt),
                    recentToCreatedAt: recentToCreatedAt.map(queryDateBound(timestamp:)),
                    asOfCreatedAt: effectiveAsOf.map(queryDateBound(timestamp:)),
                    hourFrom: hourFrom,
                    hourTo: hourTo,
                    minBaselineVisits: minBaselineVisits,
                    locality: locality,
                    region: region,
                    postalCode: postalCode,
                    countryCode: countryCode,
                    categoryName: categoryName,
                    nearLatitude: nearLatitude,
                    nearLongitude: nearLongitude,
                    radiusMeters: radiusMeters,
                    limit: limit
                ),
                totalMatchingVenues: total,
                returnedVenues: venues.count,
                venues: venues
            )
        }
    }

    static func validateQueryOptions(
        fromCreatedAt: Int?,
        toCreatedAt: Int?,
        date: String? = nil,
        hourFrom: Int? = nil,
        hourTo: Int? = nil,
        limit: Int
    ) throws {
        try validateQueryLimit(limit)
        try validateDateWindow(fromCreatedAt: fromCreatedAt, toCreatedAt: toCreatedAt)
        try validateCalendarFilters(date: date, hourFrom: hourFrom, hourTo: hourTo)
    }

    static func validatePlaceOptions(
        locality: String?,
        region: String?,
        postalCode: String?,
        countryCode: String?
    ) throws {
        try validatePlaceFilters(locality: locality, region: region, postalCode: postalCode, countryCode: countryCode)
    }

    static func validateCategoryOptions(_ categoryName: String?) throws {
        try validateCategoryFilter(categoryName)
    }

    static func validateGeoOptions(
        nearLatitude: Double?,
        nearLongitude: Double?,
        radiusMeters: Double?
    ) throws {
        try validateGeoFilters(nearLatitude: nearLatitude, nearLongitude: nearLongitude, radiusMeters: radiusMeters)
    }

    static func parseQueryTimestamp(_ rawValue: String?, optionName: String) throws -> Int? {
        guard let rawValue else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw CLIError("\(optionName) must not be empty.")
        }
        if let timestamp = Int(value) {
            return timestamp
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = fractionalFormatter.date(from: value) {
            return Int(date.timeIntervalSince1970)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = formatter.date(from: value) {
            return Int(date.timeIntervalSince1970)
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: value) {
            let timestamp = Int(date.timeIntervalSince1970)
            return optionName == "--to" ? timestamp + 86_399 : timestamp
        }

        throw CLIError("\(optionName) must be a Unix timestamp, ISO8601 instant, or YYYY-MM-DD date.")
    }
}

private func validatePlaceFilters(locality: String?, region: String?, postalCode: String?, countryCode: String?) throws {
    for (name, value) in [("--locality", locality), ("--region", region), ("--postal-code", postalCode), ("--country-code", countryCode)] {
        if let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError("\(name) must not be empty.")
        }
    }
}

private func validateCategoryFilter(_ categoryName: String?) throws {
    if let categoryName, categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw CLIError("--category must not be empty.")
    }
}

private func validateGeoFilters(nearLatitude: Double?, nearLongitude: Double?, radiusMeters: Double?) throws {
    if nearLatitude == nil && nearLongitude == nil && radiusMeters == nil { return }
    guard let nearLatitude, let nearLongitude, let radiusMeters else {
        throw CLIError("--near-lat, --near-lng, and --radius-meters must be used together.")
    }
    guard (-90...90).contains(nearLatitude) else { throw CLIError("--near-lat must be between -90 and 90.") }
    guard (-180...180).contains(nearLongitude) else { throw CLIError("--near-lng must be between -180 and 180.") }
    guard radiusMeters > 0 else { throw CLIError("--radius-meters must be greater than 0.") }
}

private func registerDistanceFunction(_ db: Database) {
    db.add(function: DatabaseFunction("distance_meters", argumentCount: 4, pure: true) { values in
        guard
            let lat1 = Double.fromDatabaseValue(values[0]),
            let lng1 = Double.fromDatabaseValue(values[1]),
            let lat2 = Double.fromDatabaseValue(values[2]),
            let lng2 = Double.fromDatabaseValue(values[3])
        else { return nil }
        return haversineDistanceMeters(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2)
    })
}

private func haversineDistanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
    let earthRadiusMeters = 6_371_000.0
    let phi1 = lat1 * .pi / 180
    let phi2 = lat2 * .pi / 180
    let deltaPhi = (lat2 - lat1) * .pi / 180
    let deltaLambda = (lng2 - lng1) * .pi / 180
    let a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
    return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
}

private func validateCalendarFilters(date: String?, hourFrom: Int?, hourTo: Int?) throws {
    if let date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: date) != nil else {
            throw CLIError("--date must use YYYY-MM-DD.")
        }
    }
    if let hourFrom, !(0...23).contains(hourFrom) {
        throw CLIError("--hour-from must be between 0 and 23.")
    }
    if let hourTo, !(0...23).contains(hourTo) {
        throw CLIError("--hour-to must be between 0 and 23.")
    }
    if let hourFrom, let hourTo, hourFrom > hourTo {
        throw CLIError("--hour-from must be less than or equal to --hour-to.")
    }
}

private func validateQueryLimit(_ limit: Int) throws {
    guard limit >= 1 else {
        throw CLIError("--limit must be at least 1.")
    }
    guard limit <= SwarmDatabase.queryHardLimit else {
        throw CLIError("--limit \(limit) exceeds the hard max of \(SwarmDatabase.queryHardLimit).")
    }
}

private func validateDateWindow(fromCreatedAt: Int?, toCreatedAt: Int?) throws {
    if let fromCreatedAt, let toCreatedAt, fromCreatedAt > toCreatedAt {
        throw CLIError("--from must be less than or equal to --to.")
    }
}

private func categoryNames(
    db: Database,
    account: String,
    venueID: String?,
    checkinID: String?,
    fromCreatedAt: Int?,
    toCreatedAt: Int?,
    date: String?,
    hourFrom: Int?,
    hourTo: Int?
) throws -> [String] {
    try String.fetchAll(
        db,
        sql: """
        SELECT DISTINCT cat.name
        FROM categories cat
        JOIN checkin_categories cc ON cc.category_id = cat.category_id
        JOIN checkins c ON c.checkin_id = cc.checkin_id
        WHERE c.account = ?
          AND (? IS NULL OR cc.venue_id = ?)
          AND (? IS NULL OR cc.checkin_id = ?)
          AND (? IS NULL OR c.created_at_unix >= ?)
          AND (? IS NULL OR c.created_at_unix <= ?)
          AND (? IS NULL OR c.local_date = ?)
          AND (? IS NULL OR c.local_hour >= ?)
          AND (? IS NULL OR c.local_hour <= ?)
          AND cat.name IS NOT NULL
        ORDER BY cat.name ASC
        """,
        arguments: [
            account,
            venueID, venueID,
            checkinID, checkinID,
            fromCreatedAt, fromCreatedAt,
            toCreatedAt, toCreatedAt,
            date, date,
            hourFrom, hourFrom,
            hourTo, hourTo
        ]
    )
}

private func venueDrillDown(
    account: String,
    dbPath: String,
    venueID: String,
    fromCreatedAt: Int?,
    toCreatedAt: Int?,
    date: String?,
    hourFrom: Int?,
    hourTo: Int?
) -> EvidenceDrillDown {
    var arguments = [
        "query", "visits",
        "--account", account,
        "--db", dbPath,
        "--venue-id", venueID
    ]
    if let fromCreatedAt {
        arguments.append(contentsOf: ["--from", String(fromCreatedAt)])
    }
    if let toCreatedAt {
        arguments.append(contentsOf: ["--to", String(toCreatedAt)])
    }
    if let date {
        arguments.append(contentsOf: ["--date", date])
    }
    if let hourFrom {
        arguments.append(contentsOf: ["--hour-from", String(hourFrom)])
    }
    if let hourTo {
        arguments.append(contentsOf: ["--hour-to", String(hourTo)])
    }
    return EvidenceDrillDown(command: "swarm-cadence", arguments: arguments)
}

private func queryDateBound(timestamp: Int) -> QueryDateBound {
    QueryDateBound(unix: timestamp, iso8601: queryISO8601String(timestamp: timestamp))
}

private func queryISO8601String(timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
