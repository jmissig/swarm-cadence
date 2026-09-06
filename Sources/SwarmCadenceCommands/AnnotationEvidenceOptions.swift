import ArgumentParser
import Foundation
import SwarmCadenceCore

struct AnnotationsAddOptions {
    let account: String
    let dbPath: String?
    let targetKind: String
    let targetID: String
    let body: String
    let source: String
    let format: OutputFormat

    init(parsed: AnnotationsAddArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        if let dbPath = parsed.dbPath, dbPath.isEmpty {
            throw CLIError("--db must not be empty.")
        }
        self.dbPath = parsed.dbPath
        guard let targetKind = parsed.targetKind else {
            throw CLIError("missing required --target-kind <kind>.")
        }
        guard let targetID = parsed.targetID else {
            throw CLIError("missing required --target-id <id>.")
        }
        guard let body = parsed.body else {
            throw CLIError("missing required --body <text>.")
        }
        self.targetKind = targetKind
        self.targetID = targetID
        self.body = body
        self.source = parsed.source
    }
}

struct AnnotationsListOptions {
    let account: String
    let dbPath: String?
    let targetKind: String?
    let targetID: String?
    let limit: Int
    let format: OutputFormat

    init(parsed: AnnotationsListArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        if let dbPath = parsed.dbPath, dbPath.isEmpty {
            throw CLIError("--db must not be empty.")
        }
        self.dbPath = parsed.dbPath
        self.targetKind = parsed.targetKind
        self.targetID = parsed.targetID
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
    }
}


struct AnnotationsTargetsOptions {
    let account: String
    let dbPath: String?
    let kind: String?
    let limit: Int
    let format: OutputFormat

    init(parsed: AnnotationsTargetsArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        if let dbPath = parsed.dbPath, dbPath.isEmpty {
            throw CLIError("--db must not be empty.")
        }
        self.dbPath = parsed.dbPath
        self.kind = parsed.kind
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
    }
}

struct EvidenceWindowOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat
    let date: String
    let hourFrom: Int?
    let hourTo: Int?
    let limit: Int

    init(parsed: EvidenceWindowArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        guard let date = parsed.date else {
            throw CLIError("missing required --date <YYYY-MM-DD>.")
        }
        self.date = date
        self.hourFrom = parsed.hourFrom
        self.hourTo = parsed.hourTo
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: nil,
            toCreatedAt: nil,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
    }
}

struct EvidencePacketOptions {
    let account: String
    let dbPath: String?
    let configPath: String?
    let format: OutputFormat
    let date: String
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
    let baselineFromCreatedAt: Int
    let baselineToCreatedAt: Int?
    let recentFromCreatedAt: Int
    let recentToCreatedAt: Int?
    let asOfCreatedAt: Int?
    let minBaselineVisits: Int
    let limit: Int

    init(parsed: EvidencePacketArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.configPath = parsed.config
        guard let date = parsed.date else {
            throw CLIError("missing required --date <YYYY-MM-DD>.")
        }
        guard let baselineFrom = parsed.baselineFrom else {
            throw CLIError("missing required --baseline-from <time>.")
        }
        guard let recentFrom = parsed.recentFrom else {
            throw CLIError("missing required --recent-from <time>.")
        }
        self.date = date
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
        self.baselineFromCreatedAt = try SwarmDatabase.parseQueryTimestamp(baselineFrom, optionName: "--baseline-from")!
        self.baselineToCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.baselineTo, optionName: "--baseline-to")
        self.recentFromCreatedAt = try SwarmDatabase.parseQueryTimestamp(recentFrom, optionName: "--recent-from")!
        self.recentToCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.recentTo, optionName: "--recent-to")
        self.asOfCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.asOf, optionName: "--as-of")
        self.minBaselineVisits = parsed.minBaselineVisits
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(
            fromCreatedAt: nil,
            toCreatedAt: nil,
            date: date,
            hourFrom: hourFrom,
            hourTo: hourTo,
            limit: limit
        )
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
        try SwarmDatabase.validatePlaceOptions(locality: locality, region: region, postalCode: postalCode, countryCode: countryCode)
        try SwarmDatabase.validateCategoryOptions(categoryNames)
        if nearPlace == nil {
            try SwarmDatabase.validateGeoOptions(nearLatitude: nearLatitude, nearLongitude: nearLongitude, radiusMeters: radiusMeters)
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
