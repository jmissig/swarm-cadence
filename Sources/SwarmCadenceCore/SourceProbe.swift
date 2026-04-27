import Foundation

public enum SourceAdapter: String, Codable {
    case v2
    case historysearch
}

public enum OutputFormat: String {
    case human
    case json
}

public enum ProbeStatus: String, Codable {
    case externalSetupRequired = "external_setup_required"
    case readyForLiveProbe = "ready_for_live_probe"
}

public struct SourceProbeResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let probeKind: String
    public let account: String
    public let adapter: SourceAdapter
    public let status: ProbeStatus
    public let externalSetupRequired: Bool
    public let networkPerformed: Bool
    public let checkedInputs: [CheckedInput]
    public let requiredMissing: [String]
    public let optionalMissing: [String]
    public let warnings: [String]
    public let nextActions: [String]
}

public struct CheckedInput: Codable, Equatable {
    public let name: String
    public let source: InputSource
    public let required: Bool
    public let sensitive: Bool
    public let state: InputState
    public let value: String?
    public let purpose: String
}

public enum InputSource: String, Codable {
    case environment
    case configFile = "config_file"
    case notFound = "not_found"
}

public enum InputState: String, Codable {
    case presentRedacted = "present_redacted"
    case missing
    case placeholder
}

public enum SourceProbe {
    public static func probe(
        account: String,
        adapter: SourceAdapter,
        environment: [String: String],
        config: [String: String] = [:]
    ) -> SourceProbeResult {
        let accountKey = AccountLabel.environmentComponent(for: account)
        let specs = requiredInputs(accountKey: accountKey, adapter: adapter)
        let inputs = specs.map { spec in
            checkedInput(for: spec, environment: environment, config: config)
        }
        let missingRequired = inputs
            .filter { $0.required && $0.state != .presentRedacted }
            .map(\.name)
        let missingOptional = inputs
            .filter { !$0.required && $0.state != .presentRedacted }
            .map(\.name)
        let externalSetupRequired = !missingRequired.isEmpty

        return SourceProbeResult(
            schemaVersion: 1,
            command: "source probe",
            probeKind: "dry_config_validation",
            account: account,
            adapter: adapter,
            status: externalSetupRequired ? .externalSetupRequired : .readyForLiveProbe,
            externalSetupRequired: externalSetupRequired,
            networkPerformed: false,
            checkedInputs: inputs,
            requiredMissing: missingRequired,
            optionalMissing: missingOptional,
            warnings: warnings(adapter: adapter),
            nextActions: nextActions(adapter: adapter, externalSetupRequired: externalSetupRequired)
        )
    }

    private static func checkedInput(
        for spec: InputSpec,
        environment: [String: String],
        config: [String: String]
    ) -> CheckedInput {
        let source: InputSource
        let rawValue: String?

        let state: InputState

        if let value = environment[spec.name], !value.isEmpty {
            source = .environment
            rawValue = value
        } else if let value = config[spec.name], !value.isEmpty {
            source = .configFile
            rawValue = value
        } else {
            source = .notFound
            rawValue = nil
        }

        if let rawValue {
            state = isPlaceholder(rawValue) ? .placeholder : .presentRedacted
        } else {
            state = .missing
        }

        return CheckedInput(
            name: spec.name,
            source: source,
            required: spec.required,
            sensitive: true,
            state: state,
            value: state == .presentRedacted ? "<redacted>" : nil,
            purpose: spec.purpose
        )
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ||
            normalized.hasPrefix("replace-with-") ||
            normalized == "changeme" ||
            normalized == "change-me" ||
            normalized == "todo"
    }

    private static func requiredInputs(accountKey: String, adapter: SourceAdapter) -> [InputSpec] {
        switch adapter {
        case .v2:
            return [
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN",
                    required: true,
                    purpose: "OAuth access token for GET /v2/users/self/checkins"
                ),
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_ID",
                    required: false,
                    purpose: "Foursquare developer app client identifier used while obtaining a token"
                ),
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_V2_CLIENT_SECRET",
                    required: false,
                    purpose: "Foursquare developer app secret if the OAuth flow exposes one"
                ),
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_V2_REDIRECT_URI",
                    required: false,
                    purpose: "Redirect URI registered on the Foursquare developer app"
                )
            ]
        case .historysearch:
            return [
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_USERID",
                    required: true,
                    purpose: "Swarm web user id captured from an authenticated historysearch request"
                ),
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_WSID",
                    required: true,
                    purpose: "Swarm web session/request id captured from an authenticated historysearch request"
                ),
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_OAUTH_TOKEN",
                    required: true,
                    purpose: "Swarm web oauth_token parameter captured from an authenticated historysearch request"
                ),
                InputSpec(
                    name: "SWARM_CADENCE_\(accountKey)_HISTORYSEARCH_COOKIE",
                    required: false,
                    purpose: "Optional authenticated Swarm web cookie if a future live probe needs it"
                )
            ]
        }
    }

    private static func warnings(adapter: SourceAdapter) -> [String] {
        switch adapter {
        case .v2:
            return [
                "This command did not call Foursquare or validate token freshness.",
                "Do not commit OAuth tokens or developer app secrets."
            ]
        case .historysearch:
            return [
                "This command did not call Swarm web historysearch or validate session freshness.",
                "historysearch inputs are private browser-session material; keep them out of git and logs."
            ]
        }
    }

    private static func nextActions(adapter: SourceAdapter, externalSetupRequired: Bool) -> [String] {
        if externalSetupRequired {
            switch adapter {
            case .v2:
                return [
                    "Create or identify a Foursquare developer app and obtain an OAuth access token for the account.",
                    "Store the token outside git using the listed SWARM_CADENCE_<ACCOUNT>_V2_* inputs, then rerun this dry probe.",
                    "Only after this dry probe is ready should a separate live probe test GET /v2/users/self/checkins."
                ]
            case .historysearch:
                return [
                    "Log in to Swarm in a browser and capture the minimal historysearch request parameters for this account.",
                    "Store userid, wsid, and oauth_token outside git using the listed SWARM_CADENCE_<ACCOUNT>_HISTORYSEARCH_* inputs, then rerun this dry probe.",
                    "Only after this dry probe is ready should a separate live probe test Swarm web historysearch."
                ]
            }
        }

        return [
            "Config shape is present for a future explicit live probe; this command still performed no network calls.",
            "Next implementation step is a minimal live credential probe with redacted errors and fixture capture."
        ]
    }
}

struct InputSpec {
    let name: String
    let required: Bool
    let purpose: String
}

enum AccountLabel {
    static func validate(_ label: String?) throws -> String {
        guard let label, !label.isEmpty else {
            throw CLIError("missing required --account <label>.")
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard label.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CLIError("--account may contain only letters, numbers, underscores, and hyphens.")
        }

        return label
    }

    static func environmentComponent(for label: String) -> String {
        label
            .uppercased()
            .map { $0 == "-" ? "_" : $0 }
            .map(String.init)
            .joined()
    }
}
