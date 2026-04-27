import Foundation

public enum SwarmCadenceCommand {
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        liveTransport: ProbeHTTPTransport = URLSessionProbeHTTPTransport(),
        output: (String) -> Void = { print($0) },
        errorOutput: (String) -> Void = { fputs($0 + "\n", stderr) }
    ) -> Int {
        do {
            let invocation = try Invocation(arguments: arguments)

            switch invocation {
            case .help:
                output(Self.helpText)
                return 0
            case let .sourceProbe(options):
                let config = try options.configPath.map(DotenvConfig.load(path:)) ?? [:]
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
                let config = try options.configPath.map(DotenvConfig.load(path:)) ?? [:]
                let result = try RawFetch.fetch(
                    account: options.account,
                    adapter: options.adapter,
                    config: config,
                    environment: environment,
                    outputDirectory: options.outputDirectory,
                    limit: options.limit,
                    offset: options.offset,
                    transport: liveTransport
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .dbImportRaw(options):
                let result = try SwarmDatabase.importRawV2Checkins(
                    dbPath: options.dbPath,
                    rawDirectory: options.rawDirectory
                )
                output(try Formatter.render(result, format: options.format))
                return 0
            case let .dbStats(options):
                let result = try SwarmDatabase.stats(dbPath: options.dbPath)
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

    public static let helpText = """
    swarm-cadence

    Usage:
      swarm-cadence source probe --account <label> --adapter <v2|historysearch> [--format <human|json>] [--config <path>] [--live]
      swarm-cadence raw fetch --account <label> --adapter v2 --out <dir> [--limit <1...250>] [--offset <n>] [--format <human|json>] [--config <path>]
      swarm-cadence db import-raw --db <path> --raw-dir <dir> [--format <human|json>]
      swarm-cadence db stats --db <path> [--format <human|json>]

    Source probe is dry config validation by default. Pass --live to perform the explicit minimal read-only v2 checkins probe.
    Raw fetch performs exactly one conservative v2 checkins request and writes one raw JSON response plus an adjacent manifest.
    DB import reads preserved raw v2 files from disk only; it performs no network calls.
    """
}

enum Invocation {
    case help
    case sourceProbe(SourceProbeOptions)
    case rawFetch(RawFetchOptions)
    case dbImportRaw(DBImportRawOptions)
    case dbStats(DBStatsOptions)

    init(arguments: [String]) throws {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
            self = .help
            return
        }

        guard arguments.count >= 2 else {
            throw CLIError("unsupported command. Run `swarm-cadence --help`.")
        }

        switch (arguments[0], arguments[1]) {
        case ("source", "probe"):
            self = .sourceProbe(try SourceProbeOptions(arguments: Array(arguments.dropFirst(2))))
        case ("raw", "fetch"):
            self = .rawFetch(try RawFetchOptions(arguments: Array(arguments.dropFirst(2))))
        case ("db", "import-raw"):
            self = .dbImportRaw(try DBImportRawOptions(arguments: Array(arguments.dropFirst(2))))
        case ("db", "stats"):
            self = .dbStats(try DBStatsOptions(arguments: Array(arguments.dropFirst(2))))
        default:
            throw CLIError("unsupported command. Run `swarm-cadence --help`.")
        }
    }
}

struct SourceProbeOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let live: Bool

    init(arguments: [String]) throws {
        var parser = OptionParser(arguments: arguments)

        let account = parser.value(for: "--account")
        var format = try OutputFormat(rawValue: parser.value(for: "--format") ?? "human")
            .orThrow("unsupported --format. Use `human` or `json`.")

        if parser.consumeFlag("--json") {
            guard format == .human else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try AccountLabel.validate(account)
        self.adapter = try SourceAdapter(rawValue: parser.value(for: "--adapter") ?? "v2")
            .orThrow("unsupported --adapter. Use `v2` or `historysearch`.")
        self.format = format
        self.configPath = parser.value(for: "--config")
        self.live = parser.consumeFlag("--live")

        try parser.finish()
    }
}

struct RawFetchOptions {
    let account: String
    let adapter: SourceAdapter
    let format: OutputFormat
    let configPath: String?
    let outputDirectory: String
    let limit: Int
    let offset: Int

    init(arguments: [String]) throws {
        var parser = OptionParser(arguments: arguments)

        let account = parser.value(for: "--account")
        var format = try OutputFormat(rawValue: parser.value(for: "--format") ?? "human")
            .orThrow("unsupported --format. Use `human` or `json`.")

        if parser.consumeFlag("--json") {
            guard format == .human else {
                throw CLIError("use either `--json` or `--format json`, not both.")
            }
            format = .json
        }

        self.account = try AccountLabel.validate(account)
        self.adapter = try SourceAdapter(rawValue: parser.value(for: "--adapter") ?? "v2")
            .orThrow("unsupported --adapter. Use `v2`.")
        guard self.adapter == .v2 else {
            throw CLIError("raw fetch is currently implemented only for --adapter v2.")
        }
        self.format = format
        self.configPath = parser.value(for: "--config")
        self.outputDirectory = try parser.value(for: "--out")
            .orThrow("missing required --out <dir>.")
        guard !self.outputDirectory.isEmpty else {
            throw CLIError("missing required --out <dir>.")
        }

        if let rawLimit = parser.value(for: "--limit") {
            guard let parsedLimit = Int(rawLimit) else {
                throw CLIError("--limit must be an integer between 1 and \(RawFetch.hardLimit).")
            }
            self.limit = parsedLimit
        } else {
            self.limit = RawFetch.defaultLimit
        }

        guard self.limit >= 1 else {
            throw CLIError("--limit must be at least 1.")
        }
        guard self.limit <= RawFetch.hardLimit else {
            throw CLIError("--limit \(self.limit) exceeds the hard max of \(RawFetch.hardLimit) per invocation.")
        }

        if let rawOffset = parser.value(for: "--offset") {
            guard let parsedOffset = Int(rawOffset) else {
                throw CLIError("--offset must be a non-negative integer.")
            }
            self.offset = parsedOffset
        } else {
            self.offset = 0
        }

        guard self.offset >= 0 else {
            throw CLIError("--offset must be at least 0.")
        }

        try parser.finish()
    }
}

struct DBImportRawOptions {
    let dbPath: String
    let rawDirectory: String
    let format: OutputFormat

    init(arguments: [String]) throws {
        var parser = OptionParser(arguments: arguments)
        self.format = try parseFormat(parser: &parser)
        self.dbPath = try parser.value(for: "--db")
            .orThrow("missing required --db <path>.")
        self.rawDirectory = try parser.value(for: "--raw-dir")
            .orThrow("missing required --raw-dir <dir>.")
        try parser.finish()
    }
}

struct DBStatsOptions {
    let dbPath: String
    let format: OutputFormat

    init(arguments: [String]) throws {
        var parser = OptionParser(arguments: arguments)
        self.format = try parseFormat(parser: &parser)
        self.dbPath = try parser.value(for: "--db")
            .orThrow("missing required --db <path>.")
        try parser.finish()
    }
}

private func parseFormat(parser: inout OptionParser) throws -> OutputFormat {
    var format = try OutputFormat(rawValue: parser.value(for: "--format") ?? "human")
        .orThrow("unsupported --format. Use `human` or `json`.")

    if parser.consumeFlag("--json") {
        guard format == .human else {
            throw CLIError("use either `--json` or `--format json`, not both.")
        }
        format = .json
    }

    return format
}

struct OptionParser {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    private var unknown: [String] = []

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json", "--live":
                flags.insert(argument)
                index += 1
            case "--account", "--adapter", "--format", "--config", "--out", "--limit", "--offset", "--db", "--raw-dir":
                guard index + 1 < arguments.count else {
                    unknown.append(argument)
                    index += 1
                    continue
                }
                values[argument] = arguments[index + 1]
                index += 2
            default:
                unknown.append(argument)
                index += 1
            }
        }
    }

    func value(for option: String) -> String? {
        values[option]
    }

    mutating func consumeFlag(_ flag: String) -> Bool {
        flags.remove(flag) != nil
    }

    func finish() throws {
        if let first = unknown.first {
            if ["--account", "--adapter", "--format", "--config", "--out", "--limit", "--offset", "--db", "--raw-dir"].contains(first) {
                throw CLIError("missing value for \(first).")
            }
            throw CLIError("unknown argument: \(first).")
        }

        if let flag = flags.first {
            throw CLIError("unknown flag: \(flag).")
        }
    }
}

enum Formatter {
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
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

    private static func renderHuman(_ result: RawImportResult) -> String {
        var lines: [String] = [
            "db import-raw",
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

        if !result.warnings.isEmpty {
            lines.append("warnings:")
            lines.append(contentsOf: result.warnings.map { "  - \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: DatabaseStatsResult) -> String {
        var lines: [String] = [
            "db stats",
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

        return lines.joined(separator: "\n")
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
