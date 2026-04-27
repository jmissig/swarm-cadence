import Foundation

public enum IngestUpdateStatus: String, Codable {
    case updated
    case noNewCheckins = "no_new_checkins"
    case updatedPartial = "updated_partial"
    case configMissing = "config_missing"
    case sourceBlocked = "source_blocked"
    case importFailed = "import_failed"
}

public struct IngestUpdatePageResult: Codable, Equatable {
    public let offset: Int
    public let limit: Int
    public let status: ProbeStatus
    public let returnedCount: Int?
    public let totalCount: Int?
    public let rawFilePath: String
    public let manifestFilePath: String
    public let checkinIDsObserved: Int
    public let existingCheckinIDsObserved: Int
    public let checkinsInserted: Int
    public let rawFilesInserted: Int
    public let warnings: [String]
}

public struct IngestUpdateResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let adapter: SourceAdapter
    public let status: IngestUpdateStatus
    public let complete: Bool
    public let networkPerformed: Bool
    public let requestCount: Int
    public let rawDirectory: String
    public let dbPath: String
    public let limit: Int
    public let requestedPages: Int
    public let fetchedPages: Int
    public let importedPages: Int
    public let nextOffset: Int
    public let checkinsInserted: Int
    public let rawFilesInserted: Int
    public let stopReason: String?
    public let missingInputs: [String]
    public let sourceStatus: ProbeStatus?
    public let errorMessage: String?
    public let freshnessBefore: DatabaseFreshness?
    public let freshnessAfter: DatabaseFreshness?
    public let pages: [IngestUpdatePageResult]

    var exitCode: Int {
        switch status {
        case .updated, .noNewCheckins:
            return 0
        case .updatedPartial:
            return checkinsInserted > 0 || rawFilesInserted > 0 ? 0 : 1
        case .configMissing, .sourceBlocked, .importFailed:
            return 1
        }
    }
}

public enum IngestUpdate {
    public static let defaultPages = 4

    public static func update(
        account: String,
        adapter: SourceAdapter,
        config: [String: String] = [:],
        environment: [String: String],
        rawDirectory: String,
        dbPath: String,
        pages requestedPages: Int = defaultPages,
        limit: Int = RawFetch.defaultLimit,
        delayMilliseconds: Int = RawFetch.fetchPagesDefaultDelayMilliseconds,
        transport: ProbeHTTPTransport = URLSessionProbeHTTPTransport(),
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws -> IngestUpdateResult {
        let account = try AccountLabel.validate(account)
        guard adapter == .v2 else {
            throw CLIError("ingest update is currently implemented only for --adapter v2.")
        }
        guard (1...RawFetch.hardLimit).contains(limit) else {
            throw CLIError("--limit \(limit) exceeds the allowed range of 1...\(RawFetch.hardLimit).")
        }
        guard requestedPages >= 1 else {
            throw CLIError("--pages must be at least 1.")
        }
        guard requestedPages <= RawFetch.fetchPagesHardMaxPages else {
            throw CLIError("--pages \(requestedPages) exceeds the hard max of \(RawFetch.fetchPagesHardMaxPages) per invocation.")
        }
        guard delayMilliseconds >= 0 else {
            throw CLIError("--delay-ms must be at least 0.")
        }
        guard !rawDirectory.isEmpty else {
            throw CLIError("--raw-dir must not be empty.")
        }
        guard !dbPath.isEmpty else {
            throw CLIError("--db must not be empty.")
        }

        let probe = SourceProbe.probe(account: account, adapter: adapter, environment: environment, config: config)
        guard probe.status != .externalSetupRequired else {
            return result(
                account: account,
                adapter: adapter,
                status: .configMissing,
                complete: false,
                networkPerformed: false,
                requestCount: 0,
                rawDirectory: rawDirectory,
                dbPath: dbPath,
                limit: limit,
                requestedPages: requestedPages,
                fetchedPages: 0,
                importedPages: 0,
                nextOffset: 0,
                checkinsInserted: 0,
                rawFilesInserted: 0,
                stopReason: "required v2 config is missing",
                missingInputs: probe.requiredMissing,
                sourceStatus: probe.status,
                errorMessage: nil,
                freshnessBefore: nil,
                freshnessAfter: nil,
                pages: []
            )
        }

        let freshnessBefore = try SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue)
        var knownCheckinIDs = try SwarmDatabase.existingCheckinIDs(
            dbPath: dbPath,
            account: account,
            adapter: adapter.rawValue
        )
        var pageResults: [IngestUpdatePageResult] = []
        var totalCheckinsInserted = 0
        var totalCheckinsUpserted = 0
        var totalRawFilesInserted = 0
        var importedPages = 0
        var nextOffset = 0
        var complete = false
        var stopReason: String?

        for pageIndex in 0..<requestedPages {
            let offset = pageIndex * limit
            nextOffset = offset + limit

            let fetchResult: RawFetchResult
            do {
                fetchResult = try RawFetch.fetch(
                    account: account,
                    adapter: adapter,
                    config: config,
                    environment: environment,
                    outputDirectory: rawDirectory,
                    limit: limit,
                    offset: offset,
                    transport: transport
                )
            } catch let error as CLIError {
                let status: IngestUpdateStatus = totalCheckinsUpserted > 0 ? .updatedPartial : .sourceBlocked
                return result(
                    account: account,
                    adapter: adapter,
                    status: status,
                    complete: false,
                    networkPerformed: true,
                    requestCount: pageResults.count + 1,
                    rawDirectory: rawDirectory,
                    dbPath: dbPath,
                    limit: limit,
                    requestedPages: requestedPages,
                    fetchedPages: pageResults.count,
                    importedPages: importedPages,
                    nextOffset: offset,
                    checkinsInserted: totalCheckinsInserted,
                    rawFilesInserted: totalRawFilesInserted,
                    stopReason: "v2 fetch failed at offset \(offset)",
                    missingInputs: [],
                    sourceStatus: .networkError,
                    errorMessage: error.message,
                    freshnessBefore: freshnessBefore,
                    freshnessAfter: try? SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue),
                    pages: pageResults
                )
            } catch {
                let status: IngestUpdateStatus = totalCheckinsUpserted > 0 ? .updatedPartial : .sourceBlocked
                return result(
                    account: account,
                    adapter: adapter,
                    status: status,
                    complete: false,
                    networkPerformed: true,
                    requestCount: pageResults.count + 1,
                    rawDirectory: rawDirectory,
                    dbPath: dbPath,
                    limit: limit,
                    requestedPages: requestedPages,
                    fetchedPages: pageResults.count,
                    importedPages: importedPages,
                    nextOffset: offset,
                    checkinsInserted: totalCheckinsInserted,
                    rawFilesInserted: totalRawFilesInserted,
                    stopReason: "v2 fetch failed at offset \(offset)",
                    missingInputs: [],
                    sourceStatus: .networkError,
                    errorMessage: "error: \(error.localizedDescription)",
                    freshnessBefore: freshnessBefore,
                    freshnessAfter: try? SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue),
                    pages: pageResults
                )
            }

            guard fetchResult.status == .success else {
                let status: IngestUpdateStatus = totalCheckinsUpserted > 0 ? .updatedPartial : .sourceBlocked
                return result(
                    account: account,
                    adapter: adapter,
                    status: status,
                    complete: false,
                    networkPerformed: true,
                    requestCount: pageResults.count + 1,
                    rawDirectory: rawDirectory,
                    dbPath: dbPath,
                    limit: limit,
                    requestedPages: requestedPages,
                    fetchedPages: pageResults.count + 1,
                    importedPages: importedPages,
                    nextOffset: offset,
                    checkinsInserted: totalCheckinsInserted,
                    rawFilesInserted: totalRawFilesInserted,
                    stopReason: "v2 source returned \(fetchResult.status.rawValue) at offset \(offset)",
                    missingInputs: [],
                    sourceStatus: fetchResult.status,
                    errorMessage: nil,
                    freshnessBefore: freshnessBefore,
                    freshnessAfter: try? SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue),
                    pages: pageResults
                )
            }

            let rawData = try Data(contentsOf: URL(fileURLWithPath: fetchResult.rawFilePath))
            let pageIDs = V2RawCheckinsFetch.checkinIDs(data: rawData)
            let existingOnPage = pageIDs.filter { knownCheckinIDs.contains($0) }.count

            if !pageIDs.isEmpty, existingOnPage == pageIDs.count {
                complete = true
                stopReason = "stopped before import at offset \(offset): all observed check-in ids already exist locally"
                pageResults.append(IngestUpdatePageResult(
                    offset: offset,
                    limit: limit,
                    status: fetchResult.status,
                    returnedCount: fetchResult.returnedCount,
                    totalCount: fetchResult.totalCount,
                    rawFilePath: fetchResult.rawFilePath,
                    manifestFilePath: fetchResult.manifestFilePath,
                    checkinIDsObserved: pageIDs.count,
                    existingCheckinIDsObserved: existingOnPage,
                    checkinsInserted: 0,
                    rawFilesInserted: 0,
                    warnings: []
                ))
                break
            }

            let importResult: RawImportResult
            do {
                importResult = try SwarmDatabase.importRawV2Checkins(
                    dbPath: dbPath,
                    rawDirectory: rawDirectory,
                    account: account,
                    manifestFileNames: [URL(fileURLWithPath: fetchResult.manifestFilePath).lastPathComponent]
                )
            } catch let error as CLIError {
                return result(
                    account: account,
                    adapter: adapter,
                    status: .importFailed,
                    complete: false,
                    networkPerformed: true,
                    requestCount: pageResults.count + 1,
                    rawDirectory: rawDirectory,
                    dbPath: dbPath,
                    limit: limit,
                    requestedPages: requestedPages,
                    fetchedPages: pageResults.count + 1,
                    importedPages: importedPages,
                    nextOffset: nextOffset,
                    checkinsInserted: totalCheckinsInserted,
                    rawFilesInserted: totalRawFilesInserted,
                    stopReason: "import failed after offset \(offset)",
                    missingInputs: [],
                    sourceStatus: fetchResult.status,
                    errorMessage: error.message,
                    freshnessBefore: freshnessBefore,
                    freshnessAfter: try? SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue),
                    pages: pageResults
                )
            } catch {
                return result(
                    account: account,
                    adapter: adapter,
                    status: .importFailed,
                    complete: false,
                    networkPerformed: true,
                    requestCount: pageResults.count + 1,
                    rawDirectory: rawDirectory,
                    dbPath: dbPath,
                    limit: limit,
                    requestedPages: requestedPages,
                    fetchedPages: pageResults.count + 1,
                    importedPages: importedPages,
                    nextOffset: nextOffset,
                    checkinsInserted: totalCheckinsInserted,
                    rawFilesInserted: totalRawFilesInserted,
                    stopReason: "import failed after offset \(offset)",
                    missingInputs: [],
                    sourceStatus: fetchResult.status,
                    errorMessage: "error: \(error.localizedDescription)",
                    freshnessBefore: freshnessBefore,
                    freshnessAfter: try? SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue),
                    pages: pageResults
                )
            }

            importedPages += 1
            totalCheckinsUpserted += importResult.checkinsUpserted
            totalCheckinsInserted += importResult.checkinsInserted
            totalRawFilesInserted += importResult.rawFilesInserted
            knownCheckinIDs.formUnion(pageIDs)
            pageResults.append(IngestUpdatePageResult(
                offset: offset,
                limit: limit,
                status: fetchResult.status,
                returnedCount: fetchResult.returnedCount,
                totalCount: fetchResult.totalCount,
                rawFilePath: fetchResult.rawFilePath,
                manifestFilePath: fetchResult.manifestFilePath,
                checkinIDsObserved: pageIDs.count,
                existingCheckinIDsObserved: existingOnPage,
                checkinsInserted: importResult.checkinsInserted,
                rawFilesInserted: importResult.rawFilesInserted,
                warnings: importResult.warnings
            ))

            if existingOnPage > 0 {
                complete = true
                stopReason = "stopped after offset \(offset): reached existing local check-in id"
                break
            }
            if let returnedCount = fetchResult.returnedCount, returnedCount < limit {
                complete = true
                stopReason = "stopped after offset \(offset): returned \(returnedCount) below limit \(limit)"
                break
            }
            if pageIndex < requestedPages - 1, delayMilliseconds > 0 {
                sleep(TimeInterval(delayMilliseconds) / 1_000)
            }
        }

        if !complete, pageResults.count >= requestedPages {
            stopReason = "stopped after requested page cap \(requestedPages); source may have older pages not checked in this run"
        }

        let status: IngestUpdateStatus
        if totalCheckinsUpserted > 0 {
            status = complete ? .updated : .updatedPartial
        } else if complete {
            status = .noNewCheckins
        } else {
            status = .updatedPartial
        }

        return result(
            account: account,
            adapter: adapter,
            status: status,
            complete: complete,
            networkPerformed: !pageResults.isEmpty,
            requestCount: pageResults.count,
            rawDirectory: rawDirectory,
            dbPath: dbPath,
            limit: limit,
            requestedPages: requestedPages,
            fetchedPages: pageResults.count,
            importedPages: importedPages,
            nextOffset: nextOffset,
            checkinsInserted: totalCheckinsInserted,
            rawFilesInserted: totalRawFilesInserted,
            stopReason: stopReason,
            missingInputs: [],
            sourceStatus: pageResults.last?.status,
            errorMessage: nil,
            freshnessBefore: freshnessBefore,
            freshnessAfter: try SwarmDatabase.freshness(dbPath: dbPath, account: account, adapter: adapter.rawValue),
            pages: pageResults
        )
    }

    private static func result(
        account: String,
        adapter: SourceAdapter,
        status: IngestUpdateStatus,
        complete: Bool,
        networkPerformed: Bool,
        requestCount: Int,
        rawDirectory: String,
        dbPath: String,
        limit: Int,
        requestedPages: Int,
        fetchedPages: Int,
        importedPages: Int,
        nextOffset: Int,
        checkinsInserted: Int,
        rawFilesInserted: Int,
        stopReason: String?,
        missingInputs: [String],
        sourceStatus: ProbeStatus?,
        errorMessage: String?,
        freshnessBefore: DatabaseFreshness?,
        freshnessAfter: DatabaseFreshness?,
        pages: [IngestUpdatePageResult]
    ) -> IngestUpdateResult {
        IngestUpdateResult(
            schemaVersion: 1,
            command: "ingest update",
            account: account,
            adapter: adapter,
            status: status,
            complete: complete,
            networkPerformed: networkPerformed,
            requestCount: requestCount,
            rawDirectory: rawDirectory,
            dbPath: dbPath,
            limit: limit,
            requestedPages: requestedPages,
            fetchedPages: fetchedPages,
            importedPages: importedPages,
            nextOffset: nextOffset,
            checkinsInserted: checkinsInserted,
            rawFilesInserted: rawFilesInserted,
            stopReason: stopReason,
            missingInputs: missingInputs,
            sourceStatus: sourceStatus,
            errorMessage: errorMessage,
            freshnessBefore: freshnessBefore,
            freshnessAfter: freshnessAfter,
            pages: pages
        )
    }
}
