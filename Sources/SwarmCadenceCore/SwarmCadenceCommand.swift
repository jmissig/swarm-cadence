import ArgumentParser
import Foundation

public enum SwarmCadenceCommand {
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        liveTransport: ProbeHTTPTransport = URLSessionProbeHTTPTransport(),
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

    private static func argumentParserMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.hasPrefix("Error: ") {
            return String(message.dropFirst("Error: ".count))
        }
        return message
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

        if Array(arguments.dropFirst(2)).contains(where: { $0 == "--help" || $0 == "-h" }) {
            self = .help
            return
        }

        switch (arguments[0], arguments[1]) {
        case ("source", "probe"):
            self = .sourceProbe(try SourceProbeOptions(parsed: Self.parse(SourceProbeArguments.self, Array(arguments.dropFirst(2)))))
        case ("raw", "fetch"):
            self = .rawFetch(try RawFetchOptions(parsed: Self.parse(RawFetchArguments.self, Array(arguments.dropFirst(2)))))
        case ("db", "import-raw"):
            self = .dbImportRaw(try DBImportRawOptions(parsed: Self.parse(DBImportRawArguments.self, Array(arguments.dropFirst(2)))))
        case ("db", "stats"):
            self = .dbStats(try DBStatsOptions(parsed: Self.parse(DBStatsArguments.self, Array(arguments.dropFirst(2)))))
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
        let signedValueOptions: Set<String> = ["--limit", "--offset"]
        var normalized: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if signedValueOptions.contains(argument),
               index + 1 < arguments.count,
               arguments[index + 1].hasPrefix("-"),
               Int(arguments[index + 1]) != nil {
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
    let outputDirectory: String
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
        self.outputDirectory = try parsed.outputDirectory
            .orThrow("missing required --out <dir>.")
        guard !self.outputDirectory.isEmpty else {
            throw CLIError("missing required --out <dir>.")
        }

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

struct DBImportRawOptions {
    let dbPath: String
    let rawDirectory: String
    let format: OutputFormat

    fileprivate init(parsed: DBImportRawArguments) throws {
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = try parsed.dbPath
            .orThrow("missing required --db <path>.")
        self.rawDirectory = try parsed.rawDirectory
            .orThrow("missing required --raw-dir <dir>.")
    }
}

struct DBStatsOptions {
    let dbPath: String
    let format: OutputFormat

    fileprivate init(parsed: DBStatsArguments) throws {
        self.format = try parseFormat(format: parsed.format, json: parsed.json)
        self.dbPath = try parsed.dbPath
            .orThrow("missing required --db <path>.")
    }
}

private struct SourceProbeArguments: ParsableArguments {
    @Option var account: String?
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

private struct DBImportRawArguments: ParsableArguments {
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("raw-dir")) var rawDirectory: String?
    @Option var format = "human"
    @Flag var json = false
}

private struct DBStatsArguments: ParsableArguments {
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var format = "human"
    @Flag var json = false
}

private func parseFormat(format rawFormat: String, json: Bool) throws -> OutputFormat {
    var format = try OutputFormat(rawValue: rawFormat)
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
