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

    Source probe is dry config validation by default. Pass --live to perform the explicit minimal read-only v2 checkins probe.
    """
}

enum Invocation {
    case help
    case sourceProbe(SourceProbeOptions)

    init(arguments: [String]) throws {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
            self = .help
            return
        }

        guard arguments.count >= 2, arguments[0] == "source", arguments[1] == "probe" else {
            throw CLIError("unsupported command. Run `swarm-cadence --help`.")
        }

        self = .sourceProbe(try SourceProbeOptions(arguments: Array(arguments.dropFirst(2))))
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
            case "--account", "--adapter", "--format", "--config":
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
            if ["--account", "--adapter", "--format", "--config"].contains(first) {
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
