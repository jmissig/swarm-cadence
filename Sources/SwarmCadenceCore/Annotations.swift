import Foundation
import GRDB

public struct Annotation: Codable, Equatable {
    public let id: Int64
    public let account: String
    public let targetKind: String
    public let targetID: String
    public let body: String
    public let source: String
    public let createdAtISO8601: String
    public let updatedAtISO8601: String
}

public struct AnnotationTarget: Codable, Equatable {
    public let kind: String?
    public let id: String?
}

struct AnnotationLookupTarget: Hashable {
    let kind: String
    let id: String
}


public struct ListAnnotationKindsResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let kinds: [String]
}

public struct AnnotationTargetUsage: Codable, Equatable {
    public let kind: String
    public let id: String
    public let annotationCount: Int
    public let lastUpdatedAtISO8601: String?
}

public struct ListAnnotationTargetsResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let kind: String?
    public let totalMatchingTargets: Int
    public let returnedTargets: Int
    public let targets: [AnnotationTargetUsage]
}

public struct AddAnnotationResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let annotation: Annotation
}

public struct ListAnnotationsResult: Codable, Equatable {
    public let schemaVersion: Int
    public let command: String
    public let account: String
    public let dbPath: String
    public let target: AnnotationTarget
    public let totalMatchingAnnotations: Int
    public let returnedAnnotations: Int
    public let annotations: [Annotation]
}

extension SwarmDatabase {

    public static func listAnnotationKinds() -> ListAnnotationKindsResult {
        ListAnnotationKindsResult(
            schemaVersion: 1,
            command: "annotations kinds",
            kinds: allowedAnnotationTargetKinds.sorted()
        )
    }

    public static func listAnnotationTargets(
        dbPath: String,
        account: String,
        kind: String? = nil,
        limit: Int = queryDefaultLimit
    ) throws -> ListAnnotationTargetsResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try AccountLabel.validate(account)
        try validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
        let normalizedKind = try kind.map(validateAnnotationTargetKind)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw CLIError("SQLite DB does not exist: \(dbPath).")
        }

        let dbQueue = try openReadOnlyDatabase(path: dbPath)
        return try dbQueue.read { db in
            guard try annotationsTableExists(db: db) else {
                return ListAnnotationTargetsResult(
                    schemaVersion: 1,
                    command: "annotations targets",
                    account: account,
                    dbPath: dbPath,
                    kind: normalizedKind,
                    totalMatchingTargets: 0,
                    returnedTargets: 0,
                    targets: []
                )
            }

            let total = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM (
                    SELECT target_kind, target_id
                    FROM annotations
                    WHERE account = ?
                      AND (? IS NULL OR target_kind = ?)
                    GROUP BY target_kind, target_id
                )
                """,
                arguments: [account, normalizedKind, normalizedKind]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT target_kind, target_id, COUNT(*) AS annotation_count, MAX(updated_at) AS last_updated_at
                FROM annotations
                WHERE account = ?
                  AND (? IS NULL OR target_kind = ?)
                GROUP BY target_kind, target_id
                ORDER BY last_updated_at DESC, target_kind ASC, target_id ASC
                LIMIT ?
                """,
                arguments: [account, normalizedKind, normalizedKind, limit]
            )
            let targets = rows.map { row in
                AnnotationTargetUsage(
                    kind: row["target_kind"],
                    id: row["target_id"],
                    annotationCount: row["annotation_count"],
                    lastUpdatedAtISO8601: row["last_updated_at"]
                )
            }
            return ListAnnotationTargetsResult(
                schemaVersion: 1,
                command: "annotations targets",
                account: account,
                dbPath: dbPath,
                kind: normalizedKind,
                totalMatchingTargets: total,
                returnedTargets: targets.count,
                targets: targets
            )
        }
    }
    public static func addAnnotation(
        dbPath: String,
        account: String,
        targetKind: String,
        targetID: String,
        body: String,
        source: String = "human",
        now: Date = Date()
    ) throws -> AddAnnotationResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try AccountLabel.validate(account)
        let targetKind = try validateAnnotationTargetKind(targetKind)
        let targetID = try validateAnnotationField(targetID, optionName: "--target-id")
        let body = try validateAnnotationField(body, optionName: "--body")
        let source = try validateAnnotationField(source, optionName: "--source")
        let timestamp = annotationISO8601String(now)

        let dbQueue = try openDatabase(path: dbPath)
        try migrate(dbQueue)

        return try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO annotations (
                    account, target_kind, target_id, body, source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [account, targetKind, targetID, body, source, timestamp, timestamp]
            )
            let id = db.lastInsertedRowID
            let annotation = try fetchAnnotation(db: db, id: id)
            return AddAnnotationResult(
                schemaVersion: 1,
                command: "annotations add",
                account: account,
                dbPath: dbPath,
                annotation: annotation
            )
        }
    }

    public static func listAnnotations(
        dbPath: String,
        account: String,
        targetKind: String? = nil,
        targetID: String? = nil,
        limit: Int = queryDefaultLimit
    ) throws -> ListAnnotationsResult {
        guard !dbPath.isEmpty else {
            throw CLIError("missing required --db <path>.")
        }
        let account = try AccountLabel.validate(account)
        try validateQueryOptions(fromCreatedAt: nil, toCreatedAt: nil, limit: limit)
        let target = try validateOptionalAnnotationTarget(kind: targetKind, id: targetID)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw CLIError("SQLite DB does not exist: \(dbPath).")
        }

        let dbQueue = try openReadOnlyDatabase(path: dbPath)

        return try dbQueue.read { db in
            guard try annotationsTableExists(db: db) else {
                return ListAnnotationsResult(
                    schemaVersion: 1,
                    command: "annotations list",
                    account: account,
                    dbPath: dbPath,
                    target: target,
                    totalMatchingAnnotations: 0,
                    returnedAnnotations: 0,
                    annotations: []
                )
            }

            let total = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM annotations
                WHERE account = ?
                  AND (? IS NULL OR target_kind = ?)
                  AND (? IS NULL OR target_id = ?)
                """,
                arguments: [account, target.kind, target.kind, target.id, target.id]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, account, target_kind, target_id, body, source, created_at, updated_at
                FROM annotations
                WHERE account = ?
                  AND (? IS NULL OR target_kind = ?)
                  AND (? IS NULL OR target_id = ?)
                ORDER BY updated_at DESC, id DESC
                LIMIT ?
                """,
                arguments: [account, target.kind, target.kind, target.id, target.id, limit]
            )

            let annotations = rows.map(annotation(row:))
            return ListAnnotationsResult(
                schemaVersion: 1,
                command: "annotations list",
                account: account,
                dbPath: dbPath,
                target: target,
                totalMatchingAnnotations: total,
                returnedAnnotations: annotations.count,
                annotations: annotations
            )
        }
    }

    private static func fetchAnnotation(db: Database, id: Int64) throws -> Annotation {
        let row = try Row.fetchOne(
            db,
            sql: """
            SELECT id, account, target_kind, target_id, body, source, created_at, updated_at
            FROM annotations
            WHERE id = ?
            """,
            arguments: [id]
        ).orThrow("annotation row was not available after insert.")
        return annotation(row: row)
    }
}

func fetchAnnotations(
    db: Database,
    account: String,
    targets: Set<AnnotationLookupTarget>
) throws -> [AnnotationLookupTarget: [Annotation]] {
    guard !targets.isEmpty else { return [:] }
    guard try annotationsTableExists(db: db) else { return [:] }

    let targetsJSON = try annotationTargetsJSON(targets)
    let rows = try Row.fetchAll(
        db,
        sql: """
        WITH requested(kind, id) AS (
            SELECT json_extract(value, '$.kind'), json_extract(value, '$.id')
            FROM json_each(?)
        )
        SELECT n.id, n.account, n.target_kind, n.target_id, n.body, n.source, n.created_at, n.updated_at
        FROM annotations n
        JOIN requested r ON r.kind = n.target_kind AND r.id = n.target_id
        WHERE n.account = ?
        ORDER BY n.updated_at DESC, n.id DESC
        """,
        arguments: [targetsJSON, account]
    )

    var annotationsByTarget: [AnnotationLookupTarget: [Annotation]] = [:]
    for row in rows {
        let annotation = annotation(row: row)
        annotationsByTarget[
            AnnotationLookupTarget(kind: annotation.targetKind, id: annotation.targetID),
            default: []
        ].append(annotation)
    }
    return annotationsByTarget
}


private func annotationsTableExists(db: Database) throws -> Bool {
    try Int.fetchOne(
        db,
        sql: """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = 'annotations'
        """
    ) != nil
}


let allowedAnnotationTargetKinds: Set<String> = [
    "venue",
    "checkin",
    "category",
    "geography",
    "context",
    "window"
]

private func validateAnnotationTargetKind(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else {
        throw CLIError("--target-kind must not be empty.")
    }
    guard allowedAnnotationTargetKinds.contains(normalized) else {
        throw CLIError("unsupported --target-kind '\(value)'. Use one of: \(allowedAnnotationTargetKinds.sorted().joined(separator: ", ")).")
    }
    return normalized
}

private func validateAnnotationField(_ value: String, optionName: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw CLIError("\(optionName) must not be empty.")
    }
    return trimmed
}

private func validateOptionalAnnotationTarget(kind: String?, id: String?) throws -> AnnotationTarget {
    switch (kind, id) {
    case (.none, .none):
        return AnnotationTarget(kind: nil, id: nil)
    case (.some(let kind), .some(let id)):
        return AnnotationTarget(
            kind: try validateAnnotationTargetKind(kind),
            id: try validateAnnotationField(id, optionName: "--target-id")
        )
    case (.some, .none):
        throw CLIError("--target-kind requires --target-id.")
    case (.none, .some):
        throw CLIError("--target-id requires --target-kind.")
    }
}

private func annotation(row: Row) -> Annotation {
    Annotation(
        id: row["id"],
        account: row["account"],
        targetKind: row["target_kind"],
        targetID: row["target_id"],
        body: row["body"],
        source: row["source"],
        createdAtISO8601: row["created_at"],
        updatedAtISO8601: row["updated_at"]
    )
}

private func annotationTargetsJSON(_ targets: Set<AnnotationLookupTarget>) throws -> String {
    let objects = targets
        .sorted { left, right in
            left.kind == right.kind ? left.id < right.id : left.kind < right.kind
        }
        .map { ["kind": $0.kind, "id": $0.id] }
    let data = try JSONSerialization.data(withJSONObject: objects, options: [])
    return String(decoding: data, as: UTF8.self)
}

private func annotationISO8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
