import Foundation

public struct EvidenceWindow: Codable, Equatable {
    public let date: String
    public let hourFrom: Int?
    public let hourTo: Int?
}

public struct EvidenceGeography: Codable, Equatable {
    public let locality: String?
    public let region: String?
    public let postalCode: String?
    public let countryCode: String?
    public let categoryName: String?
    public let nearLatitude: Double?
    public let nearLongitude: Double?
    public let radiusMeters: Double?
    public let semantics: String
}

public struct EvidenceSourceCoverage: Codable, Equatable {
    public let dbPath: String
    public let checkins: Int
    public let venues: Int
    public let oldestCreatedAtISO8601: String?
    public let latestCreatedAtISO8601: String?
}

public struct EvidenceWindowPacket: Codable, Equatable {
    public let schema: String
    public let generatedAt: String
    public let command: String
    public let account: String
    public let window: EvidenceWindow
    public let sourceCoverage: EvidenceSourceCoverage
    public let totalMatchingVenues: Int
    public let returnedVenues: Int
    public let candidateVenues: [VenueEvidence]
    public let sources: [EvidenceSource]
    public let caveats: [String]
}

public struct EvidencePacket: Codable, Equatable {
    public let schema: String
    public let generatedAt: String
    public let command: String
    public let account: String
    public let targetWindow: EvidenceWindow
    public let geography: EvidenceGeography
    public let sourceCoverage: EvidenceSourceCoverage
    public let venueSupport: QueryVenuesResult
    public let cadenceComparison: QueryCompareResult
    public let sources: [EvidenceSource]
    public let caveats: [String]
}

public struct EvidenceSource: Codable, Equatable {
    public let id: String
    public let kind: String
    public let scope: String
}

public extension SwarmDatabase {
    static func evidenceWindow(
        dbPath: String,
        account: String,
        date: String,
        hourFrom: Int? = nil,
        hourTo: Int? = nil,
        limit: Int = queryDefaultLimit,
        generatedAt: Date = Date()
    ) throws -> EvidenceWindowPacket {
        try validateQueryOptions(
            fromCreatedAt: nil,
            toCreatedAt: nil,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
        let venues = try queryVenues(
            dbPath: dbPath,
            account: account,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
        let stats = try SwarmDatabase.stats(dbPath: dbPath, account: account)

        return EvidenceWindowPacket(
            schema: "swarm_window_evidence_packet.v0",
            generatedAt: evidenceISO8601String(generatedAt),
            command: "evidence window",
            account: venues.account,
            window: EvidenceWindow(date: date, hourFrom: hourFrom, hourTo: hourTo),
            sourceCoverage: evidenceSourceCoverage(dbPath: dbPath, stats: stats),
            totalMatchingVenues: venues.totalMatchingVenues,
            returnedVenues: venues.returnedVenues,
            candidateVenues: venues.venues,
            sources: swarmSources(account: venues.account),
            caveats: windowCaveats
        )
    }

    static func evidencePacket(
        dbPath: String,
        account: String,
        date: String,
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
        baselineFromCreatedAt: Int,
        baselineToCreatedAt: Int? = nil,
        recentFromCreatedAt: Int,
        recentToCreatedAt: Int? = nil,
        asOfCreatedAt: Int? = nil,
        minBaselineVisits: Int = 1,
        limit: Int = queryDefaultLimit,
        generatedAt: Date = Date()
    ) throws -> EvidencePacket {
        try validateQueryOptions(
            fromCreatedAt: nil,
            toCreatedAt: nil,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
        try validatePlaceOptions(locality: locality, region: region, postalCode: postalCode, countryCode: countryCode)
        try validateCategoryOptions(categoryName)
        try validateGeoOptions(nearLatitude: nearLatitude, nearLongitude: nearLongitude, radiusMeters: radiusMeters)

        let venues = try queryVenues(
            dbPath: dbPath,
            account: account,
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
        )
        let compare = try queryCompare(
            dbPath: dbPath,
            account: account,
            baselineFromCreatedAt: baselineFromCreatedAt,
            baselineToCreatedAt: baselineToCreatedAt,
            recentFromCreatedAt: recentFromCreatedAt,
            recentToCreatedAt: recentToCreatedAt,
            asOfCreatedAt: asOfCreatedAt,
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
            minBaselineVisits: minBaselineVisits,
            limit: limit
        )
        let stats = try SwarmDatabase.stats(dbPath: dbPath, account: account)

        return EvidencePacket(
            schema: "swarm_experimental_packet",
            generatedAt: evidenceISO8601String(generatedAt),
            command: "evidence packet",
            account: venues.account,
            targetWindow: EvidenceWindow(date: date, hourFrom: hourFrom, hourTo: hourTo),
            geography: EvidenceGeography(
                locality: locality,
                region: region,
                postalCode: postalCode,
                countryCode: countryCode,
                categoryName: categoryName,
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                radiusMeters: radiusMeters,
                semantics: evidenceGeographySemantics(locality: locality, region: region, postalCode: postalCode, countryCode: countryCode, radiusMeters: radiusMeters)
            ),
            sourceCoverage: evidenceSourceCoverage(dbPath: dbPath, stats: stats),
            venueSupport: venues,
            cadenceComparison: compare,
            sources: swarmSources(account: venues.account),
            caveats: evidencePacketCaveats
        )
    }
}

private let windowCaveats = [
    "Check-ins are evidence of visits, not proof of preference.",
    "Fuzzy labels such as lunch or morning are chosen by the caller over explicit date/hour windows, not by swarm-cadence."
]

private let evidencePacketCaveats = [
    "This is an evidence packet, not a recommendation or ranked answer.",
    "Check-ins are evidence of visits, not proof of preference.",
    "The target window records caller intent; venue support is computed from historical visits matching the explicit filters.",
    "Locality filters mean in-place; near-place semantics should use an anchor/radius or future named area resolver.",
    "No corrections, open-now data, weather, calendar, Paprika, or other cross-source context is joined in this packet."
]

private func evidenceSourceCoverage(dbPath: String, stats: DatabaseStatsResult) -> EvidenceSourceCoverage {
    EvidenceSourceCoverage(
        dbPath: dbPath,
        checkins: stats.checkins,
        venues: stats.venues,
        oldestCreatedAtISO8601: stats.oldestCreatedAtISO8601,
        latestCreatedAtISO8601: stats.latestCreatedAtISO8601
    )
}

private func swarmSources(account: String) -> [EvidenceSource] {
    [
        EvidenceSource(
            id: "swarm_\(account)",
            kind: "swarm_checkins",
            scope: "account"
        )
    ]
}

private func evidenceGeographySemantics(
    locality: String?,
    region: String?,
    postalCode: String?,
    countryCode: String?,
    radiusMeters: Double?
) -> String {
    let hasPlaceFields = locality != nil || region != nil || postalCode != nil || countryCode != nil
    let hasRadius = radiusMeters != nil
    switch (hasPlaceFields, hasRadius) {
    case (true, true):
        return "factual venue-location filters AND explicit map-distance refinement"
    case (true, false):
        return "factual venue-location filters; this means in the specified place fields"
    case (false, true):
        return "explicit map-distance filter around a caller-supplied anchor; this can include nearby localities"
    case (false, false):
        return "no geography filter"
    }
}

private func evidenceISO8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
