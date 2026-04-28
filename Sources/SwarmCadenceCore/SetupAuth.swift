import Foundation

public struct SetupAuthResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let action: String
    public let status: String
    public let configPath: String
    public let configExists: Bool
    public let account: String
    public let v2AccessTokenPresent: Bool
    public let v2ClientIDPresent: Bool
    public let v2ClientSecretPresent: Bool
    public let v2RedirectURIPresent: Bool
    public let rawDirectory: String
    public let sqlitePath: String
    public let networkPerformed: Bool
    public let nextSuggestedCommand: String
    public let message: String
}

public struct SetupAuthInputs: Equatable {
    public let accessToken: String?
    public let clientID: String?
    public let clientSecret: String?
    public let redirectURI: String?
    public let authorizationCode: String?

    public init(
        accessToken: String? = nil,
        clientID: String? = nil,
        clientSecret: String? = nil,
        redirectURI: String? = nil,
        authorizationCode: String? = nil
    ) {
        self.accessToken = accessToken
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.authorizationCode = authorizationCode
    }
}

enum SetupAuth {
    static let defaultRedirectURI = "http://localhost:17342/foursquare/callback"

    static func status(
        account: String?,
        configPath explicitConfigPath: String?,
        environment: [String: String]
    ) throws -> SetupAuthResult {
        let account = try AccountLabel.validate(account)
        let configPath = explicitConfigPath ?? AppSupportDefaults.configPath(environment: environment)
        return try makeStatusResult(
            action: "status",
            statusOverride: nil,
            account: account,
            configPath: configPath,
            environment: environment,
            networkPerformed: false,
            messageOverride: nil
        )
    }

    static func setup(
        action: String = "login",
        account rawAccount: String?,
        configPath explicitConfigPath: String?,
        format: OutputFormat,
        inputs: SetupAuthInputs,
        environment: [String: String],
        transport: ProbeHTTPTransport,
        input: () -> String?,
        promptOutput: (String) -> Void
    ) throws -> SetupAuthResult {
        let configPath = explicitConfigPath ?? AppSupportDefaults.configPath(environment: environment)
        try requireJSONConfigPath(configPath)
        let existing = try SetupConfigStore.loadObjectIfPresent(path: configPath)
        let existingAccounts = SetupConfigStore.accountLabels(in: existing)
        let account = try resolvedAccountLabel(
            rawAccount,
            existingAccounts: existingAccounts,
            format: format,
            input: input,
            output: promptOutput
        )
        let existingValues = try existing.map { try JSONConfig.flatten($0) } ?? [:]
        var networkPerformed = false

        let accountKey = AccountLabel.environmentComponent(for: account)
        let existingToken = existingCredential(
            name: "SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN",
            environment: environment,
            config: existingValues
        )
        var token = trimmedNonEmpty(inputs.accessToken)
        var clientID = trimmedNonEmpty(inputs.clientID)
        var clientSecret = trimmedNonEmpty(inputs.clientSecret)
        var redirectURI = trimmedNonEmpty(inputs.redirectURI)
        var authorizationCode = trimmedNonEmpty(inputs.authorizationCode)

        if format == .human {
            promptOutput("Auth login for swarm-cadence.")
            promptOutput("Config path: \(configPath)")
            promptOutput("Raw check-ins: \(AppSupportDefaults.rawCheckinsDirectory(account: account, environment: environment))")
            promptOutput("SQLite DB: \(AppSupportDefaults.sqlitePath(account: account, environment: environment))")
            promptOutput("Choose one credential path:")
            promptOutput("1. Paste an existing Foursquare v2 access token if you already have one. This is the fastest path.")
            promptOutput("2. Leave the token blank to start the browser OAuth flow. You will need a Foursquare developer app client id/secret; the CLI will print the URL and ask for the returned code.")
        }

        if token == nil, let existingToken {
            token = existingToken
            if format == .human {
                promptOutput("Existing v2 access token found for \(account); keeping it. Pass --access-token to replace it, or run auth clear first.")
            }
        }

        if token == nil {
            if format == .human {
                token = try promptOptional("Foursquare v2 access token", input: input, output: promptOutput)
            } else {
                clientID = clientID ?? existingCredential(
                    name: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_ID",
                    environment: environment,
                    config: existingValues
                )
                clientSecret = clientSecret ?? existingCredential(
                    name: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_SECRET",
                    environment: environment,
                    config: existingValues
                )
                redirectURI = redirectURI ?? existingCredential(
                    name: "SWARM_CADENCE_\(accountKey)_V2_REDIRECT_URI",
                    environment: environment,
                    config: existingValues
                ) ?? defaultRedirectURI
                guard clientID != nil, clientSecret != nil, authorizationCode != nil else {
                    throw CLIError("auth login --format json requires --access-token, an existing stored token, or complete OAuth code-flow options: --client-id, --client-secret, and --authorization-code.")
                }
            }
        }

        if token == nil {
            clientID = try clientID ?? existingCredential(
                name: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_ID",
                environment: environment,
                config: existingValues
            ) ?? promptRequired("Foursquare developer app client id", input: input, output: promptOutput)
            clientSecret = try clientSecret ?? existingCredential(
                name: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_SECRET",
                environment: environment,
                config: existingValues
            ) ?? promptRequired("Foursquare developer app client secret", input: input, output: promptOutput)
            redirectURI = try redirectURI ?? existingCredential(
                name: "SWARM_CADENCE_\(accountKey)_V2_REDIRECT_URI",
                environment: environment,
                config: existingValues
            ) ?? promptWithDefault("Foursquare developer app redirect URI", defaultValue: defaultRedirectURI, input: input, output: promptOutput)

            let authorizationURL = try FoursquareOAuth.authorizationURL(clientID: clientID!, redirectURI: redirectURI!)
            if format == .human {
                promptOutput("Open this authorization URL:")
                promptOutput(authorizationURL.absoluteString)
            }

            authorizationCode = try authorizationCode ?? promptRequired("Code returned after opening the authorization URL", input: input, output: promptOutput)
            token = try FoursquareOAuth.exchangeCodeForAccessToken(
                clientID: clientID!,
                clientSecret: clientSecret!,
                redirectURI: redirectURI!,
                code: authorizationCode!,
                transport: transport
            )
            networkPerformed = true
        }

        guard let token else {
            throw CLIError("missing Foursquare v2 access token.")
        }

        var v2Values: [String: String] = ["access_token": token]
        if let clientID { v2Values["client_id"] = clientID }
        if let clientSecret { v2Values["client_secret"] = clientSecret }
        if let redirectURI { v2Values["redirect_uri"] = redirectURI }
        try SetupConfigStore.upsertV2(account: account, values: v2Values, at: configPath)

        return try makeStatusResult(
            action: action,
            statusOverride: "configured",
            account: account,
            configPath: configPath,
            environment: environment,
            networkPerformed: networkPerformed,
            messageOverride: "saved Foursquare v2 credentials for \(account); secrets are stored in the config file and were not printed"
        )
    }

    static func clear(
        account: String?,
        configPath explicitConfigPath: String?,
        environment: [String: String],
        force: Bool
    ) throws -> SetupAuthResult {
        let account = try AccountLabel.validate(account)
        guard force else {
            throw CLIError("auth clear requires --force.")
        }
        let configPath = explicitConfigPath ?? AppSupportDefaults.configPath(environment: environment)
        try requireJSONConfigPath(configPath)
        try SetupConfigStore.clearV2(account: account, at: configPath)
        return try makeStatusResult(
            action: "clear",
            statusOverride: "cleared",
            account: account,
            configPath: configPath,
            environment: environment,
            networkPerformed: false,
            messageOverride: "removed stored v2 credentials for \(account)"
        )
    }

    private static func makeStatusResult(
        action: String,
        statusOverride: String?,
        account: String,
        configPath: String,
        environment: [String: String],
        networkPerformed: Bool,
        messageOverride: String?
    ) throws -> SetupAuthResult {
        let configExists = FileManager.default.fileExists(atPath: configPath)
        let config = configExists ? try ConfigFile.load(path: configPath) : [:]
        let accountKey = AccountLabel.environmentComponent(for: account)
        let tokenPresent = credentialPresent("SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN", environment: environment, config: config)
        let clientIDPresent = credentialPresent("SWARM_CADENCE_\(accountKey)_V2_CLIENT_ID", environment: environment, config: config)
        let clientSecretPresent = credentialPresent("SWARM_CADENCE_\(accountKey)_V2_CLIENT_SECRET", environment: environment, config: config)
        let redirectURIPresent = credentialPresent("SWARM_CADENCE_\(accountKey)_V2_REDIRECT_URI", environment: environment, config: config)
        let nextCommand = tokenPresent
            ? "swarm-cadence source probe --account \(account) --adapter v2 --live"
            : "swarm-cadence auth login --account \(account)"
        let status = statusOverride ?? (tokenPresent ? "ready" : "needs_setup")
        let message = messageOverride ?? {
            if tokenPresent {
                return "config has a v2 access token for \(account)"
            }
            if configExists {
                return "config exists, but no v2 access token is present for \(account)"
            }
            return "config file is missing"
        }()

        return SetupAuthResult(
            schemaVersion: 1,
            command: "swarm-cadence auth",
            action: action,
            status: status,
            configPath: configPath,
            configExists: configExists,
            account: account,
            v2AccessTokenPresent: tokenPresent,
            v2ClientIDPresent: clientIDPresent,
            v2ClientSecretPresent: clientSecretPresent,
            v2RedirectURIPresent: redirectURIPresent,
            rawDirectory: AppSupportDefaults.rawCheckinsDirectory(account: account, environment: environment),
            sqlitePath: AppSupportDefaults.sqlitePath(account: account, environment: environment),
            networkPerformed: networkPerformed,
            nextSuggestedCommand: nextCommand,
            message: message
        )
    }


    private static func resolvedAccountLabel(
        _ rawAccount: String?,
        existingAccounts: [String],
        format: OutputFormat,
        input: () -> String?,
        output: (String) -> Void
    ) throws -> String {
        if let rawAccount {
            return try AccountLabel.validate(rawAccount)
        }

        guard format == .human else {
            throw CLIError("auth login --format json requires --account <label>.")
        }

        if existingAccounts.isEmpty {
            return try AccountLabel.validate(promptWithDefault(
                "Account label",
                defaultValue: "julian",
                input: input,
                output: output
            ))
        }

        output("Existing accounts: \(existingAccounts.joined(separator: ", "))")
        return try AccountLabel.validate(promptWithDefault(
            "Account label to update or add",
            defaultValue: existingAccounts[0],
            input: input,
            output: output
        ))
    }

    private static func credentialPresent(_ name: String, environment: [String: String], config: [String: String]) -> Bool {
        existingCredential(name: name, environment: environment, config: config) != nil
    }

    private static func existingCredential(name: String, environment: [String: String], config: [String: String]) -> String? {
        if let value = trimmedNonEmpty(environment[name]), !isPlaceholder(value) {
            return value
        }
        if let value = trimmedNonEmpty(config[name]), !isPlaceholder(value) {
            return value
        }
        return nil
    }

    private static func promptOptional(_ prompt: String, input: () -> String?, output: (String) -> Void) throws -> String? {
        output("\(prompt) (paste token, or leave blank to use browser OAuth):")
        guard let value = input() else {
            throw CLIError("interactive input unavailable for \(prompt).")
        }
        return trimmedNonEmpty(value)
    }

    private static func promptRequired(_ prompt: String, input: () -> String?, output: (String) -> Void) throws -> String {
        output("\(prompt):")
        guard let value = input() else {
            throw CLIError("interactive input unavailable for \(prompt).")
        }
        guard let trimmed = trimmedNonEmpty(value) else {
            throw CLIError("\(prompt) must not be empty.")
        }
        return trimmed
    }

    private static func promptWithDefault(_ prompt: String, defaultValue: String, input: () -> String?, output: (String) -> Void) throws -> String {
        output("\(prompt) [\(defaultValue)]:")
        guard let value = input() else {
            throw CLIError("interactive input unavailable for \(prompt).")
        }
        return trimmedNonEmpty(value) ?? defaultValue
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ||
            normalized.hasPrefix("replace-with-") ||
            normalized == "changeme" ||
            normalized == "change-me" ||
            normalized == "todo"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func requireJSONConfigPath(_ path: String) throws {
        guard path.lowercased().hasSuffix(".json") else {
            throw CLIError("auth writes require a JSON config path.")
        }
    }
}

enum FoursquareOAuth {
    static let authorizeEndpoint = "https://foursquare.com/oauth2/authenticate"
    static let tokenEndpoint = "https://foursquare.com/oauth2/access_token"

    static func authorizationURL(clientID: String, redirectURI: String) throws -> URL {
        var components = URLComponents(string: authorizeEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        guard let url = components?.url else {
            throw CLIError("could not construct Foursquare authorization URL.")
        }
        return url
    }

    static func exchangeCodeForAccessToken(
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        code: String,
        transport: ProbeHTTPTransport
    ) throws -> String {
        let request = try accessTokenRequest(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            code: code
        )
        let response: ProbeHTTPResponse
        do {
            response = try transport.perform(request)
        } catch {
            throw CLIError("Foursquare OAuth token exchange failed: \(Redactor.redact(error.localizedDescription, secrets: [clientSecret, code]))")
        }

        guard (200..<300).contains(response.statusCode) else {
            let body = String(decoding: response.data, as: UTF8.self)
            let redacted = Redactor.redact(body, secrets: [clientSecret, code])
            throw CLIError("Foursquare OAuth token exchange returned HTTP \(response.statusCode): \(redacted)")
        }

        guard let token = parseAccessToken(response.data) else {
            let body = String(decoding: response.data, as: UTF8.self)
            let redacted = Redactor.redact(body, secrets: [clientSecret, code])
            throw CLIError("Foursquare OAuth token exchange did not return an access token: \(redacted)")
        }
        return token
    }

    static func accessTokenRequest(
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        code: String
    ) throws -> URLRequest {
        var components = URLComponents(string: tokenEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code", value: code)
        ]
        guard let url = components?.url else {
            throw CLIError("could not construct Foursquare token exchange URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func parseAccessToken(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SetupConfigStore {
    static func accountLabels(in object: [String: Any]?) -> [String] {
        guard let accounts = object?["accounts"] as? [String: Any] else {
            return []
        }
        return accounts.keys.sorted()
    }

    static func loadObjectIfPresent(path: String) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CLIError("config JSON must be an object: \(path)")
        }
        return dictionary
    }

    static func upsertV2(account: String, values: [String: String], at path: String) throws {
        var object = try loadObjectIfPresent(path: path) ?? [:]
        var accounts = object["accounts"] as? [String: Any] ?? [:]
        var accountObject = accounts[account] as? [String: Any] ?? [:]
        var v2 = accountObject["v2"] as? [String: Any] ?? [:]

        for (key, value) in values where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            v2[key] = value
        }

        accountObject["v2"] = v2
        accounts[account] = accountObject
        object["accounts"] = accounts
        try save(object, to: path)
    }

    static func clearV2(account: String, at path: String) throws {
        guard var object = try loadObjectIfPresent(path: path) else {
            return
        }
        var accounts = object["accounts"] as? [String: Any] ?? [:]
        var accountObject = accounts[account] as? [String: Any] ?? [:]
        accountObject.removeValue(forKey: "v2")
        accounts[account] = accountObject
        object["accounts"] = accounts
        try save(object, to: path)
    }

    private static func save(_ object: [String: Any], to path: String) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CLIError("config JSON contains unsupported values.")
        }
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
