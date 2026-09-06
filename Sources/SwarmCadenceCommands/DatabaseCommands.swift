import ArgumentParser
import Foundation
import SwarmCadenceCore

struct DBCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "db",
        abstract: "Import/check local SQLite evidence.",
        subcommands: [DBImportRawCommand.self, DBImportFilesCommand.self, DBStatsCommand.self, DBMigrateCommand.self]
    )
}

struct DBImportRawCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-raw",
        abstract: "Import preserved raw v2 files from disk."
    )

    @OptionGroup var arguments: DBImportRawArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try DBImportRawOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.importRawV2Checkins(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            rawDirectory: options.rawDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: runtime.environment),
            account: options.account
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct DBImportFilesCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-files",
        abstract: "Import official Foursquare export files."
    )

    @OptionGroup var arguments: DBImportFilesArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try DBImportFilesOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.importFiles(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            path: options.path,
            account: options.account,
            source: options.source
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}


struct DBMigrateCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Migrate local SQLite evidence DB.",
        shouldDisplay: false
    )

    @OptionGroup var arguments: DBMigrateArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try DBMigrateOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.migrateDatabase(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct DBStatsCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Summarize database coverage."
    )

    @OptionGroup var arguments: DBStatsArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try DBStatsOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.stats(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct AuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Audit source and identity evidence.",
        subcommands: [AuditOverlapCommand.self, AuditIdentityCommand.self]
    )
}

struct AuditOverlapCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overlap",
        abstract: "Compare v2 raw files with official export by check-in id."
    )

    @OptionGroup var arguments: AuditOverlapArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try AuditOverlapOptions(parsed: arguments, runtime: runtime)
        let result = try SourceAudit.overlap(
            account: options.account,
            v2RawDirectory: options.v2RawDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: runtime.environment),
            exportPath: options.exportPath,
            exampleLimit: options.exampleLimit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct AuditIdentityCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "identity",
        abstract: "Audit venue identity candidates in the SQLite evidence store."
    )

    @OptionGroup var arguments: AuditIdentityArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try AuditIdentityOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.auditVenueIdentity(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            sameNameNearbyMeters: options.sameNameNearbyMeters,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}
