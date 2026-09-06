import ArgumentParser
import Foundation
import SwarmCadenceCore

enum Formatter {
    static func render(_ result: SetupAuthResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: SourceProbeResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func render(_ result: SourceStatusResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: RawFetchResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func render(_ result: RawFetchPagesResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: IngestUpdateResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: RawImportResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(result)
            return String(decoding: data, as: UTF8.self)
        }
    }


    static func render(_ result: DatabaseMigrateResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: DatabaseStatsResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: SourceOverlapAuditResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }
    static func render(_ result: VenueIdentityAuditResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }


    static func render(_ result: QueryCategoriesResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryVenuesResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryVisitsResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryCadenceResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: QueryCompareResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: ListAnnotationKindsResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: ListAnnotationTargetsResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: AddAnnotationResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: ListAnnotationsResult, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: EvidenceWindowPacket, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    static func render(_ result: EvidencePacket, format: OutputFormat) throws -> String {
        switch format {
        case .auto, .text:
            return renderHuman(result)
        case .json:
            return try renderJSON(result)
        }
    }

    private static func renderJSON<T: Encodable>(_ result: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(result)
        return String(decoding: data, as: UTF8.self)
    }

    private static func renderHuman(_ result: SetupAuthResult) -> String {
        [
            "Auth \(result.action): \(result.status)",
            result.message,
            "Config path: \(result.configPath)",
            "Config exists: \(result.configExists ? "yes" : "no")",
            "Account: \(result.account)",
            "V2 access token: \(result.v2AccessTokenPresent ? "present" : "missing")",
            "V2 client id: \(result.v2ClientIDPresent ? "present" : "missing")",
            "V2 client secret: \(result.v2ClientSecretPresent ? "present" : "missing")",
            "V2 redirect URI: \(result.v2RedirectURIPresent ? "present" : "missing")",
            "Raw check-ins: \(result.rawDirectory)",
            "SQLite DB: \(result.sqlitePath)",
            "Network: \(result.networkPerformed ? "performed" : "not performed")",
            "Next: \(result.nextSuggestedCommand)"
        ].joined(separator: "\n")
    }

    private static func renderHuman(_ result: SourceProbeResult) -> String {
        var lines: [String] = [
            result.probeKind == "dry_config_validation" ? "source probe (dry config validation)" : "source probe (\(result.probeKind))",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "network: \(result.networkPerformed ? "performed" : "not performed")"
        ]

        if let liveProbe = result.liveProbe {
            lines.append("endpoint: \(liveProbe.endpoint)")
            if let httpStatusCode = liveProbe.httpStatusCode {
                lines.append("http_status: \(httpStatusCode)")
            }
            if let coverage = liveProbe.fieldCoverage {
                lines.append("field coverage:")
                lines.append("  - checkin id: \(coverage.checkinID ? "present" : "missing")")
                lines.append("  - createdAt: \(coverage.createdAt ? "present" : "missing")")
                lines.append("  - venue id/name: \(coverage.venueID && coverage.venueName ? "present" : "partial_or_missing")")
                lines.append("  - lat/lng: \(coverage.latitude && coverage.longitude ? "present" : "partial_or_missing")")
                lines.append("  - categories: \(coverage.categories ? "present" : "missing")")
                lines.append("  - photos: \(coverage.photosPresent ? "present" : "not_present")")
            }
        }

        if !result.requiredMissing.isEmpty {
            lines.append("missing required inputs:")
            lines.append(contentsOf: result.requiredMissing.map { "  - \($0)" })
        }

        lines.append("next actions:")
        lines.append(contentsOf: result.nextActions.map { "  - \($0)" })
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: SourceStatusResult) -> String {
        var lines: [String] = [
            "source status: \(result.status)",
            result.message,
            "config: \(result.configPath) (\(result.configExists ? "exists" : "missing"))",
            "accounts: \(result.accountCount)",
            "network: not performed"
        ]

        for account in result.accounts {
            lines.append("- \(account.label): v2=\(account.v2AccessTokenPresent ? "token_present" : "not_configured"), historysearch=\(account.historysearchConfigured ? "configured" : "not_configured"), local_evidence=\(account.localEvidenceAvailable ? "yes" : "no")")
            lines.append("  raw_v2: \(account.defaultRawV2Path) (\(account.defaultRawV2PathExists ? "exists" : "missing"))")
            lines.append("  sqlite: \(account.defaultSqliteDbPath) (\(account.defaultSqliteDbPathExists ? "exists" : "missing"))")
        }

        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: RawFetchResult) -> String {
        var lines: [String] = [
            "raw fetch",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "limit: \(result.limit)",
            "offset: \(result.offset)",
            "raw_file: \(result.rawFilePath)",
            "manifest_file: \(result.manifestFilePath)",
            "bytes: \(result.bytes)",
            "http_status: \(result.httpStatusCode)"
        ]

        if let apiMetaCode = result.apiMetaCode {
            lines.append("api_meta_code: \(apiMetaCode)")
        }
        if let returnedCount = result.returnedCount {
            lines.append("returned_count: \(returnedCount)")
        }
        if let totalCount = result.totalCount {
            lines.append("total_count: \(totalCount)")
        }

        lines.append("network: one request performed")
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: RawFetchPagesResult) -> String {
        var lines: [String] = [
            "raw fetch-pages",
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "output_dir: \(result.outputDirectory)",
            "limit: \(result.limit)",
            "start_offset: \(result.startOffset)",
            "requested_pages: \(result.requestedPages)",
            "fetched_pages: \(result.fetchedPages)",
            "request_count: \(result.requestCount)",
            "next_offset: \(result.nextOffset)",
            "network: \(result.networkPerformed ? "performed" : "not performed")"
        ]
        if let stopReason = result.stopReason {
            lines.append("stop_reason: \(stopReason)")
        }
        if let last = result.results.last {
            lines.append("last_raw_file: \(last.rawFilePath)")
            lines.append("last_manifest_file: \(last.manifestFilePath)")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: IngestUpdateResult) -> String {
        var lines: [String] = [
            result.command,
            "account: \(result.account)",
            "adapter: \(result.adapter.rawValue)",
            "status: \(result.status.rawValue)",
            "complete: \(result.complete)",
            "requests: \(result.requestCount)",
            "fetched_pages: \(result.fetchedPages)",
            "imported_pages: \(result.importedPages)",
            "checkins_inserted: \(result.checkinsInserted)",
            "raw_files_inserted: \(result.rawFilesInserted)",
            "current_through: \(result.freshnessAfter?.currentThroughISO8601 ?? "unknown")"
        ]
        if let lastFetched = result.freshnessAfter?.lastFetchedAtISO8601 {
            lines.append("last_fetched_at: \(lastFetched)")
        }
        if let lastImported = result.freshnessAfter?.lastImportedAtISO8601 {
            lines.append("last_imported_at: \(lastImported)")
        }
        if let stopReason = result.stopReason {
            lines.append("stop_reason: \(stopReason)")
        }
        if !result.missingInputs.isEmpty {
            lines.append("missing_inputs: \(result.missingInputs.joined(separator: ", "))")
        }
        if let sourceStatus = result.sourceStatus {
            lines.append("source_status: \(sourceStatus.rawValue)")
        }
        if let errorMessage = result.errorMessage {
            lines.append("error: \(errorMessage)")
        }
        lines.append("network: \(result.networkPerformed ? "performed" : "not performed")")
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: RawImportResult) -> String {
        var lines: [String] = [
            result.command,
            "account: \(result.account ?? "unspecified")",
            "db: \(result.dbPath)",
            "raw_dir: \(result.rawDirectory)",
            "raw_files_imported: \(result.rawFilesImported)",
            "raw_files_inserted: \(result.rawFilesInserted)",
            "checkins_upserted: \(result.checkinsUpserted)",
            "checkins_inserted: \(result.checkinsInserted)",
            "venues_upserted: \(result.venuesUpserted)",
            "venues_inserted: \(result.venuesInserted)",
            "categories_upserted: \(result.categoriesUpserted)",
            "categories_inserted: \(result.categoriesInserted)",
            "skipped_files: \(result.skippedFiles)",
            "skipped_checkins: \(result.skippedCheckins)",
            "network: not performed"
        ]

        if let qualityReportPath = result.qualityReportPath {
            lines.append("quality:")
            lines.append("  missing/null values: \(result.qualityIssueCount)")
            lines.append("  report: \(qualityReportPath)")
            if let account = result.account {
                lines.append("  follow-up:")
                lines.append("    swarm-cadence raw fetch-checkins --account \(account) --ids-file \(qualityReportPath)")
            }
        }

        if !result.warnings.isEmpty {
            lines.append("warnings:")
            lines.append(contentsOf: result.warnings.map { "  - \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: SourceOverlapAuditResult) -> String {
        var lines: [String] = [
            "audit overlap",
            "account: \(result.account)",
            "v2_raw_dir: \(result.v2RawDirectory)",
            "export_path: \(result.exportPath)",
            "v2_checkins: \(result.v2Checkins)",
            "export_checkins: \(result.exportCheckins)",
            "overlapping_checkins: \(result.overlappingCheckins)",
            "v2_only_checkins: \(result.v2OnlyCheckins)",
            "export_only_checkins: \(result.exportOnlyCheckins)",
            "matches:",
            "  timestamp: \(result.timestampMatches)",
            "  venue_id: \(result.venueIDMatches)",
            "  venue_name: \(result.venueNameMatches)",
            "  lat_lng: \(result.latitudeLongitudeMatches)",
            "mismatches:",
            "  timestamp: \(result.timestampMismatches)",
            "  venue_id: \(result.venueIDMismatches)",
            "  venue_name: \(result.venueNameMismatches)",
            "  lat_lng: \(result.latitudeLongitudeMismatches)",
            "categories:",
            "  v2_rows_with_categories: \(result.v2RowsWithCategories)",
            "  export_rows_with_categories: \(result.exportRowsWithCategories)",
            "  overlapping_v2_rows_with_categories: \(result.overlappingV2RowsWithCategories)",
            "  overlapping_export_rows_with_categories: \(result.overlappingExportRowsWithCategories)",
            "network: not performed"
        ]
        if !result.examples.isEmpty {
            lines.append("examples:")
            for example in result.examples {
                lines.append("  - \(example.checkinID) \(example.field): v2=\(example.v2Value ?? "null") export=\(example.exportValue ?? "null")")
            }
        }
        return lines.joined(separator: "\n")
    }


    private static func renderHuman(_ result: DatabaseMigrateResult) -> String {
        [
            "db migrate",
            "account: \(result.account ?? "all")",
            "db: \(result.dbPath)",
            "migrations: \(result.migrationsApplied.joined(separator: ", "))",
            "annotations_table_present: \(result.annotationsTablePresent ? "yes" : "no")"
        ].joined(separator: "\n")
    }

    private static func renderHuman(_ result: DatabaseStatsResult) -> String {
        var lines: [String] = [
            "db stats",
            "account: \(result.account ?? "unspecified")",
            "db: \(result.dbPath)",
            "last_successful_check: \(result.sync.lastSuccessfulCheckAt ?? "unknown")",
            "history_coverage: \(result.sync.historyCoverage)",
            "history_verified_as_of: \(result.sync.historyVerifiedAsOf ?? "unknown")",
            "unverified_source_files: \(result.unverifiedSourceFiles)",
            "raw_files: \(result.rawFiles)",
            "checkins: \(result.checkins)",
            "venues: \(result.venues)",
            "categories: \(result.categories)"
        ]

        if let minCreatedAt = result.minCreatedAt {
            lines.append("oldest_created_at: \(minCreatedAt)")
        }
        if let oldest = result.oldestCreatedAtISO8601 {
            lines.append("oldest_created_at_iso8601: \(oldest)")
        }
        if let maxCreatedAt = result.maxCreatedAt {
            lines.append("latest_created_at: \(maxCreatedAt)")
        }
        if let latest = result.latestCreatedAtISO8601 {
            lines.append("latest_created_at_iso8601: \(latest)")
        }
        if let currentThrough = result.currentThroughISO8601 {
            lines.append("current_through_iso8601: \(currentThrough)")
        }
        if let lastFetched = result.lastFetchedAtISO8601 {
            lines.append("last_fetched_at_iso8601: \(lastFetched)")
        }
        if let lastImported = result.lastImportedAtISO8601 {
            lines.append("last_imported_at_iso8601: \(lastImported)")
        }

        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: VenueIdentityAuditResult) -> String {
        var lines: [String] = [
            "audit identity",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "total_checkins: \(result.totalCheckins)",
            "total_venue_ids: \(result.totalVenueIds)",
            "same_name_same_address: groups=\(result.sameNameSameAddressCandidateGroups) venue_ids=\(result.sameNameSameAddressCandidateVenueIds) checkins=\(result.sameNameSameAddressCandidateCheckins)",
            "same_name_nearby: groups=\(result.sameNameNearbyCandidateGroups) venue_ids=\(result.sameNameNearbyCandidateVenueIds) checkins=\(result.sameNameNearbyCandidateCheckins) threshold_meters=\(Int(result.thresholds.sameNameNearbyMeters.rounded()))",
            "returned_candidates: \(result.returnedCandidates)",
            "network: not performed"
        ]
        for candidate in result.candidates {
            lines.append("- \(candidate.kind): venues=\(candidate.venueIDCount) checkins=\(candidate.totalCheckins) distance_meters=\(candidate.distanceMeters.map { String(Int($0.rounded())) } ?? "n/a")")
            lines.append("  reason: \(candidate.reason)")
            for venue in candidate.venues {
                lines.append("  - \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
                if let address = venue.address { lines.append("    address: \(address)") }
                if let locality = venue.locality {
                    let region = venue.region.map { ", \($0)" } ?? ""
                    lines.append("    location: \(locality)\(region)")
                }
                if !venue.sourceAdapters.isEmpty {
                    let adapters = venue.sourceAdapters.map { "\($0.sourceAdapter)=\($0.checkinCount)" }.joined(separator: ", ")
                    lines.append("    source_adapters: \(adapters)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }


    private static func renderHuman(_ result: QueryCategoriesResult) -> String {
        var lines: [String] = [
            "query categories",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "total_matching_categories: \(result.totalMatchingCategories)",
            "returned_categories: \(result.returnedCategories)"
        ]
        for category in result.categories {
            lines.append("- \(category.name): checkins=\(category.checkinCount) venues=\(category.venueCount) category_id=\(category.categoryID)")
            if let first = category.firstCreatedAtISO8601, let last = category.lastCreatedAtISO8601 {
                lines.append("  first_last: \(first) … \(last)")
            }
            appendAnnotations(category.annotations, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryVenuesResult) -> String {
        var lines: [String] = [
            "query venues",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "sort: \(result.sort.rawValue)",
            "order: \(result.orderLabel)",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.venues {
            lines.append("- \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
            if let locality = venue.locality {
                let region = venue.region.map { ", \($0)" } ?? ""
                lines.append("  location: \(locality)\(region)")
            }
            if let locality = venue.locality {
                let region = venue.region.map { ", \($0)" } ?? ""
                lines.append("  location: \(locality)\(region)")
            }
            if let distanceMeters = venue.distanceMeters {
                lines.append("  distance_meters: \(Int(distanceMeters.rounded()))")
            }
            if let first = venue.firstCreatedAtISO8601, let last = venue.lastCreatedAtISO8601 {
                lines.append("  first_last: \(first) … \(last)")
            }
            if !venue.categories.isEmpty {
                lines.append("  categories: \(venue.categories.joined(separator: ", "))")
            }
            appendAnnotations(venue.annotations, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryVisitsResult) -> String {
        var lines: [String] = [
            "query visits",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "total_matching_visits: \(result.totalMatchingVisits)",
            "returned_visits: \(result.returnedVisits)"
        ]
        for visit in result.visits {
            lines.append("- \(visit.createdAtISO8601 ?? "unknown_time"): \(visit.venueName ?? visit.venueID ?? "unknown venue") checkin_id=\(visit.checkinID)")
            if !visit.categories.isEmpty {
                lines.append("  categories: \(visit.categories.joined(separator: ", "))")
            }
            appendAnnotations(visit.annotations, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryCadenceResult) -> String {
        var lines: [String] = [
            "query cadence",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "sort: \(result.sort.rawValue)",
            "order: \(result.orderLabel)",
            "current_through: \(result.sourceCoverage.currentThroughISO8601 ?? "unknown")",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.venues {
            lines.append("- \(venue.name ?? venue.venueID): visits=\(venue.visitCount) dates=\(venue.distinctLocalDates) first=\(venue.firstCreatedAtISO8601 ?? "unknown") last=\(venue.lastCreatedAtISO8601 ?? "unknown") venue_id=\(venue.venueID)")
            if let distanceMeters = venue.distanceMeters {
                lines.append("  distance_meters: \(Int(distanceMeters.rounded()))")
            }
            if let days = venue.daysSinceLastVisit {
                lines.append("  days_since_last_visit: \(days)")
            }
            lines.append("  weekday_weekend: \(venue.weekdayVisitCount)/\(venue.weekendVisitCount)")
            if !venue.hourBuckets.isEmpty {
                let buckets = venue.hourBuckets.map { "\($0.hour)=\($0.visitCount)" }.joined(separator: ", ")
                lines.append("  hours: \(buckets)")
            }
            if !venue.weekdayBuckets.isEmpty {
                let buckets = venue.weekdayBuckets.map { "\($0.weekdayISO)=\($0.visitCount)" }.joined(separator: ", ")
                lines.append("  weekdays_iso: \(buckets)")
            }
            if !venue.categories.isEmpty {
                lines.append("  categories: \(venue.categories.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: QueryCompareResult) -> String {
        var lines: [String] = [
            result.command,
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "compare_by: \(result.compareBy)",
            "metric_scope: baseline_window (first/last, gaps, days-since)",
            "sort: \(result.sort.rawValue)",
            "order: \(result.orderLabel)",
            "current_through: \(result.sourceCoverage.currentThroughISO8601 ?? "unknown")",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.venues {
            lines.append("- \(venue.name ?? venue.venueID): baseline=\(venue.baselineVisitCount) recent=\(venue.recentVisitCount) previous=\(venue.previousVisitCount) last=\(venue.lastCreatedAtISO8601 ?? "unknown") venue_id=\(venue.venueID)")
            if let distanceMeters = venue.distanceMeters {
                lines.append("  distance_meters: \(Int(distanceMeters.rounded()))")
            }
            if let days = venue.daysSinceLastVisit {
                lines.append("  days_since_last_visit: \(days)")
            }
            if let maxGap = venue.gapDays.maxDays {
                lines.append("  gap_days_max: \(maxGap)")
            }
            if !venue.categories.isEmpty {
                lines.append("  categories: \(venue.categories.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }


    private static func renderHuman(_ result: ListAnnotationKindsResult) -> String {
        (["annotations kinds"] + result.kinds.map { "- \($0)" }).joined(separator: "\n")
    }

    private static func renderHuman(_ result: ListAnnotationTargetsResult) -> String {
        var lines: [String] = [
            "annotations targets",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "kind: \(result.kind ?? "all")",
            "total_matching_targets: \(result.totalMatchingTargets)",
            "returned_targets: \(result.returnedTargets)"
        ]
        for target in result.targets {
            lines.append("- \(target.kind):\(target.id) annotations=\(target.annotationCount) updated_at=\(target.lastUpdatedAtISO8601 ?? "unknown")")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: AddAnnotationResult) -> String {
        [
            "annotations add",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "annotation_id: \(result.annotation.id)",
            "target: \(result.annotation.targetKind):\(result.annotation.targetID)",
            "source: \(result.annotation.source)",
            "created_at: \(result.annotation.createdAtISO8601)",
            "body: \(result.annotation.body)"
        ].joined(separator: "\n")
    }

    private static func renderHuman(_ result: ListAnnotationsResult) -> String {
        var lines: [String] = [
            "annotations list",
            "account: \(result.account)",
            "db: \(result.dbPath)",
            "target: \(result.target.kind.map { "\($0):\(result.target.id ?? "")" } ?? "all")",
            "total_matching_annotations: \(result.totalMatchingAnnotations)",
            "returned_annotations: \(result.returnedAnnotations)"
        ]
        for annotation in result.annotations {
            lines.append("- \(annotation.targetKind):\(annotation.targetID) annotation_id=\(annotation.id) source=\(annotation.source) updated_at=\(annotation.updatedAtISO8601)")
            lines.append("  body: \(annotation.body)")
        }
        return lines.joined(separator: "\n")
    }

    private static func appendAnnotations(_ annotations: [Annotation]?, to lines: inout [String]) {
        guard let annotations, !annotations.isEmpty else { return }
        lines.append("  annotations:")
        for annotation in annotations {
            lines.append("    - \(annotation.body)")
            lines.append("      target: \(annotation.targetKind):\(annotation.targetID) annotation_id=\(annotation.id) source=\(annotation.source)")
        }
    }

    private static func renderHuman(_ result: EvidenceWindowPacket) -> String {
        var lines: [String] = [
            "evidence window",
            "schema: \(result.schema)",
            "tool_version: \(result.toolVersion)",
            "account: \(result.account)",
            "date: \(result.window.date)",
            "hour_from: \(result.window.hourFrom.map(String.init) ?? "unspecified")",
            "hour_to: \(result.window.hourTo.map(String.init) ?? "unspecified")",
            "total_matching_venues: \(result.totalMatchingVenues)",
            "returned_venues: \(result.returnedVenues)"
        ]
        for venue in result.candidateVenues {
            lines.append("- \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderHuman(_ result: EvidencePacket) -> String {
        var lines: [String] = [
            "evidence packet",
            "schema: \(result.schema)",
            "tool_version: \(result.toolVersion)",
            "account: \(result.account)",
            "date: \(result.targetWindow.date)",
            "hour_from: \(result.targetWindow.hourFrom.map(String.init) ?? "unspecified")",
            "hour_to: \(result.targetWindow.hourTo.map(String.init) ?? "unspecified")",
            "geography: \(result.geography.semantics)",
            "views: \(result.views.map { $0.label.rawValue }.joined(separator: ", "))"
        ]
        for view in result.views {
            lines.append("view: \(view.label.rawValue)")
            lines.append("  order: \(view.orderLabel)")
            lines.append("  venue_support: \(view.venueSupport.returnedVenues)/\(view.venueSupport.totalMatchingVenues)")
            lines.append("  cadence_comparison: \(view.cadenceComparison.returnedVenues)/\(view.cadenceComparison.totalMatchingVenues)")
            for venue in view.venueSupport.venues {
                lines.append("  - \(venue.name ?? venue.venueID): visits=\(venue.visitCount) venue_id=\(venue.venueID)")
                if let distanceMeters = venue.distanceMeters {
                    lines.append("    distance_meters: \(Int(distanceMeters.rounded()))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
