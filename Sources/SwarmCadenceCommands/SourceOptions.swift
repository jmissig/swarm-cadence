import ArgumentParser
import Foundation
import SwarmCadenceCore

struct SetupOptions {
    let account: String?
    let configPath: String?
    let format: OutputFormat
    let nonInteractive: Bool
    let inputs: SetupAuthInputs

    init(parsed: SetupArguments, runtime: CommandRuntime) throws {
        self.account = parsed.account
        self.configPath = parsed.config
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.nonInteractive = parsed.nonInteractive
        self.inputs = SetupAuthInputs(
            accessToken: parsed.accessToken,
            clientID: parsed.clientID,
            clientSecret: parsed.clientSecret,
            redirectURI: parsed.redirectURI,
            authorizationCode: parsed.authorizationCode
        )
    }

    func allowsPrompts(isInputTTY: Bool) -> Bool {
        format != .json && !nonInteractive && isInputTTY
    }
}

struct SourceStatusOptions {
    let account: String?
    let format: OutputFormat
    let configPath: String?

    init(parsed: SourceStatusArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccountIfPresent(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.configPath = parsed.config
    }
}

struct SourceProbeOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let live: Bool

    init(parsed: SourceProbeArguments, runtime: CommandRuntime) throws {
        var format = try OutputFormat(rawValue: parsed.format)
            .orThrow("unsupported --format. Use `auto`, `text`, or `json`.")

        if parsed.json {
            guard format == .text else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.adapter = try SourceAdapter(rawValue: parsed.adapter)
            .orThrow("unsupported --adapter. Use `v2` or `historysearch`.")
        self.format = format
        self.configPath = parsed.config
        self.live = parsed.live
    }
}

struct RawFetchOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let outputDirectory: String?
    let limit: Int
    let offset: Int

    init(parsed: RawFetchArguments, runtime: CommandRuntime) throws {
        var format = try OutputFormat(rawValue: parsed.format)
            .orThrow("unsupported --format. Use `auto`, `text`, or `json`.")

        if parsed.json {
            guard format == .text else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.adapter = try SourceAdapter(rawValue: parsed.adapter)
            .orThrow("unsupported --adapter. Use `v2`.")
        guard self.adapter == .v2 else {
            throw CLIError("raw fetch is currently implemented only for --adapter v2.")
        }
        self.format = format
        self.configPath = parsed.config
        if let outputDirectory = parsed.outputDirectory, outputDirectory.isEmpty {
            throw CLIError("--out must not be empty.")
        }
        self.outputDirectory = parsed.outputDirectory

        self.limit = parsed.limit
        guard self.limit >= 1 else {
            throw CLIError("--limit must be at least 1.")
        }
        guard self.limit <= RawFetch.hardLimit else {
            throw CLIError("--limit \(self.limit) exceeds the hard max of \(RawFetch.hardLimit) per invocation.")
        }

        self.offset = parsed.offset
        guard self.offset >= 0 else {
            throw CLIError("--offset must be at least 0.")
        }
    }
}

struct RawFetchPagesOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let outputDirectory: String?
    let limit: Int
    let startOffset: Int
    let pages: Int
    let delayMilliseconds: Int

    init(parsed: RawFetchPagesArguments, runtime: CommandRuntime) throws {
        var format = try OutputFormat(rawValue: parsed.format)
            .orThrow("unsupported --format. Use `auto`, `text`, or `json`.")

        if parsed.json {
            guard format == .text else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.adapter = try SourceAdapter(rawValue: parsed.adapter)
            .orThrow("unsupported --adapter. Use `v2`.")
        guard self.adapter == .v2 else {
            throw CLIError("raw fetch-pages is currently implemented only for --adapter v2.")
        }
        self.format = format
        self.configPath = parsed.config
        if let outputDirectory = parsed.outputDirectory, outputDirectory.isEmpty {
            throw CLIError("--out must not be empty.")
        }
        self.outputDirectory = parsed.outputDirectory
        self.limit = parsed.limit
        guard self.limit >= 1 else { throw CLIError("--limit must be at least 1.") }
        guard self.limit <= RawFetch.hardLimit else {
            throw CLIError("--limit \(self.limit) exceeds the hard max of \(RawFetch.hardLimit) per invocation.")
        }
        self.startOffset = parsed.startOffset
        guard self.startOffset >= 0 else { throw CLIError("--start-offset must be at least 0.") }
        self.pages = parsed.pages
        guard (1...RawFetch.fetchPagesHardMaxPages).contains(self.pages) else {
            throw CLIError("--pages \(self.pages) exceeds the hard max of \(RawFetch.fetchPagesHardMaxPages) per invocation.")
        }
        self.delayMilliseconds = parsed.delayMilliseconds
        guard self.delayMilliseconds >= 0 else { throw CLIError("--delay-ms must be at least 0.") }
    }
}

struct IngestUpdateOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let rawDirectory: String?
    let dbPath: String?
    let pages: Int
    let limit: Int
    let delayMilliseconds: Int

    init(parsed: IngestUpdateArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: parsed.config, environment: runtime.environment)
        self.adapter = try SourceAdapter(rawValue: parsed.adapter)
            .orThrow("unsupported --adapter. Use `v2`.")
        guard self.adapter == .v2 else {
            throw CLIError("ingest is currently implemented only for --adapter v2.")
        }
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.configPath = parsed.config
        if let rawDirectory = parsed.rawDirectory, rawDirectory.isEmpty {
            throw CLIError("--raw-dir must not be empty.")
        }
        if let dbPath = parsed.dbPath, dbPath.isEmpty {
            throw CLIError("--db must not be empty.")
        }
        self.rawDirectory = parsed.rawDirectory
        self.dbPath = parsed.dbPath
        self.pages = parsed.pages
        guard self.pages >= 1 else { throw CLIError("--pages must be at least 1.") }
        guard self.pages <= RawFetch.fetchPagesHardMaxPages else {
            throw CLIError("--pages \(self.pages) exceeds the hard max of \(RawFetch.fetchPagesHardMaxPages) per invocation.")
        }
        self.limit = parsed.limit
        guard self.limit >= 1 else { throw CLIError("--limit must be at least 1.") }
        guard self.limit <= RawFetch.hardLimit else {
            throw CLIError("--limit \(self.limit) exceeds the hard max of \(RawFetch.hardLimit) per invocation.")
        }
        self.delayMilliseconds = parsed.delayMilliseconds
        guard self.delayMilliseconds >= 0 else { throw CLIError("--delay-ms must be at least 0.") }
    }
}

struct DBImportRawOptions {
    let account: String
    let dbPath: String?
    let rawDirectory: String?
    let format: OutputFormat

    init(parsed: DBImportRawArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.rawDirectory = parsed.rawDirectory
    }
}

struct DBImportFilesOptions {
    let account: String
    let dbPath: String?
    let path: String
    let source: FileImportSource
    let format: OutputFormat

    init(parsed: DBImportFilesArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        guard let path = parsed.path, !path.isEmpty else {
            throw CLIError("missing required --path <dir>.")
        }
        self.path = path
        self.source = try FileImportSource(rawValue: parsed.source)
            .orThrow("unsupported --source. Use `foursquare-export`.")
    }
}


struct DBMigrateOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat

    init(parsed: DBMigrateArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        if let dbPath = parsed.dbPath, dbPath.isEmpty {
            throw CLIError("--db must not be empty.")
        }
        self.dbPath = parsed.dbPath
    }
}

struct DBStatsOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat

    init(parsed: DBStatsArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
    }
}


struct AuditOverlapOptions {
    let account: String
    let v2RawDirectory: String?
    let exportPath: String
    let exampleLimit: Int
    let format: OutputFormat

    init(parsed: AuditOverlapArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        if let rawDirectory = parsed.rawDirectory, rawDirectory.isEmpty {
            throw CLIError("--raw-dir must not be empty.")
        }
        self.v2RawDirectory = parsed.rawDirectory
        guard let path = parsed.path, !path.isEmpty else {
            throw CLIError("missing required --path <foursquare-export-dir>.")
        }
        self.exportPath = path
        guard parsed.examples >= 0 else {
            throw CLIError("--examples must be at least 0.")
        }
        self.exampleLimit = parsed.examples
    }
}

struct AuditIdentityOptions {
    let account: String
    let dbPath: String?
    let sameNameNearbyMeters: Double
    let limit: Int
    let format: OutputFormat

    init(parsed: AuditIdentityArguments, runtime: CommandRuntime) throws {
        self.account = try resolveConfiguredAccount(parsed.account, configPath: nil, environment: runtime.environment)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        if let dbPath = parsed.dbPath, dbPath.isEmpty {
            throw CLIError("--db must not be empty.")
        }
        self.dbPath = parsed.dbPath
        self.sameNameNearbyMeters = parsed.sameNameNearbyMeters
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
        guard sameNameNearbyMeters >= 0 else { throw CLIError("--same-name-nearby-meters must be at least 0.") }
    }
}
