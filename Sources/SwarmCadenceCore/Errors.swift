import Foundation

package struct CLIError: Error {
    package let message: String

    package init(_ message: String) {
        self.message = "error: \(message)"
    }
}

extension Optional {
    package func orThrow(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw CLIError(message)
        }
        return value
    }
}
