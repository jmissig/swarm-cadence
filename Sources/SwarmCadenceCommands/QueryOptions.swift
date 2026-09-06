import ArgumentParser
import Foundation
import SwarmCadenceCore

struct QueryCategoriesOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat
    let limit: Int
    let includeAnnotations: Bool

    init(parsed: QueryCategoriesArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.limit = parsed.limit
        self.includeAnnotations = !parsed.noAnnotations
        try SwarmDatabase.validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
    }
}

struct QueryVenuesOptions {
    let account: String
    let dbPath: String?
    let configPath: String?
    let format: OutputFormat
    let fromCreatedAt: Int?
    let toCreatedAt: Int?
    let date: String?
    let hourFrom: Int?
    let hourTo: Int?
    let locality: String?
    let region: String?
    let postalCode: String?
    let countryCode: String?
    let nearPlace: String?
    let area: String?
    let categoryNames: [String]
    let nearLatitude: Double?
    let nearLongitude: Double?
    let radiusMeters: Double?
    let sort: EvidenceSort?
    let limit: Int
    let includeAnnotations: Bool

    init(parsed: QueryVenuesArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.configPath = parsed.config
        self.fromCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.from, optionName: "--from")
        self.toCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.to, optionName: "--to")
        self.date = parsed.date
        self.hourFrom = parsed.hourFrom
        self.hourTo = parsed.hourTo
        self.locality = parsed.locality
        self.region = parsed.region
        self.postalCode = parsed.postalCode
        self.countryCode = parsed.countryCode
        self.nearPlace = parsed.nearPlace
        self.area = parsed.area
        self.categoryNames = parsed.categoryNames
        self.nearLatitude = parsed.nearLatitude
        self.nearLongitude = parsed.nearLongitude
        self.radiusMeters = parsed.radiusMeters
        self.sort = try SwarmDatabase.parseEvidenceSort(parsed.sort)
        self.limit = parsed.limit
        self.includeAnnotations = !parsed.noAnnotations
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: fromCreatedAt,
            toCreatedAt: toCreatedAt,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
        try SwarmDatabase.validatePlaceOptions(
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode
        )
        try SwarmDatabase.validateCategoryOptions(categoryNames)
        if nearPlace == nil {
            try SwarmDatabase.validateGeoOptions(
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                radiusMeters: radiusMeters
            )
        }
        if sort == .nearest && radiusMeters == nil && nearPlace == nil {
            throw CLIError("--sort nearest requires --near-lat, --near-lng, and --radius-meters.")
        }
        try validateNamedGeographyOptions(
            nearPlace: nearPlace,
            area: area,
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude
        )
    }

    func resolveGeography(environment: [String: String]) throws -> GeographyExpansion {
        try GeographyPresetResolver.resolve(
            account: account,
            configPath: configPath,
            environment: environment,
            nearPlace: nearPlace,
            area: area,
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude,
            radiusMeters: radiusMeters
        )
    }
}

struct QueryVisitsOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat
    let venueID: String?
    let fromCreatedAt: Int?
    let toCreatedAt: Int?
    let date: String?
    let hourFrom: Int?
    let hourTo: Int?
    let categoryNames: [String]
    let limit: Int
    let includeAnnotations: Bool

    init(parsed: QueryVisitsArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        if let venueID = parsed.venueID, venueID.isEmpty {
            throw CLIError("--venue-id must not be empty.")
        }
        self.venueID = parsed.venueID
        self.fromCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.from, optionName: "--from")
        self.toCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.to, optionName: "--to")
        self.date = parsed.date
        self.hourFrom = parsed.hourFrom
        self.hourTo = parsed.hourTo
        self.categoryNames = parsed.categoryNames
        try SwarmDatabase.validateCategoryOptions(categoryNames)
        self.limit = parsed.limit
        self.includeAnnotations = !parsed.noAnnotations
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: fromCreatedAt,
            toCreatedAt: toCreatedAt,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
    }
}


struct QueryCadenceOptions {
    let account: String
    let dbPath: String?
    let configPath: String?
    let format: OutputFormat
    let venueID: String?
    let fromCreatedAt: Int?
    let toCreatedAt: Int?
    let hourFrom: Int?
    let hourTo: Int?
    let locality: String?
    let region: String?
    let postalCode: String?
    let countryCode: String?
    let nearPlace: String?
    let area: String?
    let categoryNames: [String]
    let nearLatitude: Double?
    let nearLongitude: Double?
    let radiusMeters: Double?
    let sort: EvidenceSort?
    let limit: Int

    init(parsed: QueryCadenceArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.configPath = parsed.config
        if let venueID = parsed.venueID, venueID.isEmpty {
            throw CLIError("--venue-id must not be empty.")
        }
        self.venueID = parsed.venueID
        self.fromCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.from, optionName: "--from")
        self.toCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.to, optionName: "--to")
        self.hourFrom = parsed.hourFrom
        self.hourTo = parsed.hourTo
        self.locality = parsed.locality
        self.region = parsed.region
        self.postalCode = parsed.postalCode
        self.countryCode = parsed.countryCode
        self.nearPlace = parsed.nearPlace
        self.area = parsed.area
        self.categoryNames = parsed.categoryNames
        self.nearLatitude = parsed.nearLatitude
        self.nearLongitude = parsed.nearLongitude
        self.radiusMeters = parsed.radiusMeters
        self.sort = try SwarmDatabase.parseEvidenceSort(parsed.sort)
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: fromCreatedAt,
            toCreatedAt: toCreatedAt,
            date: nil,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
        try SwarmDatabase.validatePlaceOptions(
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode
        )
        try SwarmDatabase.validateCategoryOptions(categoryNames)
        if nearPlace == nil {
            try SwarmDatabase.validateGeoOptions(
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                radiusMeters: radiusMeters
            )
        }
        if sort == .nearest && radiusMeters == nil && nearPlace == nil {
            throw CLIError("--sort nearest requires --near-lat, --near-lng, and --radius-meters.")
        }
        try validateNamedGeographyOptions(
            nearPlace: nearPlace,
            area: area,
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude
        )
    }

    func resolveGeography(environment: [String: String]) throws -> GeographyExpansion {
        try GeographyPresetResolver.resolve(
            account: account,
            configPath: configPath,
            environment: environment,
            nearPlace: nearPlace,
            area: area,
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude,
            radiusMeters: radiusMeters
        )
    }
}


struct QueryCompareOptions {
    let account: String
    let dbPath: String?
    let configPath: String?
    let format: OutputFormat
    let baselineFromCreatedAt: Int
    let baselineToCreatedAt: Int?
    let recentFromCreatedAt: Int
    let recentToCreatedAt: Int?
    let asOfCreatedAt: Int?
    let hourFrom: Int?
    let hourTo: Int?
    let locality: String?
    let region: String?
    let postalCode: String?
    let countryCode: String?
    let nearPlace: String?
    let area: String?
    let categoryNames: [String]
    let nearLatitude: Double?
    let nearLongitude: Double?
    let radiusMeters: Double?
    let sort: EvidenceSort?
    let minBaselineVisits: Int
    let limit: Int

    init(parsed: QueryCompareArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.configPath = parsed.config
        guard let baselineFrom = parsed.baselineFrom else {
            throw CLIError("missing required --baseline-from <time>.")
        }
        guard let recentFrom = parsed.recentFrom else {
            throw CLIError("missing required --recent-from <time>.")
        }
        self.baselineFromCreatedAt = try SwarmDatabase.parseQueryTimestamp(baselineFrom, optionName: "--baseline-from")!
        self.baselineToCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.baselineTo, optionName: "--baseline-to")
        self.recentFromCreatedAt = try SwarmDatabase.parseQueryTimestamp(recentFrom, optionName: "--recent-from")!
        self.recentToCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.recentTo, optionName: "--recent-to")
        self.asOfCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.asOf, optionName: "--as-of")
        self.hourFrom = parsed.hourFrom
        self.hourTo = parsed.hourTo
        self.locality = parsed.locality
        self.region = parsed.region
        self.postalCode = parsed.postalCode
        self.countryCode = parsed.countryCode
        self.nearPlace = parsed.nearPlace
        self.area = parsed.area
        self.categoryNames = parsed.categoryNames
        self.nearLatitude = parsed.nearLatitude
        self.nearLongitude = parsed.nearLongitude
        self.radiusMeters = parsed.radiusMeters
        self.sort = try SwarmDatabase.parseEvidenceSort(parsed.sort)
        self.minBaselineVisits = parsed.minBaselineVisits
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: baselineFromCreatedAt,
            toCreatedAt: baselineToCreatedAt,
            date: nil,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: recentFromCreatedAt,
            toCreatedAt: recentToCreatedAt,
            date: nil,
            hourFrom: nil,
            hourTo: nil,
            limit: limit
        )
        try SwarmDatabase.validatePlaceOptions(
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode
        )
        try SwarmDatabase.validateCategoryOptions(categoryNames)
        if nearPlace == nil {
            try SwarmDatabase.validateGeoOptions(
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                radiusMeters: radiusMeters
            )
        }
        if sort == .nearest && radiusMeters == nil && nearPlace == nil {
            throw CLIError("--sort nearest requires --near-lat, --near-lng, and --radius-meters.")
        }
        try validateNamedGeographyOptions(
            nearPlace: nearPlace,
            area: area,
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude
        )
    }

    func resolveGeography(environment: [String: String]) throws -> GeographyExpansion {
        try GeographyPresetResolver.resolve(
            account: account,
            configPath: configPath,
            environment: environment,
            nearPlace: nearPlace,
            area: area,
            locality: locality,
            region: region,
            postalCode: postalCode,
            countryCode: countryCode,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude,
            radiusMeters: radiusMeters
        )
    }
}
