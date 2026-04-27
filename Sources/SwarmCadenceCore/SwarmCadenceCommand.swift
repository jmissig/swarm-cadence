import ArgumentParser
import Foundation

public enum SwarmCadenceCommand {
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        liveTransport: ProbeHTTPTransport = URLSessionProbeHTTPTransport(),
        input: @escaping () -> String? = { readLine(strippingNewline: true) },
        output: (String) -> Void = { print($0) },
        errorOutput: (String) -> Void = { fputs($0 + "\n", stderr) }
    ) -> Int {
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments: arguments)
        } catch let exit as ArgumentParserExit {
            if exit.isSuccess {
                output(exit.message)
            } else {
                errorOutput(exit.message)
            }
            return exit.code
        } catch let error as CLIError {
            errorOutput(error.message)
            return 2
        } catch {
            errorOutput("error: \(argumentParserMessage(error))")
            return 2
        }

        do {
            switch invocation {
            case .help:
                output(Self.helpText)
                return 0
            case .version:
                output(SwarmCadenceVersion.current)
                return 0
            case let .setup(options):
                let result = try SetupAuth.setup(
                    action: AuthAction.login.rawValue,
                    account: options.account,
                    configPath: options.configPath,
                    format: options.format,
                    inputs: options.inputs,
                    environment: environment,
                    transport: liveTransport,
                    input: input,
                    promptOutput: output
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .auth(options):
                let result: SetupAuthResult
                switch options.action {
                case .status:
                    result = try SetupAuth.status(
                        account: options.account,
                        configPath: options.configPath,
                        environment: environment
                    )
                case .login:
                    result = try SetupAuth.setup(
                        action: options.action.rawValue,
                        account: options.account,
                        configPath: options.configPath,
                        format: options.format,
                        inputs: options.inputs,
                        environment: environment,
                        transport: liveTransport,
                        input: input,
                        promptOutput: output
                    )
                case .clear:
                    result = try SetupAuth.clear(
                        account: options.account,
                        configPath: options.configPath,
                        environment: environment,
                        force: options.force
                    )
                }
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .sourceProbe(options):
                let config = try ConfigFile.loadOptional(path: options.configPath, environment: environment)
                let result = options.live
                    ? SourceProbe.liveProbe(
                        account: options.account,
                        adapter: options.adapter,
                        environment: environment,
                        config: config,
                        transport: liveTransport
                    )
                    : SourceProbe.probe(
                        account: options.account,
                        adapter: options.adapter,
                        environment: environment,
                        config: config
                    )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .rawFetch(options):
                let config = try ConfigFile.loadOptional(path: options.configPath, environment: environment)
                let result = try RawFetch.fetch(
                    account: options.account,
                    adapter: options.adapter,
                    config: config,
                    environment: environment,
                    outputDirectory: options.outputDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: environment),
                    limit: options.limit,
                    offset: options.offset,
                    transport: liveTransport
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .rawFetchPages(options):
                let config = try ConfigFile.loadOptional(path: options.configPath, environment: environment)
                let result = try RawFetch.fetchPages(
                    account: options.account,
                    adapter: options.adapter,
                    config: config,
                    environment: environment,
                    outputDirectory: options.outputDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: environment),
                    limit: options.limit,
                    startOffset: options.startOffset,
                    pages: options.pages,
                    delayMilliseconds: options.delayMilliseconds,
                    transport: liveTransport
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .ingestUpdate(options):
                let config = try ConfigFile.loadOptional(path: options.configPath, environment: environment)
                let result = try IngestUpdate.update(
                    account: options.account,
                    adapter: options.adapter,
                    config: config,
                    environment: environment,
                    rawDirectory: options.rawDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: environment),
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    pages: options.pages,
                    limit: options.limit,
                    delayMilliseconds: options.delayMilliseconds,
                    transport: liveTransport
                )
                output(try Formatter.render(result, format: options.format))
                return result.exitCode
            case let .dbImportRaw(options):
                let result = try SwarmDatabase.importRawV2Checkins(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    rawDirectory: options.rawDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: environment),
                    account: options.account
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .dbImportFiles(options):
                let result = try SwarmDatabase.importFiles(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    path: options.path,
                    account: options.account,
                    source: options.source
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .dbStats(options):
                let result = try SwarmDatabase.stats(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .auditOverlap(options):
                let result = try SourceAudit.overlap(
                    account: options.account,
                    v2RawDirectory: options.v2RawDirectory ?? AppSupportDefaults.rawCheckinsDirectory(account: options.account, environment: environment),
                    exportPath: options.exportPath,
                    exampleLimit: options.exampleLimit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .queryCategories(options):
                let result = try SwarmDatabase.queryCategories(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account,
                    limit: options.limit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .queryVenues(options):
                let result = try SwarmDatabase.queryVenues(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account,
                    fromCreatedAt: options.fromCreatedAt,
                    toCreatedAt: options.toCreatedAt,
                    date: options.date,
                    hourFrom: options.hourFrom,
                    hourTo: options.hourTo,
                    locality: options.locality,
                    region: options.region,
                    postalCode: options.postalCode,
                    countryCode: options.countryCode,
                    categoryNames: options.categoryNames,
                    nearLatitude: options.nearLatitude,
                    nearLongitude: options.nearLongitude,
                    radiusMeters: options.radiusMeters,
                    sort: options.sort,
                    limit: options.limit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .queryVisits(options):
                let result = try SwarmDatabase.queryVisits(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account,
                    venueID: options.venueID,
                    fromCreatedAt: options.fromCreatedAt,
                    toCreatedAt: options.toCreatedAt,
                    date: options.date,
                    hourFrom: options.hourFrom,
                    hourTo: options.hourTo,
                    limit: options.limit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .queryCompare(options):
                let result = try SwarmDatabase.queryCompare(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account,
                    baselineFromCreatedAt: options.baselineFromCreatedAt,
                    baselineToCreatedAt: options.baselineToCreatedAt,
                    recentFromCreatedAt: options.recentFromCreatedAt,
                    recentToCreatedAt: options.recentToCreatedAt,
                    asOfCreatedAt: options.asOfCreatedAt,
                    hourFrom: options.hourFrom,
                    hourTo: options.hourTo,
                    locality: options.locality,
                    region: options.region,
                    postalCode: options.postalCode,
                    countryCode: options.countryCode,
                    categoryNames: options.categoryNames,
                    nearLatitude: options.nearLatitude,
                    nearLongitude: options.nearLongitude,
                    radiusMeters: options.radiusMeters,
                    sort: options.sort,
                    minBaselineVisits: options.minBaselineVisits,
                    limit: options.limit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .evidenceWindow(options):
                let result = try SwarmDatabase.evidenceWindow(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account,
                    date: options.date,
                    hourFrom: options.hourFrom,
                    hourTo: options.hourTo,
                    limit: options.limit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .evidencePacket(options):
                let result = try SwarmDatabase.evidencePacket(
                    dbPath: options.dbPath ?? AppSupportDefaults.sqlitePath(account: options.account, environment: environment),
                    account: options.account,
                    date: options.date,
                    hourFrom: options.hourFrom,
                    hourTo: options.hourTo,
                    locality: options.locality,
                    region: options.region,
                    postalCode: options.postalCode,
                    countryCode: options.countryCode,
                    categoryNames: options.categoryNames,
                    nearLatitude: options.nearLatitude,
                    nearLongitude: options.nearLongitude,
                    radiusMeters: options.radiusMeters,
                    baselineFromCreatedAt: options.baselineFromCreatedAt,
                    baselineToCreatedAt: options.baselineToCreatedAt,
                    recentFromCreatedAt: options.recentFromCreatedAt,
                    recentToCreatedAt: options.recentToCreatedAt,
                    asOfCreatedAt: options.asOfCreatedAt,
                    minBaselineVisits: options.minBaselineVisits,
                    limit: options.limit
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            }
        } catch let error as CLIError {
            errorOutput(error.message)
            return 2
        } catch {
            errorOutput("error: \(error.localizedDescription)")
            return 1
        }
    }

    private static func argumentParserMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.hasPrefix("Error: ") {
            return String(message.dropFirst("Error: ".count))
        }
        return message
    }

    public static let helpText = """
    swarm-cadence \(SwarmCadenceVersion.current)

    Usage:
      swarm-cadence --version
      swarm-cadence auth status --account <label> [--config <path>] [--format <human|json>]
      swarm-cadence auth login [--account <label>] [--config <path>] [--format <human|json>] [--access-token <token>]
      swarm-cadence auth clear --account <label> [--config <path>] --force [--format <human|json>]
      swarm-cadence setup [--account <label>] [--config <path>] [--format <human|json>] [--access-token <token>]  # alias for auth login
      swarm-cadence source probe --account <label> --adapter <v2|historysearch> [--format <human|json>] [--config <path>] [--live]
      swarm-cadence raw fetch --account <label> --adapter v2 [--out <dir>] [--limit <1...250>] [--offset <n>] [--format <human|json>] [--config <path>]
      swarm-cadence raw fetch-pages --account <label> --adapter v2 [--out <dir>] [--limit <1...250>] [--start-offset <n>] --pages <1...200> [--delay-ms <n>] [--format <human|json>] [--config <path>]
      swarm-cadence ingest update --account <label> --adapter v2 [--pages <n>] [--limit <1...250>] [--delay-ms <n>] [--config <path>] [--raw-dir <dir>] [--db <path>] [--format <human|json>]
      swarm-cadence db import-raw --account <label> [--db <path>] [--raw-dir <dir>] [--format <human|json>]
      swarm-cadence db import-files --account <label> --path <dir> [--source foursquare-export] [--db <path>] [--format <human|json>]
      swarm-cadence db stats --account <label> [--db <path>] [--format <human|json>]
      swarm-cadence audit overlap --account <label> --path <foursquare-export-dir> [--raw-dir <v2-raw-dir>] [--examples <n>] [--format <human|json>]
      swarm-cadence query categories --account <label> [--db <path>] [--limit <1...250>] [--format <human|json>]
      swarm-cadence query venues --account <label> [--db <path>] [--date <YYYY-MM-DD>] [--hour-from <0...23>] [--hour-to <0...23>] [--from <time>] [--to <time>] [--locality <name>] [--region <code>] [--postal-code <code>] [--country-code <code>] [--category <name>] [--near-lat <lat> --near-lng <lng> --radius-meters <m>] [--sort <nearest|strongest|recent|stale>] [--limit <1...250>] [--format <human|json>]
      swarm-cadence query visits --account <label> [--db <path>] [--venue-id <id>] [--date <YYYY-MM-DD>] [--hour-from <0...23>] [--hour-to <0...23>] [--from <time>] [--to <time>] [--limit <1...250>] [--format <human|json>]
      swarm-cadence query compare --account <label> --baseline-from <time> --recent-from <time> [--db <path>] [--baseline-to <time>] [--recent-to <time>] [--as-of <time>] [--hour-from <0...23>] [--hour-to <0...23>] [--locality <name>] [--region <code>] [--postal-code <code>] [--country-code <code>] [--category <name>] [--near-lat <lat> --near-lng <lng> --radius-meters <m>] [--sort <nearest|strongest|recent|stale>] [--min-baseline-visits <n>] [--limit <1...250>] [--format <human|json>]
      swarm-cadence evidence window --account <label> --date <YYYY-MM-DD> [--hour-from <0...23>] [--hour-to <0...23>] [--db <path>] [--limit <1...250>] [--format <human|json>]
      swarm-cadence evidence packet --account <label> --date <YYYY-MM-DD> --baseline-from <time> --recent-from <time> [--db <path>] [--baseline-to <time>] [--recent-to <time>] [--as-of <time>] [--hour-from <0...23>] [--hour-to <0...23>] [--locality <name>] [--region <code>] [--postal-code <code>] [--country-code <code>] [--category <name>] [--near-lat <lat> --near-lng <lng> --radius-meters <m>] [--min-baseline-visits <n>] [--limit <1...250>] [--format <human|json>]

    Defaults live under ~/Library/Application Support/swarm-cadence: config.json plus per-account raw archives and SQLite DBs under accounts/<label>/.
    Auth login guides first-run v2 token/OAuth config without printing tokens or client secrets; when --account is omitted in human mode, it prompts for an account label. `setup` is a compatibility alias for `auth login`.
    Source probe is dry config validation by default. Pass --live to perform the explicit minimal read-only v2 checkins probe.
    Raw fetch performs exactly one conservative v2 checkins request and writes one raw JSON response plus an adjacent manifest.
    Ingest update is cron-friendly v2 collection: fetch bounded recent pages, preserve raw files, import after each successful page, and report factual freshness.
    DB import reads preserved raw v2 files from disk only; it performs no network calls.
    Audit overlap compares preserved v2 raw files and Foursquare export files by check-in id without writing to SQLite.
    """
}

enum Invocation {
    case help
    case version
    case setup(SetupOptions)
    case auth(AuthOptions)
    case sourceProbe(SourceProbeOptions)
    case rawFetch(RawFetchOptions)
    case rawFetchPages(RawFetchPagesOptions)
    case ingestUpdate(IngestUpdateOptions)
    case dbImportRaw(DBImportRawOptions)
    case dbImportFiles(DBImportFilesOptions)
    case dbStats(DBStatsOptions)
    case auditOverlap(AuditOverlapOptions)
    case queryCategories(QueryCategoriesOptions)
    case queryVenues(QueryVenuesOptions)
    case queryVisits(QueryVisitsOptions)
    case queryCompare(QueryCompareOptions)
    case evidenceWindow(EvidenceWindowOptions)
    case evidencePacket(EvidencePacketOptions)

    init(arguments: [String]) throws {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
            self = .help
            return
        }
        if arguments == ["--version"] {
            self = .version
            return
        }

        guard !arguments.isEmpty else {
            throw CLIError("unsupported command. Run `swarm-cadence --help`.")
        }

        if Array(arguments.dropFirst()).contains(where: { $0 == "--help" || $0 == "-h" }) {
            self = .help
            return
        }

        if arguments[0] == "setup" {
            self = .setup(try SetupOptions(parsed: Self.parse(SetupArguments.self, Array(arguments.dropFirst()))))
            return
        }

        guard arguments.count >= 2 else {
            throw CLIError("unsupported command. Run `swarm-cadence --help`.")
        }

        switch (arguments[0], arguments[1]) {
        case ("auth", _):
            self = .auth(try AuthOptions(parsed: Self.parse(AuthArguments.self, Array(arguments.dropFirst()))))
        case ("source", "probe"):
            self = .sourceProbe(try SourceProbeOptions(parsed: Self.parse(SourceProbeArguments.self, Array(arguments.dropFirst(2)))))
        case ("raw", "fetch"):
            self = .rawFetch(try RawFetchOptions(parsed: Self.parse(RawFetchArguments.self, Array(arguments.dropFirst(2)))))
        case ("raw", "fetch-pages"):
            self = .rawFetchPages(try RawFetchPagesOptions(parsed: Self.parse(RawFetchPagesArguments.self, Array(arguments.dropFirst(2)))))
        case ("ingest", "update"):
            self = .ingestUpdate(try IngestUpdateOptions(parsed: Self.parse(IngestUpdateArguments.self, Array(arguments.dropFirst(2)))))
        case ("db", "import-raw"):
            self = .dbImportRaw(try DBImportRawOptions(parsed: Self.parse(DBImportRawArguments.self, Array(arguments.dropFirst(2)))))
        case ("db", "import-files"):
            self = .dbImportFiles(try DBImportFilesOptions(parsed: Self.parse(DBImportFilesArguments.self, Array(arguments.dropFirst(2)))))
        case ("db", "stats"):
            self = .dbStats(try DBStatsOptions(parsed: Self.parse(DBStatsArguments.self, Array(arguments.dropFirst(2)))))
        case ("audit", "overlap"):
            self = .auditOverlap(try AuditOverlapOptions(parsed: Self.parse(AuditOverlapArguments.self, Array(arguments.dropFirst(2)))))
        case ("query", "categories"):
            self = .queryCategories(try QueryCategoriesOptions(parsed: Self.parse(QueryCategoriesArguments.self, Array(arguments.dropFirst(2)))))
        case ("query", "venues"):
            self = .queryVenues(try QueryVenuesOptions(parsed: Self.parse(QueryVenuesArguments.self, Array(arguments.dropFirst(2)))))
        case ("query", "visits"):
            self = .queryVisits(try QueryVisitsOptions(parsed: Self.parse(QueryVisitsArguments.self, Array(arguments.dropFirst(2)))))
        case ("query", "compare"):
            self = .queryCompare(try QueryCompareOptions(parsed: Self.parse(QueryCompareArguments.self, Array(arguments.dropFirst(2)))))
        case ("evidence", "window"):
            self = .evidenceWindow(try EvidenceWindowOptions(parsed: Self.parse(EvidenceWindowArguments.self, Array(arguments.dropFirst(2)))))
        case ("evidence", "packet"):
            self = .evidencePacket(try EvidencePacketOptions(parsed: Self.parse(EvidencePacketArguments.self, Array(arguments.dropFirst(2)))))
        default:
            throw CLIError("unsupported command. Run `swarm-cadence --help`.")
        }
    }

    private static func parse<Arguments: ParsableArguments>(
        _ type: Arguments.Type,
        _ arguments: [String]
    ) throws -> Arguments {
        do {
            return try type.parse(Self.normalizeSignedValues(arguments))
        } catch {
            let exitCode = type.exitCode(for: error)
            if exitCode.rawValue == 0 {
                throw ArgumentParserExit(
                    message: type.fullMessage(for: error),
                    code: Int(exitCode.rawValue),
                    isSuccess: true
                )
            }
            throw CLIError(type.message(for: error))
        }
    }

    private static func normalizeSignedValues(_ arguments: [String]) -> [String] {
        let signedValueOptions: Set<String> = ["--limit", "--offset", "--pages", "--delay-ms", "--from", "--to", "--baseline-from", "--baseline-to", "--recent-from", "--recent-to", "--as-of", "--near-lat", "--near-lng", "--radius-meters"]
        var normalized: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if signedValueOptions.contains(argument),
               index + 1 < arguments.count,
               arguments[index + 1].hasPrefix("-"),
               (Int(arguments[index + 1]) != nil || Double(arguments[index + 1]) != nil) {
                normalized.append("\(argument)=\(arguments[index + 1])")
                index += 2
            } else {
                normalized.append(argument)
                index += 1
            }
        }

        return normalized
    }
}

private struct ArgumentParserExit: Error {
    let message: String
    let code: Int
    let isSuccess: Bool
}

enum AuthAction: String {
    case status
    case login
    case clear
}

struct SetupOptions {
    let account: String?
    let configPath: String?
    let format: OutputFormat
    let inputs: SetupAuthInputs

    fileprivate init(parsed: SetupArguments) throws {
        self.account = parsed.account
        self.configPath = parsed.config
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.inputs = SetupAuthInputs(
            accessToken: parsed.accessToken,
            clientID: parsed.clientID,
            clientSecret: parsed.clientSecret,
            redirectURI: parsed.redirectURI,
            authorizationCode: parsed.authorizationCode
        )
    }
}

struct AuthOptions {
    let action: AuthAction
    let account: String?
    let configPath: String?
    let format: OutputFormat
    let inputs: SetupAuthInputs
    let force: Bool

    fileprivate init(parsed: AuthArguments) throws {
        self.action = try AuthAction(rawValue: parsed.action ?? AuthAction.status.rawValue)
            .orThrow("unsupported auth action. Use `status`, `login`, or `clear`.")
        if self.action == .login {
            self.account = parsed.account
        } else {
            self.account = try AccountLabel.validate(parsed.account)
        }
        self.configPath = parsed.config
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.inputs = SetupAuthInputs(
            accessToken: parsed.accessToken,
            clientID: parsed.clientID,
            clientSecret: parsed.clientSecret,
            redirectURI: parsed.redirectURI,
            authorizationCode: parsed.authorizationCode
        )
        self.force = parsed.force

        if action != .login {
            let setupFlags = [
                parsed.accessToken,
                parsed.clientID,
                parsed.clientSecret,
                parsed.redirectURI,
                parsed.authorizationCode
            ]
            if setupFlags.contains(where: { $0 != nil }) {
                throw CLIError("auth \(action.rawValue) does not accept setup credential options.")
            }
        }
        if action != .clear, force {
            throw CLIError("auth \(action.rawValue) does not accept --force.")
        }
    }
}

struct SourceProbeOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let live: Bool

    fileprivate init(parsed: SourceProbeArguments) throws {
        var format = try OutputFormat(rawValue: parsed.format)
            .orThrow("unsupported --format. Use `human` or `json`.")

        if parsed.json {
            guard format == .human else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try AccountLabel.validate(parsed.account)
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

    fileprivate init(parsed: RawFetchArguments) throws {
        var format = try OutputFormat(rawValue: parsed.format)
            .orThrow("unsupported --format. Use `human` or `json`.")

        if parsed.json {
            guard format == .human else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try AccountLabel.validate(parsed.account)
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

    fileprivate init(parsed: RawFetchPagesArguments) throws {
        var format = try OutputFormat(rawValue: parsed.format)
            .orThrow("unsupported --format. Use `human` or `json`.")

        if parsed.json {
            guard format == .human else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try AccountLabel.validate(parsed.account)
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

    fileprivate init(parsed: IngestUpdateArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
        self.adapter = try SourceAdapter(rawValue: parsed.adapter)
            .orThrow("unsupported --adapter. Use `v2`.")
        guard self.adapter == .v2 else {
            throw CLIError("ingest update is currently implemented only for --adapter v2.")
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

    fileprivate init(parsed: DBImportRawArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
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

    fileprivate init(parsed: DBImportFilesArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
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

struct DBStatsOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat

    fileprivate init(parsed: DBStatsArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
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

    fileprivate init(parsed: AuditOverlapArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
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


struct QueryCategoriesOptions {
    let account: String
    let dbPath: String?
    let format: OutputFormat
    let limit: Int

    fileprivate init(parsed: QueryCategoriesArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.limit = parsed.limit
        try SwarmDatabase.validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
    }
}

struct QueryVenuesOptions {
    let account: String
    let dbPath: String?
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
    let categoryNames: [String]
    let nearLatitude: Double?
    let nearLongitude: Double?
    let radiusMeters: Double?
    let sort: EvidenceSort?
    let limit: Int

    fileprivate init(parsed: QueryVenuesArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
        self.fromCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.from, optionName: "--from")
        self.toCreatedAt = try SwarmDatabase.parseQueryTimestamp(parsed.to, optionName: "--to")
        self.date = parsed.date
        self.hourFrom = parsed.hourFrom
        self.hourTo = parsed.hourTo
        self.locality = parsed.locality
        self.region = parsed.region
        self.postalCode = parsed.postalCode
        self.countryCode = parsed.countryCode
        self.categoryNames = parsed.categoryNames
        self.nearLatitude = parsed.nearLatitude
        self.nearLongitude = parsed.nearLongitude
        self.radiusMeters = parsed.radiusMeters
        self.sort = try SwarmDatabase.parseEvidenceSort(parsed.sort)
        self.limit = parsed.limit
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
        try SwarmDatabase.validateGeoOptions(
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude,
            radiusMeters: radiusMeters
        )
        if sort == .nearest && radiusMeters == nil {
            throw CLIError("--sort nearest requires --near-lat, --near-lng, and --radius-meters.")
        }
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
    let limit: Int

    fileprivate init(parsed: QueryVisitsArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
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
        self.limit = parsed.limit
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



struct QueryCompareOptions {
    let account: String
    let dbPath: String?
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
    let categoryNames: [String]
    let nearLatitude: Double?
    let nearLongitude: Double?
    let radiusMeters: Double?
    let sort: EvidenceSort?
    let minBaselineVisits: Int
    let limit: Int

    fileprivate init(parsed: QueryCompareArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
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
        try SwarmDatabase.validateGeoOptions(
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude,
            radiusMeters: radiusMeters
        )
        if sort == .nearest && radiusMeters == nil {
            throw CLIError("--sort nearest requires --near-lat, --near-lng, and --radius-meters.")
        }
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

    fileprivate init(parsed: EvidenceWindowArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
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
    let format: OutputFormat
    let date: String
    let hourFrom: Int?
    let hourTo: Int?
    let locality: String?
    let region: String?
    let postalCode: String?
    let countryCode: String?
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

    fileprivate init(parsed: EvidencePacketArguments) throws {
        self.account = try AccountLabel.validate(parsed.account)
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = parsed.dbPath
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
        try SwarmDatabase.validateGeoOptions(nearLatitude: nearLatitude, nearLongitude: nearLongitude, radiusMeters: radiusMeters)
    }
}

private struct SetupArguments: ParsableArguments {
    @Option var account: String?
    @Option var config: String?
    @Option var format = "human"
    @Option(name: .customLong("access-token")) var accessToken: String?
    @Option(name: .customLong("client-id")) var clientID: String?
    @Option(name: .customLong("client-secret")) var clientSecret: String?
    @Option(name: .customLong("redirect-uri")) var redirectURI: String?
    @Option(name: .customLong("authorization-code")) var authorizationCode: String?
    @Flag var json = false
}

private struct AuthArguments: ParsableArguments {
    @Argument var action: String?
    @Option var account: String?
    @Option var config: String?
    @Option var format = "human"
    @Option(name: .customLong("access-token")) var accessToken: String?
    @Option(name: .customLong("client-id")) var clientID: String?
    @Option(name: .customLong("client-secret")) var clientSecret: String?
    @Option(name: .customLong("redirect-uri")) var redirectURI: String?
    @Option(name: .customLong("authorization-code")) var authorizationCode: String?
    @Flag var force = false
    @Flag var json = false
}

private struct SourceProbeArguments: ParsableArguments {    @Option var account: String?
    @Option var adapter = "v2"
    @Option var format = "human"
    @Option var config: String?
    @Flag var live = false
    @Flag var json = false
}

private struct RawFetchArguments: ParsableArguments {
    @Option var account: String?
    @Option var adapter = "v2"
    @Option var format = "human"
    @Option var config: String?
    @Option(name: .customLong("out")) var outputDirectory: String?
    @Option var limit = RawFetch.defaultLimit
    @Option var offset = 0
    @Flag var json = false
}

private struct RawFetchPagesArguments: ParsableArguments {
    @Option var account: String?
    @Option var adapter = "v2"
    @Option var format = "human"
    @Option var config: String?
    @Option(name: .customLong("out")) var outputDirectory: String?
    @Option var limit = RawFetch.defaultLimit
    @Option(name: .customLong("start-offset")) var startOffset = 0
    @Option var pages: Int
    @Option(name: .customLong("delay-ms")) var delayMilliseconds = RawFetch.fetchPagesDefaultDelayMilliseconds
    @Flag var json = false
}

private struct IngestUpdateArguments: ParsableArguments {
    @Option var account: String?
    @Option var adapter = "v2"
    @Option var format = "human"
    @Option var config: String?
    @Option(name: .customLong("raw-dir")) var rawDirectory: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var pages = IngestUpdate.defaultPages
    @Option var limit = RawFetch.defaultLimit
    @Option(name: .customLong("delay-ms")) var delayMilliseconds = RawFetch.fetchPagesDefaultDelayMilliseconds
    @Flag var json = false
}

private struct DBImportRawArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("raw-dir")) var rawDirectory: String?
    @Option var format = "human"
    @Flag var json = false
}

private struct DBImportFilesArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var path: String?
    @Option var source = FileImportSource.foursquareExport.rawValue
    @Option var format = "human"
    @Flag var json = false
}

private struct DBStatsArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var format = "human"
    @Flag var json = false
}

private struct AuditOverlapArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("raw-dir")) var rawDirectory: String?
    @Option var path: String?
    @Option var examples = SourceAudit.defaultExampleLimit
    @Option var format = "human"
    @Flag var json = false
}



private struct QueryCategoriesArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "human"
    @Flag var json = false
}

private struct QueryVenuesArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("from")) var from: String?
    @Option(name: .customLong("to")) var to: String?
    @Option var date: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option var sort: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "human"
    @Flag var json = false
}

private struct QueryVisitsArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("venue-id")) var venueID: String?
    @Option(name: .customLong("from")) var from: String?
    @Option(name: .customLong("to")) var to: String?
    @Option var date: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "human"
    @Flag var json = false
}



private struct QueryCompareArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("baseline-from")) var baselineFrom: String?
    @Option(name: .customLong("baseline-to")) var baselineTo: String?
    @Option(name: .customLong("recent-from")) var recentFrom: String?
    @Option(name: .customLong("recent-to")) var recentTo: String?
    @Option(name: .customLong("as-of")) var asOf: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option var sort: String?
    @Option(name: .customLong("min-baseline-visits")) var minBaselineVisits = 1
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "human"
    @Flag var json = false
}

private struct EvidenceWindowArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var date: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "human"
    @Flag var json = false
}

private struct EvidencePacketArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var date: String?
    @Option(name: .customLong("baseline-from")) var baselineFrom: String?
    @Option(name: .customLong("baseline-to")) var baselineTo: String?
    @Option(name: .customLong("recent-from")) var recentFrom: String?
    @Option(name: .customLong("recent-to")) var recentTo: String?
    @Option(name: .customLong("as-of")) var asOf: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option(name: .customLong("min-baseline-visits")) var minBaselineVisits = 1
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "human"
    @Flag var json = false
}

private func parseFormat(format rawFormat: String, json: Bool) throws -> OutputFormat {    var format = try OutputFormat(rawValue: rawFormat)
        .orThrow("unsupported --format. Use `human` or `json`.")

    if json {
        guard format == .human else {
            throw CLIError("use either `--json` or `--format json`, not both.")
        }
        format = .json
    }

    return format
}

enum Formatter {
    static func render(_ result: SetupAuthResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: SourceProbeResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func render(_ result: RawFetchResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func render(_ result: RawFetchPagesResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: IngestUpdateResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: RawImportResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func render(_ result: DatabaseStatsResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: SourceOverlapAuditResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryCategoriesResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryVenuesResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryVisitsResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryCompareResult, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: EvidenceWindowPacket, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: EvidencePacket, format: OutputFormat) throws -> String {
        switch format {
        case .human:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    private static func renderJSON<T: Encodable>(_ result: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(result)
        return String(decoding: data, as: UTF8.self)
    }

    private static func renderHuman(_ result: SetupAuthResult) -> String {
        [
            "Auth \(result.action): \(result.status)",
            result.message,
            "Config path: \(result.configPath)",
            "Config exists: \(result.configExists ? "yes" : "no")",
            "Account: \(result.account)",
            "V2 access token: \(result.v2AccessTokenPresent ? "present" : "missing")",
            "V2 client id: \(result.v2ClientIDPresent ? "present" : "missing")",
            "V2 client secret: \(result.v2ClientSecretPresent ? "present" : "missing")",
            "V2 redirect URI: \(result.v2RedirectURIPresent ? "present" : "missing")",
            "Raw check-ins: \(result.rawDirectory)",
            "SQLite DB: \(result.sqlitePath)",
            "Network: \(result.networkPerformed ? "performed" : "not performed")",
            "Next: \(result.nextSuggestedCommand)"
        ].joined(separator: "\n")
    }

    private static func renderHuman(_ result: SourceProbeResult) -> String {
        var lines: [String] = [
            result.probeKind == "dry_config_validation" ? "source probe (dry config validation)" : "source probe (\(result.probeKind))",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "network: \(result.networkPerformed ? "performed" : "not performed")"
        ]

        if let liveProbe = result.liveProbe {
            lines.append("endpoint: \(liveProbe.endpoint)")
            if let httpStatusCode = liveProbe.httpStatusCode {
                lines.append("http_status: \(httpStatusCode)")
            }
            if let coverage = liveProbe.fieldCoverage {
                lines.append("field coverage:")
                lines.append("  - checkin id: \(coverage.checkinID ? "present" : "missing")")
                lines.append("  - createdAt: \(coverage.createdAt ? "present" : "missing")")
                lines.append("  - venue id/name: \(coverage.venueID && coverage.venueName ? "present" : "partial_or_missing")")
                lines.append("  - lat/lng: \(coverage.latitude && coverage.longitude ? "present" : "partial_or_missing")")
                lines.append("  - categories: \(coverage.categories ? "present" : "missing")")
                lines.append("  - photos: \(coverage.photosPresent ? "present" : "not_present")")
            }
        }

        if !result.requiredMissing.isEmpty {
            lines.append("missing required inputs:")
            lines.append(contentsOf: result.requiredMissing.map { "  - \($0)" })
        }

        lines.append("next actions:")
        lines.append(contentsOf: result.nextActions.map { "  - \($0)" })
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: RawFetchResult) -> String {
        var lines: [String] = [
            "raw fetch",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "limit: \(result.limit)",
            "offset: \(result.offset)",
            "raw_file: \(result.rawFilePath)",
            "manifest_file: \(result.manifestFilePath)",
            "bytes: \(result.bytes)",
            "http_status: \(result.httpStatusCode)"
        ]

        if let apiMetaCode = result.apiMetaCode {
            lines.append("api_meta_code: \(apiMetaCode)")
        }
        if let returnedCount = result.returnedCount {
            lines.append("returned_count: \(returnedCount)")
        }
        if let totalCount = result.totalCount {
            lines.append("total_count: \(totalCount)")
        }

        lines.append("network: one request performed")
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: RawFetchPagesResult) -> String {
        var lines: [String] = [
            "raw fetch-pages",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "output_dir: \(result.outputDirectory)",
            "limit: \(result.limit)",
            "start_offset: \(result.startOffset)",
            "requested_pages: \(result.requestedPages)",
            "fetched_pages: \(result.fetchedPages)",
            "request_count: \(result.requestCount)",
            "next_offset: \(result.nextOffset)",
            "network: \(result.networkPerformed ? "performed" : "not performed")"
        ]
        if let stopReason = result.stopReason {
            lines.append("stop_reason: \(stopReason)")
        }
        if let last = result.results.last {
            lines.append("last_raw_file: \(last.rawFilePath)")
            lines.append("last_manifest_file: \(last.manifestFilePath)")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: IngestUpdateResult) -> String {
        var lines: [String] = [
            "ingest update",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "complete: \(result.complete)",
            "requests: \(result.requestCount)",
            "fetched_pages: \(result.fetchedPages)",
            "imported_pages: \(result.importedPages)",
            "checkins_inserted: \(result.checkinsInserted)",
            "raw_files_inserted: \(result.rawFilesInserted)",
            "current_through: \(result.freshnessAfter?.currentThroughISO8601 ?? "unknown")"
        ]
        if let lastFetched = result.freshnessAfter?.lastFetchedAtISO8601 {
            lines.append("last_fetched_at: \(lastFetched)")
        }
        if let lastImported = result.freshnessAfter?.lastImportedAtISO8601 {
            lines.append("last_imported_at: \(lastImported)")
        }
        if let stopReason = result.stopReason {
            lines.append("stop_reason: \(stopReason)")
        }
        if !result.missingInputs.isEmpty {
            lines.append("missing_inputs: \(result.missingInputs.joined(separator: ", "))")
        }
        if let sourceStatus = result.sourceStatus {
            lines.append("source_status: \(sourceStatus.rawValue)")
        }
        if let errorMessage = result.errorMessage {
            lines.append("error: \(errorMessage)")
        }
        lines.append("network: \(result.networkPerformed ? "performed" : "not performed")")
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: RawImportResult) -> String {
        var lines: [String] = [
            result.command,
            "account: \(result.account ?? "unspecified")",
            "db: \(result.dbPath)",
            "raw_dir: \(result.rawDirectory)",
            "raw_files_imported: \(result.rawFilesImported)",
            "raw_files_inserted: \(result.rawFilesInserted)",
            "checkins_upserted: \(result.checkinsUpserted)",
            "checkins_inserted: \(result.checkinsInserted)",
            "venues_upserted: \(result.venuesUpserted)",
            "venues_inserted: \(result.venuesInserted)",
            "categories_upserted: \(result.categoriesUpserted)",
            "categories_inserted: \(result.categoriesInserted)",
            "skipped_files: \(result.skippedFiles)",
            "skipped_checkins: \(result.skippedCheckins)",
            "network: not performed"
        ]

        if let qualityReportPath = result.qualityReportPath {
            lines.append("quality:")
            lines.append("  missing/null values: \(result.qualityIssueCount)")
            lines.append("  report: \(qualityReportPath)")
            if let account = result.account {
                lines.append("  follow-up:")
                lines.append("    swarm-cadence raw fetch-checkins --account \(account) --ids-file \(qualityReportPath)")
            }
        }

        if !result.warnings.isEmpty {
            lines.append("warnings:")
            lines.append(contentsOf: result.warnings.map { "  - \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: SourceOverlapAuditResult) -> String {
        var lines: [String] = [
            "audit overlap",
            "account: \(result.account)",
            "v2_raw_dir: \(result.v2RawDirectory)",
            "export_path: \(result.exportPath)",
            "v2_checkins: \(result.v2Checkins)",
            "export_checkins: \(result.exportCheckins)",
            "overlapping_checkins: \(result.overlappingCheckins)",
            "v2_only_checkins: \(result.v2OnlyCheckins)",
            "export_only_checkins: \(result.exportOnlyCheckins)",
            "matches:",
            "  timestamp: \(result.timestampMatches)",
            "  venue_id: \(result.venueIDMatches)",
            "  venue_name: \(result.venueNameMatches)",
            "  lat_lng: \(result.latitudeLongitudeMatches)",
            "mismatches:",
            "  timestamp: \(result.timestampMismatches)",
            "  venue_id: \(result.venueIDMismatches)",
            "  venue_name: \(result.venueNameMismatches)",
            "  lat_lng: \(result.latitudeLongitudeMismatches)",
            "categories:",
            "  v2_rows_with_categories: \(result.v2RowsWithCategories)",
            "  export_rows_with_categories: \(result.exportRowsWithCategories)",
            "  overlapping_v2_rows_with_categories: \(result.overlappingV2RowsWithCategories)",
            "  overlapping_export_rows_with_categories: \(result.overlappingExportRowsWithCategories)",
            "network: not performed"
        ]
        if !result.examples.isEmpty {
            lines.append("examples:")
            for example in result.examples {
                lines.append("  - \(example.checkinID) \(example.field): v2=\(example.v2Value ?? "null") export=\(example.exportValue ?? "null")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: DatabaseStatsResult) -> String {
        var lines: [String] = [
            "db stats",
            "account: \(result.account ?? "unspecified")",
            "db: \(result.dbPath)",
            "raw_files: \(result.rawFiles)",
            "checkins: \(result.checkins)",
            "venues: \(result.venues)",
            "categories: \(result.categories)"
        ]

        if let minCreatedAt = result.minCreatedAt {
            lines.append("oldest_created_at: \(minCreatedAt)")
        }
        if let oldest = result.oldestCreatedAtISO8601 {
            lines.append("oldest_created_at_iso8601: \(oldest)")
        }
        if let maxCreatedAt = result.maxCreatedAt {
            lines.append("latest_created_at: \(maxCreatedAt)")
        }
        if let latest = result.latestCreatedAtISO8601 {
            lines.append("latest_created_at_iso8601: \(latest)")
        }
        if let currentThrough = result.currentThroughISO8601 {
            lines.append("current_through_iso8601: \(currentThrough)")
        }
        if let lastFetched = result.lastFetchedAtISO8601 {
            lines.append("last_fetched_at_iso8601: \(lastFetched)")
        }
        if let lastImported = result.lastImportedAtISO8601 {
            lines.append("last_imported_at_iso8601: \(lastImported)")
        }

        return lines.joined(separator: "\n")
    }


    private static func renderHuman(_ result: QueryCategoriesResult) -> String {
        var lines: [String] = [
            "query categories",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "total_matching_categories: \(result.totalMatchingCategories)",
            "returned_categories: \(result.returnedCategories)"
        ]
        for category in result.categories {
            lines.append("- \(category.name): checkins=\(category.checkinCount) venues=\(category.venueCount) category_id=\(category.categoryID)")
            if let first = category.firstCreatedAtISO8601, let last = category.lastCreatedAtISO8601 {
                lines.append("  first_last: \(first) … \(last)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryVenuesResult) -> String {
        var lines: [String] = [
            "query venues",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "sort: \(result.sort.rawValue)",
            "order: \(result.orderLabel)",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.venues {
            lines.append("- \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
            if let locality = venue.locality {
                let region = venue.region.map { ", \($0)" } ?? ""
                lines.append("  location: \(locality)\(region)")
            }
            if let locality = venue.locality {
                let region = venue.region.map { ", \($0)" } ?? ""
                lines.append("  location: \(locality)\(region)")
            }
            if let distanceMeters = venue.distanceMeters {
                lines.append("  distance_meters: \(Int(distanceMeters.rounded()))")
            }
            if let first = venue.firstCreatedAtISO8601, let last = venue.lastCreatedAtISO8601 {
                lines.append("  first_last: \(first) … \(last)")
            }
            if !venue.categories.isEmpty {
                lines.append("  categories: \(venue.categories.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryVisitsResult) -> String {
        var lines: [String] = [
            "query visits",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "total_matching_visits: \(result.totalMatchingVisits)",
            "returned_visits: \(result.returnedVisits)"
        ]
        for visit in result.visits {
            lines.append("- \(visit.createdAtISO8601 ?? "unknown_time"): \(visit.venueName ?? visit.venueID ?? "unknown venue") checkin_id=\(visit.checkinID)")
            if !visit.categories.isEmpty {
                lines.append("  categories: \(visit.categories.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryCompareResult) -> String {
        var lines: [String] = [
            "query compare",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "compare_by: \(result.compareBy)",
            "sort: \(result.sort.rawValue)",
            "order: \(result.orderLabel)",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.venues {
            lines.append("- \(venue.name ?? venue.venueID): baseline=\(venue.baselineVisitCount) recent=\(venue.recentVisitCount) previous=\(venue.previousVisitCount) last=\(venue.lastCreatedAtISO8601 ?? "unknown") venue_id=\(venue.venueID)")
            if let distanceMeters = venue.distanceMeters {
                lines.append("  distance_meters: \(Int(distanceMeters.rounded()))")
            }
            if let days = venue.daysSinceLastVisit {
                lines.append("  days_since_last_visit: \(days)")
            }
            if !venue.categories.isEmpty {
                lines.append("  categories: \(venue.categories.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: EvidenceWindowPacket) -> String {
        var lines: [String] = [
            "evidence window",
            "schema: \(result.schema)",
            "tool_version: \(result.toolVersion)",
            "account: \(result.account)",
            "date: \(result.window.date)",
            "hour_from: \(result.window.hourFrom.map(String.init) ?? "unspecified")",
            "hour_to: \(result.window.hourTo.map(String.init) ?? "unspecified")",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.candidateVenues {
            lines.append("- \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: EvidencePacket) -> String {
        var lines: [String] = [
            "evidence packet",
            "schema: \(result.schema)",
            "tool_version: \(result.toolVersion)",
            "account: \(result.account)",
            "date: \(result.targetWindow.date)",
            "hour_from: \(result.targetWindow.hourFrom.map(String.init) ?? "unspecified")",
            "hour_to: \(result.targetWindow.hourTo.map(String.init) ?? "unspecified")",
            "geography: \(result.geography.semantics)",
            "views: \(result.views.map { $0.label.rawValue }.joined(separator: ", "))"
        ]
        for view in result.views {
            lines.append("view: \(view.label.rawValue)")
            lines.append("  order: \(view.orderLabel)")
            lines.append("  venue_support: \(view.venueSupport.returnedVenues)/\(view.venueSupport.totalMatchingVenues)")
            lines.append("  cadence_comparison: \(view.cadenceComparison.returnedVenues)/\(view.cadenceComparison.totalMatchingVenues)")
            for venue in view.venueSupport.venues {
                lines.append("  - \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
                if let distanceMeters = venue.distanceMeters {
                    lines.append("    distance_meters: \(Int(distanceMeters.rounded()))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum ConfigFile {
    static func loadOptional(path explicitPath: String?, environment: [String: String]) throws -> [String: String] {
        let path = explicitPath ?? AppSupportDefaults.configPath(environment: environment)
        if explicitPath == nil, !FileManager.default.fileExists(atPath: path) {
            return [:]
        }
        return try load(path: path)
    }

    static func load(path: String) throws -> [String: String] {
        if path.lowercased().hasSuffix(".json") {
            return try JSONConfig.load(path: path)
        }
        return try DotenvConfig.load(path: path)
    }
}

enum DotenvConfig {
    static func load(path: String) throws -> [String: String] {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        var values: [String: String] = [:]

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let assignment = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line
            guard let equals = assignment.firstIndex(of: "=") else { continue }

            let key = assignment[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = assignment[assignment.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }

        return values
    }
}


enum AppSupportDefaults {
    static let appDirectoryName = "swarm-cadence"

    static func appSupportDirectory(environment: [String: String]) -> String {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent(appDirectoryName, isDirectory: true)
                .path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .path
    }

    static func configPath(environment: [String: String]) -> String {
        URL(fileURLWithPath: appSupportDirectory(environment: environment))
            .appendingPathComponent("config.json")
            .path
    }

    static func accountDirectory(account: String, environment: [String: String]) -> String {
        URL(fileURLWithPath: appSupportDirectory(environment: environment), isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
            .path
    }

    static func rawCheckinsDirectory(account: String, environment: [String: String]) -> String {
        URL(fileURLWithPath: accountDirectory(account: account, environment: environment), isDirectory: true)
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("checkins", isDirectory: true)
            .path
    }

    static func sqlitePath(account: String, environment: [String: String]) -> String {
        URL(fileURLWithPath: accountDirectory(account: account, environment: environment), isDirectory: true)
            .appendingPathComponent("swarm-cadence.sqlite")
            .path
    }
}

enum JSONConfig {
    static func flatten(_ dictionary: [String: Any]) throws -> [String: String] {
        var values: [String: String] = [:]
        flattenFlatEnvironmentKeys(from: dictionary, into: &values)
        flattenAccounts(from: dictionary["accounts"], into: &values)
        return values
    }

    static func load(path: String) throws -> [String: String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CLIError("config JSON must be an object: \(path)")
        }

        return try flatten(dictionary)
    }

    private static func flattenFlatEnvironmentKeys(from dictionary: [String: Any], into values: inout [String: String]) {
        for (key, value) in dictionary where key.hasPrefix("SWARM_CADENCE_") {
            if let stringValue = value as? String, !stringValue.isEmpty {
                values[key] = stringValue
            }
        }
    }

    private static func flattenAccounts(from object: Any?, into values: inout [String: String]) {
        guard let accounts = object as? [String: Any] else { return }

        for (account, accountObject) in accounts {
            guard let accountDictionary = accountObject as? [String: Any] else { continue }
            let accountKey = AccountLabel.environmentComponent(for: account)

            if let v2 = accountDictionary["v2"] as? [String: Any] {
                map(v2, key: "access_token", to: "SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN", into: &values)
                map(v2, key: "client_id", to: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_ID", into: &values)
                map(v2, key: "client_secret", to: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_SECRET", into: &values)
                map(v2, key: "redirect_uri", to: "SWARM_CADENCE_\(accountKey)_V2_REDIRECT_URI", into: &values)
            }

            if let historysearch = accountDictionary["historysearch"] as? [String: Any] {
                map(historysearch, key: "userid", to: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_USERID", into: &values)
                map(historysearch, key: "wsid", to: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_WSID", into: &values)
                map(historysearch, key: "oauth_token", to: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_OAUTH_TOKEN", into: &values)
                map(historysearch, key: "cookie", to: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_COOKIE", into: &values)
            }
        }
    }

    private static func map(_ dictionary: [String: Any], key: String, to outputKey: String, into values: inout [String: String]) {
        guard let value = dictionary[key] as? String, !value.isEmpty else { return }
        values[outputKey] = value
    }
}

struct CLIError: Error {
    let message: String

    init(_ message: String) {
        self.message = "error: \(message)"
    }
}

extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw CLIError(message)
        }
        return value
    }
}
