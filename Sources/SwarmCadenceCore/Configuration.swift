import Foundation

package enum ConfigFile {}

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


package enum AppSupportDefaults {
    package static let appDirectoryName = "swarm-cadence"

    package static func appSupportDirectory(environment: [String: String]) -> String {
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

    package static func configPath(environment: [String: String]) -> String {
        URL(fileURLWithPath: appSupportDirectory(environment: environment))
            .appendingPathComponent("config.json")
            .path
    }

    package static func accountDirectory(account: String, environment: [String: String]) -> String {
        URL(fileURLWithPath: appSupportDirectory(environment: environment), isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
            .path
    }

    package static func rawCheckinsDirectory(account: String, environment: [String: String]) -> String {
        URL(fileURLWithPath: accountDirectory(account: account, environment: environment), isDirectory: true)
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("checkins", isDirectory: true)
            .path
    }

    package static func sqlitePath(account: String, environment: [String: String]) -> String {
        URL(fileURLWithPath: accountDirectory(account: account, environment: environment), isDirectory: true)
            .appendingPathComponent("swarm-cadence.sqlite")
            .path
    }
}

/// Exact account identity; legacy environment naming is only an input adapter.
package struct AccountID: Hashable {
    package let rawValue: String
    package init(_ value: String) throws { rawValue = try AccountLabel.validate(value) }
}

package struct ResolvedSourceInputs {
    package let account: AccountID
    package let environment: [String: String]
    package let config: [String: String]
}

package struct AccountConfiguration {
    private let accounts: [String: [String: Any]]
    private let legacy: [String: String]

    package init(_ object: [String: Any]) {
        accounts = object["accounts"] as? [String: [String: Any]] ?? [:]
        legacy = object.reduce(into: [:]) { result, entry in
            if entry.key.hasPrefix("SWARM_CADENCE_"), let value = entry.value as? String {
                result[entry.key] = value
            }
        }
    }

    func resolve(account label: String, environment: [String: String]) throws -> ResolvedSourceInputs {
        let account = try AccountID(label)
        let component = AccountLabel.environmentComponent(for: label)
        let prefix = "SWARM_CADENCE_\(component)_"
        let aliases = Set(accounts.keys.filter { AccountLabel.environmentComponent(for: $0) == component }).union([label])
        let canonical = label == label.lowercased() && !label.contains("-")
        let keys = Set(["V2_ACCESS_TOKEN", "V2_CLIENT_ID", "V2_CLIENT_SECRET", "V2_REDIRECT_URI",
            "HISTORYSEARCH_USERID", "HISTORYSEARCH_WSID", "HISTORYSEARCH_OAUTH_TOKEN", "HISTORYSEARCH_COOKIE"].map { prefix + $0 })
        let legacyInputs = legacy.filter { keys.contains($0.key) }
        let environmentInputs = environment.filter { keys.contains($0.key) }
        if (!canonical || aliases.count > 1), (!legacyInputs.isEmpty || !environmentInputs.isEmpty) {
            throw CLIError("ambiguous legacy credential mapping for account \(label); use exact account-keyed JSON credentials and remove the shared environment/flat override.")
        }
        var values = legacyInputs
        let selected = accounts[label] ?? [:]
        for (source, fields) in [
            ("v2", ["access_token", "client_id", "client_secret", "redirect_uri"]),
            ("historysearch", ["userid", "wsid", "oauth_token", "cookie"])
        ] {
            let object = selected[source] as? [String: Any] ?? [:]
            for field in fields {
                if let value = object[field] as? String {
                    values[prefix + source.uppercased() + "_" + field.uppercased()] = value
                }
            }
        }
        return ResolvedSourceInputs(account: account, environment: environmentInputs, config: values)
    }
}

extension ConfigFile {
    package static func resolve(account: String, path explicitPath: String?, environment: [String: String]) throws -> ResolvedSourceInputs {
        let path = explicitPath ?? AppSupportDefaults.configPath(environment: environment)
        guard FileManager.default.fileExists(atPath: path) else {
            if explicitPath != nil { throw CLIError("config file does not exist: \(path)") }
            return try AccountConfiguration([:]).resolve(account: account, environment: environment)
        }
        if path.lowercased().hasSuffix(".json") {
            return try AccountConfiguration(SetupConfigStore.loadObjectIfPresent(path: path) ?? [:])
                .resolve(account: account, environment: environment)
        }
        return try AccountConfiguration(DotenvConfig.load(path: path)).resolve(account: account, environment: environment)
    }
}

/// Shared recognition for placeholders across setup, status, probes, and fetches.
enum CredentialValue {
    static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized.hasPrefix("replace-with-")
            || ["changeme", "change-me", "todo"].contains(normalized)
    }
    static func usable(_ value: String?) -> String? {
        guard let value, !isPlaceholder(value) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
