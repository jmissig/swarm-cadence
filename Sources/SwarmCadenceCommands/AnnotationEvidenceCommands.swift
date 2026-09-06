import ArgumentParser
import Foundation
import SwarmCadenceCore

struct AnnotationsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "annotations",
        abstract: "Attach/list annotations.",
        subcommands: [AnnotationsAddCommand.self, AnnotationsListCommand.self, AnnotationsKindsCommand.self, AnnotationsTargetsCommand.self]
    )
}

struct AnnotationsAddCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Attach an annotation to a target."
    )

    @OptionGroup var arguments: AnnotationsAddArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try AnnotationsAddOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.addAnnotation(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            targetKind: options.targetKind,
            targetID: options.targetID,
            body: options.body,
            source: options.source
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct AnnotationsListCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List annotations."
    )

    @OptionGroup var arguments: AnnotationsListArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try AnnotationsListOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.listAnnotations(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            targetKind: options.targetKind,
            targetID: options.targetID,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}


struct AnnotationsKindsCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kinds",
        abstract: "List supported annotation target kinds."
    )

    @Option var format = "auto"
    @Flag var json = false

    mutating func execute(_ runtime: CommandRuntime) throws {
        let format = try parseFormat(format: format, json: json)
        let result = SwarmDatabase.listAnnotationKinds()
        runtime.output(try Formatter.render(result, format: format))
    }
}

struct AnnotationsTargetsCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "targets",
        abstract: "List annotation target IDs currently used in the DB."
    )

    @OptionGroup var arguments: AnnotationsTargetsArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try AnnotationsTargetsOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.listAnnotationTargets(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            kind: options.kind,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct EvidenceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evidence",
        abstract: "Build bounded evidence bundles for Robut.",
        subcommands: [EvidenceWindowCommand.self, EvidencePacketCommand.self]
    )
}

struct EvidenceWindowCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "Describe one date/hour evidence window."
    )

    @OptionGroup var arguments: EvidenceWindowArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try EvidenceWindowOptions(parsed: arguments, runtime: runtime)
        let result = try SwarmDatabase.evidenceWindow(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
            date: options.date,
            hourFrom: options.hourFrom,
            hourTo: options.hourTo,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct EvidencePacketCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "packet",
        abstract: "Compose one bounded local evidence packet."
    )

    @OptionGroup var arguments: EvidencePacketArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try EvidencePacketOptions(parsed: arguments, runtime: runtime)
        let geography = try options.resolveGeography(environment: runtime.environment)
        let result = try SwarmDatabase.evidencePacket(
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            account: options.account,
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
            baselineFromCreatedAt: options.baselineFromCreatedAt,
            baselineToCreatedAt: options.baselineToCreatedAt,
            recentFromCreatedAt: options.recentFromCreatedAt,
            recentToCreatedAt: options.recentToCreatedAt,
            asOfCreatedAt: options.asOfCreatedAt,
            minBaselineVisits: options.minBaselineVisits,
            limit: options.limit
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}
