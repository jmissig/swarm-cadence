import Foundation

public struct SourceStatusResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let status: String
    public let message: String
    public let configPath: String
    public let configExists: Bool
    public let accountCount: Int
    public let accounts: [SourceAccountStatus]
    public let networkPerformed: Bool
}

public struct SourceAccountStatus: Codable, Equatable {
    public let label: String
    public let account: String
    public let v2Configured: Bool
    public let v2AccessTokenPresent: Bool
    public let historysearchConfigured: Bool
    public let defaultRawV2Path: String
    public let defaultRawV2PathExists: Bool
    public let defaultSqliteDbPath: String
    public let defaultSqliteDbPathExists: Bool
    public let localEvidenceAvailable: Bool
}

public enum SourceStatus {
    public static func status(
        account requestedAccount: String?,
        configPath explicitConfigPath: String?,
        environment: [String: String]
    ) throws -> SourceStatusResult {
        let configPath = explicitConfigPath ?? AppSupportDefaults.configPath(environment: environment)
        let configExists = FileManager.default.fileExists(atPath: configPath)
        let object = try SetupConfigStore.loadObjectIfPresent(path: configPath)
        let configValues = try object.map(JSONConfig.flatten) ?? [:]
        let labels: [String]

        if let requestedAccount {
            labels = [try AccountLabel.validate(requestedAccount)]
        } else {
            labels = try SetupConfigStore.accountLabels(in: object)
                .map(AccountLabel.validate)
                .sorted()
        }

        let accounts = labels.map { label in
            accountStatus(label: label, environment: environment, config: configValues)
        }

        return SourceStatusResult(
            schemaVersion: 1,
            command: "source status",
            status: "ok",
            message: message(configExists: configExists, requestedAccount: requestedAccount, accountCount: accounts.count),
            configPath: configPath,
            configExists: configExists,
            accountCount: accounts.count,
            accounts: accounts,
            networkPerformed: false
        )
    }

    private static func accountStatus(
        label: String,
        environment: [String: String],
        config: [String: String]
    ) -> SourceAccountStatus {
        let accountKey = AccountLabel.environmentComponent(for: label)
        let v2TokenPresent = credentialPresent(
            "SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN",
            environment: environment,
            config: config
        )
        let v2Configured = v2TokenPresent
        let historysearchConfigured = [
            "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_USERID",
            "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_WSID",
            "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_OAUTH_TOKEN"
        ].allSatisfy { credentialPresent($0, environment: environment, config: config) }

        let rawPath = AppSupportDefaults.rawCheckinsDirectory(account: label, environment: environment)
        let sqlitePath = AppSupportDefaults.sqlitePath(account: label, environment: environment)
        let rawExists = FileManager.default.fileExists(atPath: rawPath)
        let sqliteExists = FileManager.default.fileExists(atPath: sqlitePath)

        return SourceAccountStatus(
            label: label,
            account: label,
            v2Configured: v2Configured,
            v2AccessTokenPresent: v2TokenPresent,
            historysearchConfigured: historysearchConfigured,
            defaultRawV2Path: rawPath,
            defaultRawV2PathExists: rawExists,
            defaultSqliteDbPath: sqlitePath,
            defaultSqliteDbPathExists: sqliteExists,
            localEvidenceAvailable: rawExists || sqliteExists
        )
    }

    private static func message(configExists: Bool, requestedAccount: String?, accountCount: Int) -> String {
        if let requestedAccount {
            return "reported source readiness for account \(requestedAccount); no network, SQLite queries, or raw payload reads were performed"
        }
        if accountCount > 0 {
            return "reported configured source accounts; no network, SQLite queries, or raw payload reads were performed"
        }
        if configExists {
            return "config exists but has no configured accounts"
        }
        return "config file is missing; no configured accounts found"
    }

    private static func credentialPresent(
        _ name: String,
        environment: [String: String],
        config: [String: String]
    ) -> Bool {
        if let value = trimmedNonPlaceholder(environment[name]) {
            return !value.isEmpty
        }
        if let value = trimmedNonPlaceholder(config[name]) {
            return !value.isEmpty
        }
        return false
    }

    private static func trimmedNonPlaceholder(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        guard !normalized.hasPrefix("replace-with-"),
              normalized != "changeme",
              normalized != "change-me",
              normalized != "todo" else {
            return nil
        }
        return trimmed
    }
}
