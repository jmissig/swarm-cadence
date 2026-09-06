import ArgumentParser
import Foundation
import SwarmCadenceCore

struct SetupArguments: ParsableArguments {
    @Option(help: "Account label to configure, such as default or partner. Text mode prompts when omitted.") var account: String?
    @Option(help: "Config JSON path. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(help: "Output format: auto, text, or json. JSON mode never prompts.") var format = "auto"
    @Option(name: .customLong("access-token"), help: "Existing Foursquare v2 access token. Fastest path; skips the browser OAuth flow.") var accessToken: String?
    @Option(name: .customLong("client-id"), help: "Foursquare developer app client id, used only when exchanging an authorization code.") var clientID: String?
    @Option(name: .customLong("client-secret"), help: "Foursquare developer app client secret, used only when exchanging an authorization code.") var clientSecret: String?
    @Option(name: .customLong("redirect-uri"), help: "Developer app redirect URI. Defaults to a local callback URI and must match the Foursquare app setting.") var redirectURI: String?
    @Option(name: .customLong("authorization-code"), help: "Code copied from the browser redirect after opening the printed authorization URL.") var authorizationCode: String?
    @Flag(
        name: [.customLong("non-interactive"), .customLong("no-input")],
        help: "Never prompt; require complete one-shot options. Non-TTY and JSON modes also never prompt."
    ) var nonInteractive = false
    @Flag(help: "Shortcut for --format json.") var json = false
}

struct SourceStatusArguments: ParsableArguments {
    @Option var account: String?
    @Option var format = "auto"
    @Option var config: String?
    @Flag var json = false
}

struct SourceProbeArguments: ParsableArguments {
    @Option var account: String?
    @Option var adapter = "v2"
    @Option var format = "auto"
    @Option var config: String?
    @Flag var live = false
    @Flag var json = false
}

struct RawFetchArguments: ParsableArguments {
    @Option(help: "Account label to fetch for, such as default or partner.") var account: String?
    @Option(help: "Source adapter to use. Currently only v2 is supported for live raw fetches.") var adapter = "v2"
    @Option(help: "Output format: auto, text, or json.") var format = "auto"
    @Option(help: "Config JSON path. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(name: .customLong("out"), help: "Directory for preserved raw response and manifest files. Defaults to the account raw/v2/checkins directory.") var outputDirectory: String?
    @Option(help: "Maximum check-ins to request in this page. Must be within the tool's bounded source limit.") var limit = RawFetch.defaultLimit
    @Option(help: "Source pagination offset for this one-page fetch.") var offset = 0
    @Flag(help: "Shortcut for --format json.") var json = false
}

struct RawFetchPagesArguments: ParsableArguments {
    @Option(help: "Account label to fetch for, such as default or partner.") var account: String?
    @Option(help: "Source adapter to use. Currently only v2 is supported for live raw fetches.") var adapter = "v2"
    @Option(help: "Output format: auto, text, or json.") var format = "auto"
    @Option(help: "Config JSON path. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(name: .customLong("out"), help: "Directory for preserved raw response and manifest files. Defaults to the account raw/v2/checkins directory.") var outputDirectory: String?
    @Option(help: "Maximum check-ins to request per page. Must be within the tool's bounded source limit.") var limit = RawFetch.defaultLimit
    @Option(name: .customLong("start-offset"), help: "Source pagination offset for the first page.") var startOffset = 0
    @Option(help: "Number of recent source pages to fetch before stopping unless a short page is reached first.") var pages: Int
    @Option(name: .customLong("delay-ms"), help: "Pause between page requests, in milliseconds, to keep unattended fetches polite.") var delayMilliseconds = RawFetch.fetchPagesDefaultDelayMilliseconds
    @Flag(help: "Shortcut for --format json.") var json = false
}

struct IngestUpdateArguments: ParsableArguments {
    @Option(help: "Account label to update, such as default or partner.") var account: String?
    @Option(help: "Source adapter to use. Ingest currently supports v2 only.") var adapter = "v2"
    @Option(help: "Output format: auto, text, or json.") var format = "auto"
    @Option(help: "Config JSON path. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(name: .customLong("raw-dir"), help: "Directory containing/preserving v2 raw response and manifest files. Defaults to the account raw/v2/checkins directory.") var rawDirectory: String?
    @Option(name: .customLong("db"), help: "SQLite evidence database path. Defaults to the account swarm-cadence.sqlite file.") var dbPath: String?
    @Option(help: "Maximum number of recent source pages to fetch during this update.") var pages = IngestUpdate.defaultPages
    @Option(help: "Maximum check-ins to request per source page. Must be within the tool's bounded source limit.") var limit = RawFetch.defaultLimit
    @Option(name: .customLong("delay-ms"), help: "Pause between page requests, in milliseconds, to keep unattended updates polite.") var delayMilliseconds = RawFetch.fetchPagesDefaultDelayMilliseconds
    @Flag(help: "Shortcut for --format json.") var json = false
}

struct DBImportRawArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("raw-dir")) var rawDirectory: String?
    @Option var format = "auto"
    @Flag var json = false
}

struct DBImportFilesArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var path: String?
    @Option var source = FileImportSource.foursquareExport.rawValue
    @Option var format = "auto"
    @Flag var json = false
}


struct DBMigrateArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var format = "auto"
    @Flag var json = false
}

struct DBStatsArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var format = "auto"
    @Flag var json = false
}

struct AuditOverlapArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("raw-dir")) var rawDirectory: String?
    @Option var path: String?
    @Option var examples = SourceAudit.defaultExampleLimit
    @Option var format = "auto"
    @Flag var json = false
}

struct AuditIdentityArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("same-name-nearby-meters")) var sameNameNearbyMeters = SwarmDatabase.identityAuditDefaultSameNameNearbyMeters
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}


struct QueryCategoriesArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
    @Flag(name: .customLong("no-annotations"), help: "Do not include inline annotations.") var noAnnotations = false
}

struct QueryVenuesArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(help: "Config JSON path for named geography presets. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(name: .customLong("from")) var from: String?
    @Option(name: .customLong("to")) var to: String?
    @Option var date: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("near-place")) var nearPlace: String?
    @Option(name: .customLong("area")) var area: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option var sort: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
    @Flag(name: .customLong("no-annotations"), help: "Do not include inline annotations.") var noAnnotations = false
}

struct QueryVisitsArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("venue-id")) var venueID: String?
    @Option(name: .customLong("from")) var from: String?
    @Option(name: .customLong("to")) var to: String?
    @Option var date: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
    @Flag(name: .customLong("no-annotations"), help: "Do not include inline annotations.") var noAnnotations = false
}


struct QueryCadenceArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(help: "Config JSON path for named geography presets. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(name: .customLong("venue-id")) var venueID: String?
    @Option(name: .customLong("from")) var from: String?
    @Option(name: .customLong("to")) var to: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("near-place")) var nearPlace: String?
    @Option(name: .customLong("area")) var area: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option var sort: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}


struct QueryCompareArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(help: "Config JSON path for named geography presets. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option(name: .customLong("baseline-from")) var baselineFrom: String?
    @Option(name: .customLong("baseline-to")) var baselineTo: String?
    @Option(name: .customLong("recent-from")) var recentFrom: String?
    @Option(name: .customLong("recent-to")) var recentTo: String?
    @Option(name: .customLong("as-of")) var asOf: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("near-place")) var nearPlace: String?
    @Option(name: .customLong("area")) var area: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option var sort: String?
    @Option(name: .customLong("min-baseline-visits")) var minBaselineVisits = 1
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}

struct AnnotationsAddArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("target-kind")) var targetKind: String?
    @Option(name: .customLong("target-id")) var targetID: String?
    @Option var body: String?
    @Option var source = "human"
    @Option var format = "auto"
    @Flag var json = false
}

struct AnnotationsListArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("target-kind")) var targetKind: String?
    @Option(name: .customLong("target-id")) var targetID: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}


struct AnnotationsTargetsArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(name: .customLong("kind")) var kind: String?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}

struct EvidenceWindowArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option var date: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}

struct EvidencePacketArguments: ParsableArguments {
    @Option var account: String?
    @Option(name: .customLong("db")) var dbPath: String?
    @Option(help: "Config JSON path for named geography presets. Defaults to Application Support/swarm-cadence/config.json.") var config: String?
    @Option var date: String?
    @Option(name: .customLong("baseline-from")) var baselineFrom: String?
    @Option(name: .customLong("baseline-to")) var baselineTo: String?
    @Option(name: .customLong("recent-from")) var recentFrom: String?
    @Option(name: .customLong("recent-to")) var recentTo: String?
    @Option(name: .customLong("as-of")) var asOf: String?
    @Option(name: .customLong("hour-from")) var hourFrom: Int?
    @Option(name: .customLong("hour-to")) var hourTo: Int?
    @Option var locality: String?
    @Option var region: String?
    @Option(name: .customLong("postal-code")) var postalCode: String?
    @Option(name: .customLong("country-code")) var countryCode: String?
    @Option(name: .customLong("near-place")) var nearPlace: String?
    @Option(name: .customLong("area")) var area: String?
    @Option(name: .customLong("category")) var categoryNames: [String] = []
    @Option(name: .customLong("near-lat")) var nearLatitude: Double?
    @Option(name: .customLong("near-lng")) var nearLongitude: Double?
    @Option(name: .customLong("radius-meters")) var radiusMeters: Double?
    @Option(name: .customLong("min-baseline-visits")) var minBaselineVisits = 1
    @Option var limit = SwarmDatabase.queryDefaultLimit
    @Option var format = "auto"
    @Flag var json = false
}
