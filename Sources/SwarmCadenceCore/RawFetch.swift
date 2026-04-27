import CryptoKit
import Foundation

public struct RawFetchResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let adapter: SourceAdapter
    public let status: ProbeStatus
    public let networkPerformed: Bool
    public let requestCount: Int
    public let endpoint: String
    public let method: String
    public let apiVersion: String
    public let limit: Int
    public let fetchedAt: String
    public let httpStatusCode: Int
    public let apiMetaCode: Int?
    public let returnedCount: Int?
    public let totalCount: Int?
    public let rawFilePath: String
    public let manifestFilePath: String
    public let bytes: Int
    public let sha256: String
}

public struct RawFetchManifest: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let adapter: SourceAdapter
    public let account: String
    public let endpoint: String
    public let method: String
    public let apiVersion: String
    public let limit: Int
    public let pageMarker: String
    public let fetchedAt: String
    public let httpStatusCode: Int
    public let apiMetaCode: Int?
    public let returnedCount: Int?
    public let totalCount: Int?
    public let rawFileName: String
    public let rawBytes: Int
    public let rawSha256: String
}

public enum RawFetch {
    public static let defaultLimit = 100
    public static let hardLimit = 100
    static let pageMarker = "page1"

    public static func fetch(
        account: String,
        adapter: SourceAdapter,
        config: [String: String] = [:],
        environment: [String: String],
        outputDirectory: String,
        limit: Int = defaultLimit,
        transport: ProbeHTTPTransport = URLSessionProbeHTTPTransport(),
        fetchedAt: Date = Date()
    ) throws -> RawFetchResult {
        let account = try AccountLabel.validate(account)
        guard adapter == .v2 else {
            throw CLIError("raw fetch is currently implemented only for --adapter v2.")
        }
        guard (1...hardLimit).contains(limit) else {
            throw CLIError("--limit \(limit) exceeds the allowed range of 1...\(hardLimit).")
        }
        guard !outputDirectory.isEmpty else {
            throw CLIError("missing required --out <dir>.")
        }

        let accountKey = AccountLabel.environmentComponent(for: account)
        let tokenName = "SWARM_CADENCE_\(accountKey)_V2_ACCESS_TOKEN"
        guard let accessToken = resolvedInputValue(named: tokenName, environment: environment, config: config) else {
            throw CLIError("missing required \(tokenName).")
        }

        let request = try V2RawCheckinsFetch.makeRequest(accessToken: accessToken, limit: limit)
        let response: ProbeHTTPResponse
        do {
            response = try transport.perform(request)
        } catch {
            throw CLIError("v2 raw fetch failed: \(Redactor.redact(error.localizedDescription, secrets: [accessToken]))")
        }

        let outputDirectoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        let fetchedAtString = iso8601Formatter.string(from: fetchedAt)
        let baseName = "\(filenameTimestampFormatter.string(from: fetchedAt))-\(adapter.rawValue)-\(account)-checkins-\(pageMarker)-limit\(limit)"
        let rawFileURL = try uniqueFileURL(in: outputDirectoryURL, baseName: baseName, extension: "raw.json")
        guard FileManager.default.createFile(atPath: rawFileURL.path, contents: response.data) else {
            throw CLIError("could not write raw response file at \(rawFileURL.path).")
        }

        let sha256 = sha256Hex(response.data)
        let summary = V2RawCheckinsFetch.parseSummary(data: response.data, httpStatusCode: response.statusCode)
        let status = V2RawCheckinsFetch.statusFor(httpStatusCode: response.statusCode, metaCode: summary.apiMetaCode)
        let manifestFileURL = rawFileURL.deletingPathExtension().deletingPathExtension().appendingPathExtension("manifest.json")
        let manifest = RawFetchManifest(
            schemaVersion: 1,
            command: "raw fetch",
            adapter: adapter,
            account: account,
            endpoint: V2RawCheckinsFetch.endpoint,
            method: "GET",
            apiVersion: SourceProbe.v2APIVersion,
            limit: limit,
            pageMarker: pageMarker,
            fetchedAt: fetchedAtString,
            httpStatusCode: response.statusCode,
            apiMetaCode: summary.apiMetaCode,
            returnedCount: summary.returnedCount,
            totalCount: summary.totalCount,
            rawFileName: rawFileURL.lastPathComponent,
            rawBytes: response.data.count,
            rawSha256: sha256
        )
        try writeManifest(manifest, to: manifestFileURL)

        return RawFetchResult(
            schemaVersion: 1,
            command: "raw fetch",
            account: account,
            adapter: adapter,
            status: status,
            networkPerformed: true,
            requestCount: 1,
            endpoint: V2RawCheckinsFetch.endpoint,
            method: "GET",
            apiVersion: SourceProbe.v2APIVersion,
            limit: limit,
            fetchedAt: fetchedAtString,
            httpStatusCode: response.statusCode,
            apiMetaCode: summary.apiMetaCode,
            returnedCount: summary.returnedCount,
            totalCount: summary.totalCount,
            rawFilePath: rawFileURL.path,
            manifestFilePath: manifestFileURL.path,
            bytes: response.data.count,
            sha256: sha256
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeManifest(_ manifest: RawFetchManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    private static func uniqueFileURL(in directory: URL, baseName: String, extension pathExtension: String) throws -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension(pathExtension)
            suffix += 1
            if suffix > 1000 {
                throw CLIError("could not choose a collision-free raw output filename in \(directory.path).")
            }
        }
        return candidate
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

    private static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ||
            normalized.hasPrefix("replace-with-") ||
            normalized == "changeme" ||
            normalized == "change-me" ||
            normalized == "todo"
    }

    private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static var filenameTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter
    }
}

struct V2RawSummary: Equatable {
    let apiMetaCode: Int?
    let returnedCount: Int?
    let totalCount: Int?
}

enum V2RawCheckinsFetch {
    static let endpoint = "https://api.foursquare.com/v2/users/self/checkins"

    static func makeRequest(
        accessToken: String,
        limit: Int,
        apiVersion: String = SourceProbe.v2APIVersion
    ) throws -> URLRequest {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
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
        request.setValue("swarm-cadence raw-fetch", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func parseSummary(data: Data, httpStatusCode: Int) -> V2RawSummary {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let meta = object?["meta"] as? [String: Any]
        let checkins = (object?["response"] as? [String: Any])?["checkins"] as? [String: Any]
        let items = checkins?["items"] as? [[String: Any]]

        return V2RawSummary(
            apiMetaCode: meta?["code"] as? Int,
            returnedCount: items?.count,
            totalCount: checkins?["count"] as? Int
        )
    }

    static func statusFor(httpStatusCode: Int, metaCode: Int?) -> ProbeStatus {
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
}
