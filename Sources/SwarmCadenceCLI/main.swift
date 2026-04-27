import Darwin
import Foundation
import SwarmCadenceCore

let exitCode = SwarmCadenceCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(Int32(exitCode))
