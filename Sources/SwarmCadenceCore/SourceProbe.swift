import Foundation

public enum SourceAdapter: String, Codable {
    case v2
    case historysearch
}

public enum OutputFormat: String {
    case text
    case json
}

public enum ProbeStatus: String, Codable {
    case externalSetupRequired = "external_setup_required"
    case readyForLiveProbe = "ready_for_live_probe"
    case success
    case blocked
    case unauthorized
    case paymentRequired = "payment_required"
    case schemaUnexpected = "schema_unexpected"
    case networkError = "network_error"
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
    public let liveProbe: LiveProbeResult?
    public let warnings: [String]
    public let nextActions: [String]
}

public struct LiveProbeResult: Codable, Equatable {
    public let adapter: SourceAdapter
    public let endpoint: String
    public let method: String
    public let apiVersion: String?
    public let limit: Int?
    public let status: ProbeStatus
    public let networkPerformed: Bool
    public let httpStatusCode: Int?
    public let apiMetaCode: Int?
    public let message: String?
    public let fieldCoverage: V2FieldCoverage?
    public let countDateHints: V2CountDateHints?
}

public struct V2FieldCoverage: Codable, Equatable {
    public let sampleReturned: Bool
    public let checkinID: Bool
    public let createdAt: Bool
    public let venueID: Bool
    public let venueName: Bool
    public let latitude: Bool
    public let longitude: Bool
    public let categories: Bool
    public let photosObject: Bool
    public let photosPresent: Bool
}

public struct V2CountDateHints: Codable, Equatable {
    public let totalCount: Int?
    public let returnedCount: Int
    public let sampleCreatedAt: Int?
    public let sampleCreatedAtISO8601: String?
    public let categoryCount: Int?
    public let photoCount: Int?
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
    public static let v2APIVersion = "20260427"

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
            liveProbe: nil,
            warnings: warnings(adapter: adapter),
            nextActions: nextActions(adapter: adapter, externalSetupRequired: externalSetupRequired)
        )
    }

    public static func liveProbe(
        account: String,
        adapter: SourceAdapter,
        environment: [String: String],
        config: [String: String] = [:],
        transport: ProbeHTTPTransport = URLSessionProbeHTTPTransport()
    ) -> SourceProbeResult {
        let dryResult = probe(
            account: account,
            adapter: adapter,
            environment: environment,
            config: config
        )

        guard adapter == .v2 else {
            return dryResult.replacing(
                probeKind: "live_source_probe",
                status: .blocked,
                liveProbe: LiveProbeResult(
                    adapter: adapter,
                    endpoint: "not_implemented",
                    method: "GET",
                    apiVersion: nil,
                    limit: nil,
                    status: .blocked,
                    networkPerformed: false,
                    httpStatusCode: nil,
                    apiMetaCode: nil,
                    message: "Live probe is currently implemented only for the v2 adapter.",
                    fieldCoverage: nil,
                    countDateHints: nil
                ),
                warnings: dryResult.warnings + ["Live historysearch probing is not implemented yet."],
                nextActions: ["Use --adapter v2 for the live source probe, or rerun without --live for dry config validation."]
            )
        }

        let accountKey = AccountLabel.environmentComponent(for: account)
        let tokenName = "SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN"
        guard let accessToken = resolvedInputValue(named: tokenName, environment: environment, config: config) else {
            return dryResult.replacing(
                probeKind: "live_v2_checkins",
                warnings: dryResult.warnings + ["Live probe was requested but not performed because required v2 token input is missing or placeholder."],
                nextActions: dryResult.nextActions
            )
        }

        let liveResult = V2CheckinsProbe.perform(accessToken: accessToken, transport: transport)
        return dryResult.replacing(
            probeKind: "live_v2_checkins",
            status: liveResult.status,
            externalSetupRequired: false,
            networkPerformed: liveResult.networkPerformed,
            liveProbe: liveResult,
            warnings: liveCredentialWarnings(adapter: adapter) + liveWarnings(for: liveResult),
            nextActions: liveNextActions(for: liveResult)
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

    private static func resolvedInputValue(
        named name: String,
        environment: [String: String],
        config: [String: String]
    ) -> String? {
        let rawValue: String?
        if let value = environment[name], !value.isEmpty {
            rawValue = value
        } else if let value = config[name], !value.isEmpty {
            rawValue = value
        } else {
            rawValue = nil
        }

        guard let rawValue, !isPlaceholder(rawValue) else {
            return nil
        }
        return rawValue
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
                    "Only after this dry probe is ready should --live test GET /v2/users/self/checkins."
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
            "Config shape is present for an explicit --live probe; this command still performed no network calls.",
            "Run --live only when you want the minimal read-only source viability check."
        ]
    }

    private static func liveWarnings(for result: LiveProbeResult) -> [String] {
        switch result.status {
        case .success:
            if result.fieldCoverage?.sampleReturned == false {
                return ["The live v2 request succeeded, but no sample check-in was returned for field coverage."]
            }
            return ["The live v2 request was read-only and used limit=1; it did not ingest or persist data."]
        case .unauthorized:
            return ["The v2 token was rejected or lacks access to the account's check-in history."]
        case .paymentRequired:
            return ["The v2 endpoint appears gated or payment-required for this token/app."]
        case .schemaUnexpected:
            return ["The v2 response did not match the expected checkins envelope shape."]
        case .networkError:
            return ["The v2 request failed before a usable HTTP response was parsed."]
        default:
            return ["The live v2 probe did not establish usable check-in-history access."]
        }
    }

    private static func liveCredentialWarnings(adapter: SourceAdapter) -> [String] {
        switch adapter {
        case .v2:
            return ["Do not commit OAuth tokens or developer app secrets."]
        case .historysearch:
            return ["historysearch inputs are private browser-session material; keep them out of git and logs."]
        }
    }

    private static func liveNextActions(for result: LiveProbeResult) -> [String] {
        switch result.status {
        case .success:
            return [
                "Use this v2 path as the likely first ingest adapter, after adding raw preservation and SQLite storage.",
                "Keep future ingest/backfill separate from source probe and continue using explicit account/config inputs."
            ]
        case .unauthorized:
            return [
                "Check that the token belongs to the requested account and has access to user check-ins.",
                "If v2 remains unauthorized, test the historysearch fallback with a separate explicit live probe."
            ]
        case .paymentRequired:
            return [
                "Treat v2 OAuth as blocked for now and prepare the narrow Swarm web historysearch fallback.",
                "Keep export/import available for bootstrap and reconciliation."
            ]
        case .schemaUnexpected:
            return [
                "Inspect the redacted response shape manually before adding ingest code.",
                "Do not build a parser or schema migration until the source envelope is understood."
            ]
        default:
            return [
                "Rerun the live probe after checking local connectivity and token setup.",
                "No database or remote state was changed."
            ]
        }
    }
}

extension SourceProbeResult {
    func replacing(
        probeKind: String? = nil,
        status: ProbeStatus? = nil,
        externalSetupRequired: Bool? = nil,
        networkPerformed: Bool? = nil,
        liveProbe: LiveProbeResult? = nil,
        warnings: [String]? = nil,
        nextActions: [String]? = nil
    ) -> SourceProbeResult {
        SourceProbeResult(
            schemaVersion: schemaVersion,
            command: command,
            probeKind: probeKind ?? self.probeKind,
            account: account,
            adapter: adapter,
            status: status ?? self.status,
            externalSetupRequired: externalSetupRequired ?? self.externalSetupRequired,
            networkPerformed: networkPerformed ?? self.networkPerformed,
            checkedInputs: checkedInputs,
            requiredMissing: requiredMissing,
            optionalMissing: optionalMissing,
            liveProbe: liveProbe ?? self.liveProbe,
            warnings: warnings ?? self.warnings,
            nextActions: nextActions ?? self.nextActions
        )
    }
}

public struct ProbeHTTPResponse {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

public protocol ProbeHTTPTransport {
    func perform(_ request: URLRequest) throws -> ProbeHTTPResponse
}

public final class URLSessionProbeHTTPTransport: ProbeHTTPTransport {
    public init() {}

    public func perform(_ request: URLRequest) throws -> ProbeHTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<ProbeHTTPResponse, Error>!

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result = .failure(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                result = .failure(ProbeTransportError("missing HTTP response"))
                return
            }

            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let key = key as? String {
                    headers[key] = String(describing: value)
                }
            }
            result = .success(ProbeHTTPResponse(statusCode: httpResponse.statusCode, data: data ?? Data(), headers: headers))
        }.resume()

        semaphore.wait()
        return try result.get()
    }
}

struct ProbeTransportError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

enum V2CheckinsProbe {
    static let endpoint = "https://api.foursquare.com/v2/users/self/checkins"

    static func makeRequest(accessToken: String, apiVersion: String = SourceProbe.v2APIVersion) throws -> URLRequest {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "oauth_token", value: accessToken)
        ]

        guard let url = components?.url else {
            throw ProbeTransportError("could not construct v2 checkins URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("swarm-cadence source-probe", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func perform(accessToken: String, transport: ProbeHTTPTransport) -> LiveProbeResult {
        do {
            let request = try makeRequest(accessToken: accessToken)
            let response = try transport.perform(request)
            return parse(data: response.data, httpStatusCode: response.statusCode, secrets: [accessToken])
        } catch {
            return LiveProbeResult(
                adapter: .v2,
                endpoint: endpoint,
                method: "GET",
                apiVersion: SourceProbe.v2APIVersion,
                limit: 1,
                status: .networkError,
                networkPerformed: true,
                httpStatusCode: nil,
                apiMetaCode: nil,
                message: Redactor.redact(error.localizedDescription, secrets: [accessToken]),
                fieldCoverage: nil,
                countDateHints: nil
            )
        }
    }

    static func parse(data: Data, httpStatusCode: Int, secrets: [String] = []) -> LiveProbeResult {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let meta = object?["meta"] as? [String: Any]
        let metaCode = meta?["code"] as? Int
        let redactedMessage = Redactor.redact(
            (meta?["errorDetail"] as? String) ?? (meta?["errorType"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: httpStatusCode),
            secrets: secrets
        )

        let status = statusFor(httpStatusCode: httpStatusCode, metaCode: metaCode)
        guard status == .success else {
            return LiveProbeResult(
                adapter: .v2,
                endpoint: endpoint,
                method: "GET",
                apiVersion: SourceProbe.v2APIVersion,
                limit: 1,
                status: status,
                networkPerformed: true,
                httpStatusCode: httpStatusCode,
                apiMetaCode: metaCode,
                message: redactedMessage,
                fieldCoverage: nil,
                countDateHints: nil
            )
        }

        guard let checkins = (object?["response"] as? [String: Any])?["checkins"] as? [String: Any],
              let items = checkins["items"] as? [[String: Any]] else {
            return LiveProbeResult(
                adapter: .v2,
                endpoint: endpoint,
                method: "GET",
                apiVersion: SourceProbe.v2APIVersion,
                limit: 1,
                status: .schemaUnexpected,
                networkPerformed: true,
                httpStatusCode: httpStatusCode,
                apiMetaCode: metaCode,
                message: "Expected response.checkins.items array was not present.",
                fieldCoverage: nil,
                countDateHints: nil
            )
        }

        let sample = items.first
        let venue = sample?["venue"] as? [String: Any]
        let location = venue?["location"] as? [String: Any]
        let categories = venue?["categories"] as? [[String: Any]]
        let photos = sample?["photos"] as? [String: Any]
        let photoItems = photos?["items"] as? [[String: Any]]
        let photoCount = photos?["count"] as? Int ?? photoItems?.count
        let createdAt = sample?["createdAt"] as? Int

        let coverage = V2FieldCoverage(
            sampleReturned: sample != nil,
            checkinID: nonEmptyString(sample?["id"]),
            createdAt: createdAt != nil,
            venueID: nonEmptyString(venue?["id"]),
            venueName: nonEmptyString(venue?["name"]),
            latitude: location?["lat"] is NSNumber || location?["lat"] is Double || location?["lat"] is Int,
            longitude: location?["lng"] is NSNumber || location?["lng"] is Double || location?["lng"] is Int,
            categories: !(categories?.isEmpty ?? true),
            photosObject: photos != nil,
            photosPresent: (photoCount ?? 0) > 0 || !(photoItems?.isEmpty ?? true)
        )

        let hints = V2CountDateHints(
            totalCount: checkins["count"] as? Int,
            returnedCount: items.count,
            sampleCreatedAt: createdAt,
            sampleCreatedAtISO8601: createdAt.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval($0))) },
            categoryCount: categories?.count,
            photoCount: photoCount
        )

        return LiveProbeResult(
            adapter: .v2,
            endpoint: endpoint,
            method: "GET",
            apiVersion: SourceProbe.v2APIVersion,
            limit: 1,
            status: .success,
            networkPerformed: true,
            httpStatusCode: httpStatusCode,
            apiMetaCode: metaCode,
            message: sample == nil ? "v2 checkins request succeeded; no sample check-in returned." : "v2 checkins request succeeded.",
            fieldCoverage: coverage,
            countDateHints: hints
        )
    }

    private static func statusFor(httpStatusCode: Int, metaCode: Int?) -> ProbeStatus {
        let code = metaCode ?? httpStatusCode
        switch code {
        case 200..<300:
            return (200..<300).contains(httpStatusCode) ? .success : .blocked
        case 401, 403:
            return .unauthorized
        case 402:
            return .paymentRequired
        default:
            return (200..<300).contains(httpStatusCode) ? .schemaUnexpected : .blocked
        }
    }

    private static func nonEmptyString(_ value: Any?) -> Bool {
        guard let string = value as? String else {
            return false
        }
        return !string.isEmpty
    }
}

enum Redactor {
    static func redact(_ value: String, secrets: [String]) -> String {
        secrets.reduce(value) { current, secret in
            guard !secret.isEmpty else {
                return current
            }
            return current.replacingOccurrences(of: secret, with: "<redacted>")
        }
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
