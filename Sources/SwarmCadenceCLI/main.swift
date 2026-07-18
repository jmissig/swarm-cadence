import Darwin
import Foundation
import SwarmCadenceCore

let exitCode = SwarmCadenceCommand.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    isInputTTY: isatty(STDIN_FILENO) != 0
)
exit(Int32(exitCode))
