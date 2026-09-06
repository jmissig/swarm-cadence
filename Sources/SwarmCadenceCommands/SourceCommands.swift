import ArgumentParser
import Foundation
import SwarmCadenceCore

struct SetupCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Alias for `auth login`."
    )

    @OptionGroup var arguments: SetupArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try SetupOptions(parsed: arguments, runtime: runtime)
        let result = try SetupAuth.setup(
            action: "login",
            account: options.account,
            configPath: options.configPath,
            allowsPrompts: options.allowsPrompts(isInputTTY: runtime.isInputTTY),
            inputs: options.inputs,
            environment: runtime.environment,
            transport: runtime.liveTransport,
            input: runtime.input,
            promptOutput: runtime.output
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct AuthCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage saved Foursquare/Swarm auth.",
        subcommands: [AuthStatusCommand.self, AuthLoginCommand.self, AuthClearCommand.self]
    )
}

struct AuthStatusCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show configured account/auth readiness."
    )

    @Option(help: "Account label to inspect, such as default or partner.") var account: String?
    @Option(help: "Config JSON path. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(help: "Output format: auto, text, or json.") var format = "auto"
    @Flag(help: "Shortcut for --format json.") var json = false

    mutating func execute(_ runtime: CommandRuntime) throws {
        let account = try resolveConfiguredAccount(account, configPath: config, environment: runtime.environment)
        let result = try SetupAuth.status(
            account: account,
            configPath: config,
            environment: runtime.environment
        )
        runtime.output(try Formatter.render(result, format: try parseFormat(format: format, json: json)))
    }
}

struct AuthLoginCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Configure v2 token/OAuth credentials."
    )

    @OptionGroup var arguments: SetupArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try SetupOptions(parsed: arguments, runtime: runtime)
        let result = try SetupAuth.setup(
            action: "login",
            account: options.account,
            configPath: options.configPath,
            allowsPrompts: options.allowsPrompts(isInputTTY: runtime.isInputTTY),
            inputs: options.inputs,
            environment: runtime.environment,
            transport: runtime.liveTransport,
            input: runtime.input,
            promptOutput: runtime.output
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct AuthClearCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Remove saved account auth."
    )

    @Option(help: "Account label to clear, such as default or partner.") var account: String?
    @Option(help: "Config JSON path. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(help: "Output format: auto, text, or json.") var format = "auto"
    @Flag(help: "Required to remove stored credentials.") var force = false
    @Flag(help: "Shortcut for --format json.") var json = false

    mutating func execute(_ runtime: CommandRuntime) throws {
        let outputFormat = try parseFormat(format: format, json: json)
        let account = try resolveConfiguredAccount(account, configPath: config, environment: runtime.environment)
        let result = try SetupAuth.clear(
            account: account,
            configPath: config,
            environment: runtime.environment,
            force: force
        )
        runtime.output(try Formatter.render(result, format: outputFormat))
    }
}

struct SourceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "source",
        abstract: "Inspect source/account readiness.",
        subcommands: [SourceStatusCommand.self, SourceProbeCommand.self]
    )
}

struct SourceStatusCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "List configured accounts and local evidence paths."
    )

    @OptionGroup var arguments: SourceStatusArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try SourceStatusOptions(parsed: arguments, runtime: runtime)
        let result = try SourceStatus.status(
            account: options.account,
            configPath: options.configPath,
            environment: runtime.environment
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct SourceProbeCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Validate v2/historysearch source configuration."
    )

    @OptionGroup var arguments: SourceProbeArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try SourceProbeOptions(parsed: arguments, runtime: runtime)
        let inputs = try ConfigFile.resolve(account: options.account, path: options.configPath, environment: runtime.environment)
        let result = options.live
            ? SourceProbe.liveProbe(
                account: options.account,
                adapter: options.adapter,
                environment: inputs.environment,
                config: inputs.config,
                transport: runtime.liveTransport
            )
            : SourceProbe.probe(
                account: options.account,
                adapter: options.adapter,
                environment: inputs.environment,
                config: inputs.config
            )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct RawCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "raw",
        abstract: "Collect preserved source payloads.",
        subcommands: [RawFetchCommand.self, RawFetchPagesCommand.self]
    )
}

struct RawFetchCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "Fetch one conservative v2 checkins page."
    )

    @OptionGroup var arguments: RawFetchArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try RawFetchOptions(parsed: arguments, runtime: runtime)
        let inputs = try ConfigFile.resolve(account: options.account, path: options.configPath, environment: runtime.environment)
        let result = try RawFetch.fetch(
            account: options.account,
            adapter: options.adapter,
            config: inputs.config,
            environment: inputs.environment,
            outputDirectory: options.outputDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: runtime.environment),
            limit: options.limit,
            offset: options.offset,
            transport: runtime.liveTransport
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct RawFetchPagesCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch-pages",
        abstract: "Fetch bounded recent v2 pages."
    )

    @OptionGroup var arguments: RawFetchPagesArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        let options = try RawFetchPagesOptions(parsed: arguments, runtime: runtime)
        let inputs = try ConfigFile.resolve(account: options.account, path: options.configPath, environment: runtime.environment)
        let result = try RawFetch.fetchPages(
            account: options.account,
            adapter: options.adapter,
            config: inputs.config,
            environment: inputs.environment,
            outputDirectory: options.outputDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: runtime.environment),
            limit: options.limit,
            startOffset: options.startOffset,
            pages: options.pages,
            delayMilliseconds: options.delayMilliseconds,
            transport: runtime.liveTransport
        )
        runtime.output(try Formatter.render(result, format: options.format))
    }
}

struct IngestCommand: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Fetch bounded v2 raw pages and import successful pages.",
        usage: "swarm-cadence ingest --account <label> [--adapter v2] [--pages <pages>] [--limit <limit>]",
        discussion: """
        Normal operator path:
          swarm-cadence ingest --account <label> --adapter v2
        """
    )

    @OptionGroup var arguments: IngestUpdateArguments

    mutating func execute(_ runtime: CommandRuntime) throws {
        if runtime.arguments == ["ingest"] {
            throw CleanExit.helpRequest(Self.self)
        }
        try Self.runUpdate(arguments, runtime: runtime)
    }

    static func runUpdate(_ arguments: IngestUpdateArguments, runtime: CommandRuntime) throws {
        let options = try IngestUpdateOptions(parsed: arguments, runtime: runtime)
        let inputs = try ConfigFile.resolve(account: options.account, path: options.configPath, environment: runtime.environment)
        let result = try IngestUpdate.update(
            account: options.account,
            adapter: options.adapter,
            config: inputs.config,
            environment: inputs.environment,
            rawDirectory: options.rawDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: runtime.environment),
            dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: runtime.environment),
            pages: options.pages,
            limit: options.limit,
            delayMilliseconds: options.delayMilliseconds,
            command: "ingest",
            transport: runtime.liveTransport,
            now: runtime.now
        )
        runtime.output(try Formatter.render(result, format: options.format))
        runtime.exitCode = result.exitCode
    }
}
