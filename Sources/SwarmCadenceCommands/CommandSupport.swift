import ArgumentParser
import Foundation
import SwarmCadenceCore

func parseFormat(format rawFormat: String, json: Bool) throws -> OutputFormat {
    var format = try OutputFormat(rawValue: rawFormat)
        .orThrow("unsupported --format. Use `auto`, `text`, or `json`.")

    if json {
        guard format != .json else {
            throw CLIError("use either `--json` or `--format json`, not both.")
        }
        format = .json
    }

    return format
}

func resolveConfiguredAccount(
    _ rawAccount: String?,
    configPath explicitConfigPath: String?,
    environment: [String: String]
) throws -> String {
    if let rawAccount {
        return try AccountLabel.validate(rawAccount)
    }

    let labels = try configuredAccountLabels(configPath: explicitConfigPath, environment: environment)
    if labels.count == 1 {
        return labels[0]
    }
    if labels.count > 1 {
        throw CLIError("missing required --account <label>; configured accounts: \(labels.joined(separator: ", ")).")
    }
    throw CLIError("missing required --account <label>.")
}

func resolveConfiguredAccountIfPresent(
    _ rawAccount: String?,
    configPath explicitConfigPath: String?,
    environment: [String: String]
) throws -> String? {
    if let rawAccount {
        return try AccountLabel.validate(rawAccount)
    }

    let labels = try configuredAccountLabels(configPath: explicitConfigPath, environment: environment)
    if labels.count == 1 {
        return labels[0]
    }
    if labels.count > 1 {
        throw CLIError("missing required --account <label>; configured accounts: \(labels.joined(separator: ", ")).")
    }
    return nil
}

func configuredAccountLabels(configPath explicitConfigPath: String?, environment: [String: String]) throws -> [String] {
    let configPath = explicitConfigPath ?? AppSupportDefaults.configPath(environment: environment)
    guard configPath.lowercased().hasSuffix(".json"),
          FileManager.default.fileExists(atPath: configPath) else {
        return []
    }

    return try SetupConfigStore.accountLabels(in: SetupConfigStore.loadObjectIfPresent(path: configPath))
        .map(AccountLabel.validate)
        .sorted()
}

func validateNamedGeographyOptions(
    nearPlace: String?,
    area: String?,
    locality: String?,
    region: String?,
    postalCode: String?,
    countryCode: String?,
    nearLatitude: Double?,
    nearLongitude: Double?
) throws {
    if let nearPlace, nearPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw CLIError("--near-place must not be empty.")
    }
    if let area, area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw CLIError("--area must not be empty.")
    }
    if nearPlace != nil && (nearLatitude != nil || nearLongitude != nil) {
        throw CLIError("--near-place cannot be combined with --near-lat or --near-lng.")
    }
    if area != nil && nearPlace != nil {
        throw CLIError("--area cannot be combined with --near-place.")
    }
    if area != nil && (locality != nil || region != nil || postalCode != nil || countryCode != nil) {
        throw CLIError("--area cannot be combined with --locality, --region, --postal-code, or --country-code.")
    }
}
