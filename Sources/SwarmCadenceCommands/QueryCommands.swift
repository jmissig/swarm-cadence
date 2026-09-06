import ArgumentParser
import Foundation
import SwarmCadenceCore

struct QueryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Read evidence rows and descriptive rollups.",
        subcommands: [QueryCategoriesCommand.self, QueryVenuesCommand.self, QueryVisitsCommand.self, QueryCadenceCommand.self, QueryCompareCommand.self, QueryLapsesCommand.self]
    )
}

struct QueryCategoriesCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "categories",
        abstract: "List category coverage."
    )

    @OptionGroup var arguments: QueryCategoriesArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try QueryCategoriesOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.queryCategories(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            limit: options.limit,
            includeAnnotations: options.includeAnnotations
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct QueryVenuesCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "venues",
        abstract: "List/filter venues."
    )

    @OptionGroup var arguments: QueryVenuesArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try QueryVenuesOptions(parsed: arguments, runtime: runtime)
        let geography = try options.resolveGeography(environment: runtime.environment)
        let result = try SwarmDatabase.queryVenues(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            fromCreatedAt: options.fromCreatedAt,
            toCreatedAt: options.toCreatedAt,
            date: options.date,
            hourFrom: options.hourFrom,
            hourTo: options.hourTo,
            locality: geography.locality,
            region: geography.region,
            postalCode: geography.postalCode,
            countryCode: geography.countryCode,
            areaLocalities: geography.areaLocalities,
            categoryNames: options.categoryNames,
            nearLatitude: geography.nearLatitude,
            nearLongitude: geography.nearLongitude,
            radiusMeters: geography.radiusMeters,
            geography: geography.geography,
            sort: options.sort,
            limit: options.limit,
            includeAnnotations: options.includeAnnotations
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct QueryVisitsCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "visits",
        abstract: "List/filter visits."
    )

    @OptionGroup var arguments: QueryVisitsArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try QueryVisitsOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.queryVisits(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            venueID: options.venueID,
            fromCreatedAt: options.fromCreatedAt,
            toCreatedAt: options.toCreatedAt,
            date: options.date,
            hourFrom: options.hourFrom,
            hourTo: options.hourTo,
            categoryNames: options.categoryNames,
            limit: options.limit,
            includeAnnotations: options.includeAnnotations
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct QueryCadenceCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cadence",
        abstract: "Roll up factual venue time/cadence evidence."
    )

    @OptionGroup var arguments: QueryCadenceArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try QueryCadenceOptions(parsed: arguments, runtime: runtime)
        let geography = try options.resolveGeography(environment: runtime.environment)
        let result = try SwarmDatabase.queryCadence(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            venueID: options.venueID,
            fromCreatedAt: options.fromCreatedAt,
            toCreatedAt: options.toCreatedAt,
            hourFrom: options.hourFrom,
            hourTo: options.hourTo,
            locality: geography.locality,
            region: geography.region,
            postalCode: geography.postalCode,
            countryCode: geography.countryCode,
            areaLocalities: geography.areaLocalities,
            categoryNames: options.categoryNames,
            nearLatitude: geography.nearLatitude,
            nearLongitude: geography.nearLongitude,
            radiusMeters: geography.radiusMeters,
            geography: geography.geography,
            sort: options.sort,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct QueryCompareCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare baseline and recent venue evidence."
    )

    @OptionGroup var arguments: QueryCompareArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try QueryCompareOptions(parsed: arguments, runtime: runtime)
        let geography = try options.resolveGeography(environment: runtime.environment)
        let result = try SwarmDatabase.queryCompare(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            baselineFromCreatedAt: options.baselineFromCreatedAt,
            baselineToCreatedAt: options.baselineToCreatedAt,
            recentFromCreatedAt: options.recentFromCreatedAt,
            recentToCreatedAt: options.recentToCreatedAt,
            asOfCreatedAt: options.asOfCreatedAt,
            hourFrom: options.hourFrom,
            hourTo: options.hourTo,
            locality: geography.locality,
            region: geography.region,
            postalCode: geography.postalCode,
            countryCode: geography.countryCode,
            areaLocalities: geography.areaLocalities,
            categoryNames: options.categoryNames,
            nearLatitude: geography.nearLatitude,
            nearLongitude: geography.nearLongitude,
            radiusMeters: geography.radiusMeters,
            geography: geography.geography,
            sort: options.sort,
            minBaselineVisits: options.minBaselineVisits,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct QueryLapsesCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lapses",
        abstract: "Expose active/lapsed venue evidence from explicit comparison windows."
    )

    @OptionGroup var arguments: QueryCompareArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try QueryCompareOptions(parsed: arguments, runtime: runtime)
        let geography = try options.resolveGeography(environment: runtime.environment)
        let result = try SwarmDatabase.queryCompare(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            baselineFromCreatedAt: options.baselineFromCreatedAt,
            baselineToCreatedAt: options.baselineToCreatedAt,
            recentFromCreatedAt: options.recentFromCreatedAt,
            recentToCreatedAt: options.recentToCreatedAt,
            asOfCreatedAt: options.asOfCreatedAt,
            hourFrom: options.hourFrom,
            hourTo: options.hourTo,
            locality: geography.locality,
            region: geography.region,
            postalCode: geography.postalCode,
            countryCode: geography.countryCode,
            areaLocalities: geography.areaLocalities,
            categoryNames: options.categoryNames,
            nearLatitude: geography.nearLatitude,
            nearLongitude: geography.nearLongitude,
            radiusMeters: geography.radiusMeters,
            geography: geography.geography,
            sort: options.sort,
            minBaselineVisits: options.minBaselineVisits,
            limit: options.limit,
            commandName: "query lapses"
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}
