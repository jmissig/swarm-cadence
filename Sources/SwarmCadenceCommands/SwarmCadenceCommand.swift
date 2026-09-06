import ArgumentParser
import Foundation
import SwarmCadenceCore

public enum SwarmCadenceCommand {
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        liveTransport: ProbeHTTPTransport = URLSessionProbeHTTPTransport(),
        isInputTTY: Bool = true,
        now: @escaping () -> Date = Date.init,
        input: @escaping () -> String? = { readLine(strippingNewline: true) },
        output: @escaping (String) -> Void = { print($0) },
        errorOutput: @escaping (String) -> Void = { fputs($0 + "\n", stderr) }
    ) -> Int {
        let runtime = CommandRuntime(
            arguments: Self.normalizeSignedValues(arguments),
            environment: environment,
            liveTransport: liveTransport,
            isInputTTY: isInputTTY,
            now: now,
            input: input,
            output: output,
            errorOutput: errorOutput,
            exitCode: 0
        )

        do {
            var command = try SwarmCadenceCLI.parseAsRoot(runtime.arguments)
            do {
                if var executable = command as? InvocableCommand {
                    try executable.execute(runtime)
                } else {
                    try command.run()
                }
                return runtime.exitCode
            } catch let error as CleanExit {
                output(SwarmCadenceCLI.fullMessage(for: error))
                return 0
            } catch let error as CLIError {
                errorOutput(error.message)
                return 2
            } catch {
                let exitCode = SwarmCadenceCLI.exitCode(for: error)
                if exitCode.isSuccess {
                    output(SwarmCadenceCLI.fullMessage(for: error))
                    return 0
                }
                errorOutput("error: \(error.localizedDescription)")
                return 1
            }
        } catch {
            let exitCode = SwarmCadenceCLI.exitCode(for: error)
            let message = SwarmCadenceCLI.fullMessage(for: error)
            if exitCode.isSuccess {
                output(message)
            } else {
                errorOutput(message)
            }
            return exitCode.isSuccess ? 0 : 2
        }
    }

    public static let verbsText = """
    swarm-cadence \(SwarmCadenceVersion.current)

    SUBCOMMANDS:
      auth                      Manage saved Foursquare/Swarm auth.
      setup                     Alias for `auth login`.
      source                    Inspect source/account readiness.
      raw                       Collect preserved source payloads.
      ingest                    Update the local evidence store from source data.
      db                        Import/check local SQLite evidence.
      audit                     Audit source and identity evidence.
      query                     Read evidence rows and descriptive rollups.
      annotations                     Attach/list annotations.
      evidence                  Build bounded evidence bundles for Robut.

    Run `swarm-cadence --help` for examples and grouped subcommands.
    Run a command with `--help` for detailed options, e.g. `swarm-cadence query visits --help`.
    """

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

protocol InvocableCommand: ParsableCommand {
    mutating func execute(_ runtime: CommandRuntime) throws
}

final class CommandRuntime {
    let arguments: [String]
    let environment: [String: String]
    let liveTransport: ProbeHTTPTransport
    let isInputTTY: Bool
    let now: () -> Date
    let input: () -> String?
    let output: (String) -> Void
    let errorOutput: (String) -> Void
    var exitCode: Int

    init(arguments: [String], environment: [String: String], liveTransport: ProbeHTTPTransport,
         isInputTTY: Bool, now: @escaping () -> Date, input: @escaping () -> String?,
         output: @escaping (String) -> Void, errorOutput: @escaping (String) -> Void, exitCode: Int) {
        self.arguments = arguments; self.environment = environment; self.liveTransport = liveTransport
        self.isInputTTY = isInputTTY; self.now = now; self.input = input
        self.output = output; self.errorOutput = errorOutput; self.exitCode = exitCode
    }
}

struct SwarmCadenceCLI: InvocableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swarm-cadence",
        abstract: "Build and query local Foursquare/Swarm check-in evidence.",
        discussion: """
        swarm-cadence \(SwarmCadenceVersion.current)

        Use source collection/import to build the local evidence store. Use query
        and evidence commands for bounded answers. Robut composes Guides above
        this layer; the CLI exposes source-backed rows, rollups, comparisons,
        and drill-downs.

        Examples:
          swarm-cadence --version
          swarm-cadence auth status --account <label>
          swarm-cadence auth login [--account <label>]
          swarm-cadence setup [--account <label>]
          swarm-cadence source status [--account <label>]
          swarm-cadence ingest --account default --adapter v2
          swarm-cadence query visits --account default --date 2026-03-25
          swarm-cadence annotations add --account default --target-kind venue --target-id <venue-id> --body "Annotation"
          swarm-cadence annotations list --account default --target-kind venue --target-id <venue-id>
          swarm-cadence query compare --account default --baseline-from 2026-03-01 --recent-from 2026-04-01
          swarm-cadence query lapses --account default --baseline-from 2024-01-01 --recent-from 2026-01-01
          swarm-cadence evidence packet --account default --date 2026-03-25 --baseline-from 2026-03-01 --recent-from 2026-04-01

        Defaults live under ~/Library/Application Support/swarm-cadence: config.json
        plus per-account raw archives and SQLite DBs under accounts/<label>/.

        For detailed command options, run a command with --help.
        """,
        version: SwarmCadenceVersion.current,
        groupedSubcommands: [
            CommandGroup(name: "Setup and ingest", subcommands: [
                AuthCommand.self,
                SetupCommand.self,
                SourceCommand.self,
                RawCommand.self,
                IngestCommand.self
            ]),
            CommandGroup(name: "Evidence store", subcommands: [
                DBCommand.self,
                AuditCommand.self,
                QueryCommand.self,
                AnnotationsCommand.self,
                EvidenceCommand.self
            ])
        ]
    )

    mutating func execute(_ runtime: CommandRuntime) throws {
        runtime.output(SwarmCadenceCommand.verbsText)
    }
}
